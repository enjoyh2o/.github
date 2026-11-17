import SwiftUI

/// The chess board.
///
/// It can be used four ways, and they can be mixed freely:
///   * Look at it — large pieces with outlines, strong square contrast, and
///     marks for the last move, a check, and where a picked-up piece can go.
///   * Tap a piece, then tap where it should go.
///   * Slide a finger across it: each square says what is on it and plays a
///     note placed left-to-right and low-to-high to match its position.
///   * With VoiceOver: every square is a labelled button, rotors jump between
///     your pieces, the opponent's pieces and the legal destinations, and
///     each square offers actions to hear its attackers or its moves.
struct ChessBoardView: View {
    let table: GameTable<ChessSession>

    @Environment(AppServices.self) private var services
    @Namespace private var rotorSpace
    /// The piece that has been picked up, if any.
    @State private var selected: Square?

    var body: some View {
        let snapshot = table.snapshot
        let position = snapshot.position
        let flipped = snapshot.viewer == .black
        let destinations = Set(selected.map { position.legalMoves(from: $0).map(\.to) } ?? [])
        let settings = services.settings

        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let cell = side / 8

            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { column in
                            let square = ChessBoardView.square(row: row, column: column, flipped: flipped)
                            ChessSquareView(
                                square: square,
                                piece: position[square],
                                cell: cell,
                                theme: settings.boardTheme,
                                pieceStyle: settings.pieceStyle,
                                isSelected: selected == square,
                                isDestination: destinations.contains(square),
                                isLastMove: snapshot.lastMove?.from == square || snapshot.lastMove?.to == square,
                                isCheck: snapshot.checkedKing == square,
                                fileLabel: row == 7 ? String(Square.fileLetter(square.file)) : nil,
                                rankLabel: column == 0 ? String(square.rank + 1) : nil
                            )
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(label(for: square, in: snapshot))
                            .accessibilityValue(value(for: square, in: snapshot, destinations: destinations))
                            .accessibilityAddTraits(selected == square ? [.isButton, .isSelected] : .isButton)
                            .accessibilityAction { tapped(square) }
                            .accessibilityAction(named: "Hear attackers and defenders") {
                                table.send("what is on \(square.name)", echo: false)
                            }
                            .accessibilityAction(named: "Hear this piece's moves") {
                                table.send("moves for \(square.name)", echo: false)
                            }
                            .accessibilityRotorEntry(id: square.index, in: rotorSpace)
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.6), lineWidth: 2))
            .explorable(
                columns: 8, rows: 8, cell: CGSize(width: cell, height: cell),
                entered: { column, row in
                    describeUnderFinger(ChessBoardView.square(row: row, column: column, flipped: flipped),
                                        row: row, column: column)
                },
                tapped: { column, row in
                    tapped(ChessBoardView.square(row: row, column: column, flipped: flipped))
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chess board")
        .accessibilityRotor("My pieces") {
            rotorEntries(for: snapshot.viewer ?? position.sideToMove, in: snapshot)
        }
        .accessibilityRotor("Opponent's pieces") {
            rotorEntries(for: (snapshot.viewer ?? position.sideToMove).opposite, in: snapshot)
        }
        .accessibilityRotor("Possible moves") {
            ForEach(destinations.sorted(), id: \.index) { square in
                AccessibilityRotorEntry(Text(label(for: square, in: snapshot)), id: square.index, in: rotorSpace)
            }
        }
        .onChange(of: position) {
            // Whatever was picked up belongs to a position that is gone.
            selected = nil
        }
    }

    // MARK: Layout

    /// The square shown at a screen row and column. White sits at the bottom
    /// unless the player has the black pieces.
    static func square(row: Int, column: Int, flipped: Bool) -> Square {
        flipped
            ? Square(file: 7 - column, rank: row)
            : Square(file: column, rank: 7 - row)
    }

    // MARK: Words for VoiceOver

    private func label(for square: Square, in snapshot: ChessSnapshot) -> String {
        let perspective = ChessPerspective(viewer: snapshot.viewer)
        let content: String
        if let piece = snapshot.position[square] {
            content = "\(perspective.owner(piece.color)) \(piece.kind.name)"
        } else {
            content = "empty"
        }
        return SpeechFormatter.spoken("\(square.name), \(content)", naming: services.settings.squareNaming)
    }

    private func value(for square: Square, in snapshot: ChessSnapshot, destinations: Set<Square>) -> String {
        var notes: [String] = []
        if selected == square { notes.append("picked up") }
        if destinations.contains(square) { notes.append("can move here") }
        if snapshot.checkedKing == square { notes.append("in check") }
        if snapshot.lastMove?.to == square { notes.append("just moved") }
        return notes.joined(separator: ", ")
    }

    @AccessibilityRotorContentBuilder
    private func rotorEntries(for color: PieceColor, in snapshot: ChessSnapshot) -> some AccessibilityRotorContent {
        ForEach(snapshot.position.squares(color: color), id: \.index) { square in
            AccessibilityRotorEntry(Text(label(for: square, in: snapshot)), id: square.index, in: rotorSpace)
        }
    }

    // MARK: Touch

    private func describeUnderFinger(_ square: Square, row: Int, column: Int) {
        let snapshot = table.snapshot
        let occupied = snapshot.position[square] != nil
        services.feedback.square(
            column: column, row: 7 - row, columns: 8, rows: 8,
            occupied: occupied, settings: services.settings
        )
        let perspective = ChessPerspective(viewer: snapshot.viewer)
        if let piece = snapshot.position[square] {
            table.whisper("\(square.name), \(perspective.owner(piece.color)) \(piece.kind.name)")
        } else {
            table.whisper("\(square.name), empty")
        }
    }

    /// Pick up, put down, or move. Every outcome is sent to the session as
    /// ordinary words, so touch and speech can never disagree.
    private func tapped(_ square: Square) {
        let snapshot = table.snapshot
        let position = snapshot.position

        if let from = selected {
            selected = nil
            if from == square {
                table.whisper("Put down.")
                return
            }
            let isLegal = position.legalMoves(from: from).contains { $0.to == square }
            if !isLegal, let piece = position[square], piece.color == position.sideToMove {
                pickUp(square)      // switched to another of your own pieces
                return
            }
            // Legal moves are played; anything else gets a spoken explanation.
            table.send(from.name + square.name, echo: false)
            return
        }

        let canPickUp = position[square]?.color == position.sideToMove
            && !snapshot.isComputerTurn && snapshot.outcome == nil
        if canPickUp {
            pickUp(square)
        } else {
            table.send("what is on \(square.name)", echo: false)
        }
    }

    private func pickUp(_ square: Square) {
        selected = square
        table.send("moves for \(square.name)", echo: false)
    }
}

