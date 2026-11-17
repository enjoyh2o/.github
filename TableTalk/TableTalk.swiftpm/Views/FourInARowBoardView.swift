import SwiftUI

/// The Four in a Row board: seven columns, six rows, pieces fall to the
/// bottom. Tap anywhere in a column to drop a piece there, slide a finger
/// to hear each space, or use VoiceOver — every space is labelled.
struct FourInARowBoardView: View {
    let table: GameTable<FourInARowSession>

    @Environment(AppServices.self) private var services

    private let columns = FourInARowBoard.columnCount
    private let rows = FourInARowBoard.rowCount

    var body: some View {
        let snapshot = table.snapshot

        GeometryReader { proxy in
            let cell = min(proxy.size.width / CGFloat(columns), proxy.size.height / CGFloat(rows))

            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { rowFromTop in
                    HStack(spacing: 0) {
                        ForEach(0..<columns, id: \.self) { columnIndex in
                            let space = self.space(column: columnIndex, rowFromTop: rowFromTop)
                            FourInARowSpaceView(
                                side: snapshot.board[column: space.column, row: space.row],
                                isWinning: snapshot.winningCells.contains(space),
                                isLastMove: snapshot.lastMove == space,
                                size: cell
                            )
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(snapshot.label(for: space))
                            .accessibilityHint("Double tap to drop a piece in column \(space.column)")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { drop(in: space.column) }
                            .accessibilityAction(named: "Read this column") {
                                table.send("read column \(space.column)", echo: false)
                            }
                        }
                    }
                }
            }
            .frame(width: cell * CGFloat(columns), height: cell * CGFloat(rows))
            .background(Color(red: 0.11, green: 0.27, blue: 0.58), in: RoundedRectangle(cornerRadius: 14))
            .explorable(
                columns: columns, rows: rows, cell: CGSize(width: cell, height: cell),
                entered: { column, rowFromTop in
                    let space = self.space(column: column, rowFromTop: rowFromTop)
                    services.feedback.square(
                        column: column, row: rows - 1 - rowFromTop, columns: columns, rows: rows,
                        occupied: snapshot.board[column: space.column, row: space.row] != nil,
                        settings: services.settings
                    )
                    table.whisper(snapshot.label(for: space))
                },
                tapped: { column, _ in drop(in: column + 1) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(CGFloat(columns) / CGFloat(rows), contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Four in a Row board, 7 columns by 6 rows")
    }

    /// Columns count from 1 at the left, rows from 1 at the bottom — the way
    /// the player says them.
    private func space(column: Int, rowFromTop: Int) -> FourInARowBoard.Cell {
        FourInARowBoard.Cell(column: column + 1, row: rows - rowFromTop)
    }

    private func drop(in column: Int) {
        table.send("column \(column)", echo: false)
    }
}

/// One space on the board. The two sides differ in shape as well as colour:
/// Red has a ring inside it, Yellow a diamond.
struct FourInARowSpaceView: View {
    let side: FourInARowBoard.Side?
    let isWinning: Bool
    let isLastMove: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            switch side {
            case .none:
                Circle().fill(Color(uiColor: .systemBackground))
            case .some(.red):
                Circle().fill(Color(red: 0.82, green: 0.10, blue: 0.14))
                Circle().stroke(Color.white, lineWidth: max(2, size * 0.06)).padding(size * 0.2)
            case .some(.yellow):
                Circle().fill(Color(red: 1.0, green: 0.84, blue: 0.10))
                Rectangle()
                    .fill(Color.black)
                    .frame(width: size * 0.22, height: size * 0.22)
                    .rotationEffect(.degrees(45))
            }
            if isWinning {
                Circle().strokeBorder(Color.white, lineWidth: max(4, size * 0.1))
            } else if isLastMove {
                Circle().strokeBorder(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: max(2, size * 0.05), dash: [6, 4]))
            }
        }
        .padding(size * 0.08)
        .frame(width: size, height: size)
    }
}
