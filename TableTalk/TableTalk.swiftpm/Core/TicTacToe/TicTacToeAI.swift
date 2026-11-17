import Foundation

/// The computer opponent for Tic-Tac-Toe.
///
/// Everything here is a pure function of a board value, so the session can
/// hand a copy of the board to a background thread and wait for a square to
/// come back.
enum TicTacToeAI {

    typealias Mark = TicTacToeBoard.Mark

    /// Picks the computer's square (1 to 9), or nil if the board is full.
    static func chooseSquare<R: RandomNumberGenerator>(
        on board: TicTacToeBoard,
        for mark: Mark,
        difficulty: Difficulty,
        using rng: inout R
    ) -> Int? {
        let free = board.freeSquares
        guard !free.isEmpty else { return nil }

        switch difficulty {
        case .gentle:
            // Never misses its own three in a row, but half the time it
            // plays anywhere at all, which leaves the player real chances.
            if let win = board.winningSquares(for: mark).randomElement(using: &rng) { return win }
            if Bool.random(using: &rng) { return free.randomElement(using: &rng) }
            return sensibleSquare(on: board, for: mark, using: &rng)

        case .steady:
            return sensibleSquare(on: board, for: mark, using: &rng)

        case .sharp:
            // Equally good squares are chosen between at random so that the
            // computer does not play the same game every time.
            return favourites(among: perfectSquares(on: board, for: mark)).randomElement(using: &rng)
        }
    }

    /// The move to suggest as a hint. Always the same for the same position.
    static func bestSquare(on board: TicTacToeBoard, for mark: Mark) -> Int? {
        let perfect = perfectSquares(on: board, for: mark)
        return preference.first(where: perfect.contains)
    }

    /// Every square that gives `mark` the best result they can force:
    /// a win if there is one, otherwise a draw, otherwise the slowest loss.
    static func perfectSquares(on board: TicTacToeBoard, for mark: Mark) -> [Int] {
        var board = board
        let placed = board.markCount
        var best = -unbounded
        var squares: [Int] = []
        for square in board.freeSquares {
            board.place(mark, on: square)
            // The window starts just below the best score so far: enough to
            // tell "better", "just as good" and "worse" apart.
            let score = -value(of: &board, toMove: mark.other, placed: placed + 1, alpha: -unbounded, beta: 1 - best)
            board.clear(square)
            if score > best {
                best = score
                squares = [square]
            } else if score == best {
                squares.append(square)
            }
        }
        return squares
    }

    // MARK: Rules of thumb

    private static let corners: Set<Int> = [1, 3, 7, 9]

    /// Centre, then corners, then edges: the order of how many lines run
    /// through each square (four, three and two).
    private static let preference = [5, 1, 3, 7, 9, 2, 4, 6, 8]

    /// Plays the way most people do: finish three in a row, stop the
    /// opponent's, and otherwise prefer the centre, then a corner. It does
    /// not look ahead, so a two-way trap still catches it.
    private static func sensibleSquare<R: RandomNumberGenerator>(
        on board: TicTacToeBoard,
        for mark: Mark,
        using rng: inout R
    ) -> Int? {
        if let win = board.winningSquares(for: mark).randomElement(using: &rng) { return win }
        if let block = board.winningSquares(for: mark.other).randomElement(using: &rng) { return block }
        let free = board.freeSquares
        if free.contains(5) { return 5 }
        if let corner = free.filter(corners.contains).randomElement(using: &rng) { return corner }
        return free.randomElement(using: &rng)
    }

    /// Among squares that are equally good with perfect play, the centre and
    /// corners give an imperfect opponent more ways to go wrong.
    private static func favourites(among squares: [Int]) -> [Int] {
        let strong = squares.filter { $0 == 5 || corners.contains($0) }
        return strong.isEmpty ? squares : strong
    }

    // MARK: Minimax

    private static let unbounded = 100

    /// The value of the position for `mark`, who is about to move: positive
    /// if they can force a win, negative if they must lose, zero for a draw.
    /// Quicker wins score higher, so the search never dawdles over a win or
    /// gives up early on a loss.
    ///
    /// This is minimax written the "negamax" way: what is good for one player
    /// is exactly as bad for the other, so each level just flips the sign.
    /// `alpha` and `beta` let it stop looking at a move as soon as it is
    /// clearly worse than one already found.
    private static func value(
        of board: inout TicTacToeBoard,
        toMove mark: Mark,
        placed: Int,
        alpha: Int,
        beta: Int
    ) -> Int {
        // The opponent moved last. If that made three in a row, we have lost.
        if board.hasLine(of: mark.other) { return placed - 10 }
        if placed == 9 { return 0 }

        var alpha = alpha
        for square in 1...9 where board[square] == nil {
            board.place(mark, on: square)
            let score = -value(of: &board, toMove: mark.other, placed: placed + 1, alpha: -beta, beta: -alpha)
            board.clear(square)
            if score > alpha { alpha = score }
            if alpha >= beta { break }
        }
        return alpha
    }
}