/// One square of the board with everything drawn on it.
struct ChessSquareView: View {
    let square: Square
    let piece: Piece?
    let cell: CGFloat
    let theme: BoardTheme
    let pieceStyle: PieceStyle
    let isSelected: Bool
    let isDestination: Bool
    let isLastMove: Bool
    let isCheck: Bool
    let fileLabel: String?
    let rankLabel: String?

    var body: some View {
        let background = square.isLight ? theme.lightSquare : theme.darkSquare
        let ink = square.isLight ? theme.darkSquare : theme.lightSquare

        ZStack {
            Rectangle().fill(background)

            // Marks use shape as well as colour: a frame for the last move,
            // a thick frame for the picked-up piece, a ring for check.
            if isLastMove {
                Rectangle().strokeBorder(theme.lastMove, lineWidth: max(3, cell * 0.08))
            }
            if isCheck {
                Circle().strokeBorder(theme.check, lineWidth: max(4, cell * 0.1)).padding(cell * 0.04)
            }
            if isSelected {
                Rectangle().strokeBorder(theme.selection, lineWidth: max(4, cell * 0.12))
            }

            if let piece {
                ChessPieceView(piece: piece, size: cell, style: pieceStyle)
            }

            if isDestination {
                if piece == nil {
                    Circle()
                        .fill(theme.selection)
                        .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                        .frame(width: cell * 0.3, height: cell * 0.3)
                } else {
                    // A capture: ring the piece instead of covering it.
                    Circle()
                        .strokeBorder(theme.selection, lineWidth: max(3, cell * 0.09))
                        .padding(cell * 0.05)
                }
            }

            if let rankLabel {
                Text(rankLabel)
                    .font(.system(size: max(9, cell * 0.2), weight: .bold))
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(cell * 0.04)
            }
            if let fileLabel {
                Text(fileLabel)
                    .font(.system(size: max(9, cell * 0.2), weight: .bold))
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(cell * 0.04)
            }
        }
        .frame(width: cell, height: cell)
    }
}
