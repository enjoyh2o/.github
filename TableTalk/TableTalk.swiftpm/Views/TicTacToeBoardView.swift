import SwiftUI

/// The Tic-Tac-Toe board. Squares are numbered 1 to 9 in reading order and
/// also have names ("top left", "centre"), which is how they are spoken.
struct TicTacToeBoardView: View {
    let table: GameTable<TicTacToeSession>

    @Environment(AppServices.self) private var services

    var body: some View {
        let snapshot = table.snapshot

        GeometryReader { proxy in
            let cell = min(proxy.size.width, proxy.size.height) / 3

            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { column in
                            let square = row * 3 + column + 1
                            TicTacToeSquareView(
                                mark: snapshot.board[square],
                                isWinning: snapshot.winningSquares.contains(square),
                                isLastMove: snapshot.lastMove == square,
                                size: cell
                            )
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(snapshot.label(for: square))
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { take(square) }
                        }
                    }
                }
            }
            .frame(width: cell * 3, height: cell * 3)
            .explorable(
                columns: 3, rows: 3, cell: CGSize(width: cell, height: cell),
                entered: { column, row in
                    let square = row * 3 + column + 1
                    services.feedback.square(
                        column: column, row: 2 - row, columns: 3, rows: 3,
                        occupied: snapshot.board[square] != nil,
                        settings: services.settings
                    )
                    table.whisper(snapshot.label(for: square))
                },
                tapped: { column, row in take(row * 3 + column + 1) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tic-Tac-Toe board")
    }

    private func take(_ square: Int) {
        table.send(TicTacToeBoard.name(of: square), echo: false)
    }
}

struct TicTacToeSquareView: View {
    let mark: TicTacToeBoard.Mark?
    let isWinning: Bool
    let isLastMove: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            Rectangle().fill(isWinning ? Color.accentColor.opacity(0.25) : Color(uiColor: .secondarySystemBackground))
            Rectangle().strokeBorder(Color.primary, lineWidth: isWinning ? max(4, size * 0.06) : 1.5)
            if let mark {
                Text(mark.name)
                    .font(.system(size: size * 0.62, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.primary)
            }
            if isLastMove && !isWinning {
                Rectangle()
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: max(3, size * 0.04), dash: [8, 5]))
                    .padding(size * 0.05)
            }
        }
        .frame(width: size, height: size)
    }
}
