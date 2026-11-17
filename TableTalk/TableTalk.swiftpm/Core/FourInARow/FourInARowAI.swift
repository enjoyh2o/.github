import Foundation

/// The computer opponent for Four in a Row.
///
/// Everything here is a pure function of a board value, so the session can
/// hand a copy of the board to a background thread and wait for a column to
/// come back.
enum FourInARowAI {

    typealias Side = FourInARowBoard.Side

    /// How many positions the Sharp level may look at for one move.
    ///
    /// A count rather than a stopwatch, for two reasons: the same position
    /// always gets the same answer, and the wait stays short even in a debug
    /// build, where this code runs many times slower than in a release build.
    static let sharpNodeBudget = 60_000

    /// A smaller allowance for hints, which are worked out while the player waits.
    static let hintNodeBudget = 20_000

    /// Picks the computer's column (1 to 7), or nil if the board is full.
    static func chooseColumn<R: RandomNumberGenerator>(
        on board: FourInARowBoard,
        for side: Side,
        difficulty: Difficulty,
        using rng: inout R
    ) -> Int? {
        let open = board.openColumns
        guard !open.isEmpty else { return nil }
        let wins = board.winningColumns(for: side)
        let blocks = board.winningColumns(for: side.other)

        switch difficulty {
        case .gentle:
            // Friendly, not hopeless: it usually finishes its own four and
            // usually stops the player's, and otherwise drops a piece anywhere.
            if let win = wins.randomElement(using: &rng), Int.random(in: 1...10, using: &rng) <= 9 { return win }
            if let block = blocks.randomElement(using: &rng), Int.random(in: 1...4, using: &rng) <= 3 { return block }
            return open.randomElement(using: &rng)

        case .steady, .sharp:
            if let win = wins.randomElement(using: &rng) { return win }
            // With two or more ways to lose the game is gone against good
            // play, but blocking one of them still makes the player find it.
            if let block = blocks.randomElement(using: &rng) { return block }
            let best = difficulty == .steady
                ? strongestColumns(on: board, for: side, maxDepth: 4, nodeBudget: .max)
                : strongestColumns(on: board, for: side, maxDepth: .max, nodeBudget: sharpNodeBudget)
            // Equally good moves are chosen between at random so that the
            // computer does not play the same game every time.
            return best.randomElement(using: &rng)
        }
    }

    /// The move to suggest as a hint. Always the same for the same position.
    static func bestColumn(on board: FourInARowBoard, for side: Side) -> Int? {
        if let win = board.winningColumns(for: side).first { return win }
        if let block = board.winningColumns(for: side.other).first { return block }
        return strongestColumns(on: board, for: side, maxDepth: .max, nodeBudget: hintNodeBudget).first
    }

    /// Every column that looks best for `side`, centre first.
    ///
    /// The search looks one move further ahead each time round, and stops
    /// when it reaches `maxDepth`, when the game is decided, or when the node
    /// budget runs out. The answer from the last finished round is used.
    static func strongestColumns(
        on board: FourInARowBoard,
        for side: Side,
        maxDepth: Int,
        nodeBudget: Int
    ) -> [Int] {
        let start = Position(board, toMove: side)
        var search = Search(nodesLeft: nodeBudget)
        // If not even one round fits the budget, any open column will do.
        var best = centreFirst.filter { start.landingCells & Position.column($0) != 0 }
        let deepest = min(maxDepth, FourInARowBoard.columnCount * FourInARowBoard.rowCount - start.pieceCount)
        var depth = 1
        while depth <= deepest, let found = search.bestColumns(in: start, depth: depth) {
            best = found.columns
            // A forced win or loss has been seen to the end. Looking deeper
            // could not change it.
            if abs(found.score) >= decided { break }
            depth += 1
        }
        return best.map { $0 + 1 }
    }

    // MARK: Search

    /// Columns by index (0 to 6), middle first. Central pieces take part in
    /// the most lines, so trying them first finds good moves early and lets
    /// the search skip more of the rest.
    private static let centreFirst = [3, 2, 4, 1, 5, 0, 6]

    /// Scores are from the point of view of whoever is about to move. A win
    /// scores `winScore` minus the number of pieces on the board, so quicker
    /// wins score higher and, for the loser, slower losses hurt less. It is
    /// far above anything `estimate()` can return, so a real win is never
    /// mistaken for a promising position.
    private static let winScore = 10_000
    private static let decided = winScore - 100
    private static let unbounded = 1_000_000

    /// A look-ahead search with a running node count.
    private struct Search {
        var nodesLeft: Int
        var ranOut: Bool { nodesLeft < 0 }

        /// The best columns for the side to move, looking `depth` moves
        /// ahead, or nil if the budget ran out before the answer was complete.
        mutating func bestColumns(in position: Position, depth: Int) -> (columns: [Int], score: Int)? {
            let landing = position.landingCells
            let winningNow = position.winningCells(for: position.mine)
            var best = -unbounded
            var columns: [Int] = []
            for column in centreFirst {
                let cell = landing & Position.column(column)
                if cell == 0 { continue }
                let value: Int
                if winningNow & cell != 0 {
                    value = winScore - position.pieceCount
                } else {
                    // The window starts just below the best score so far:
                    // enough to tell "better", "just as good" and "worse"
                    // apart without working out exactly how much worse.
                    value = -score(position.playing(cell), depth: depth - 1, alpha: -unbounded, beta: 1 - best)
                }
                if ranOut { return nil }
                if value > best {
                    best = value
                    columns = [column]
                } else if value == best {
                    columns.append(column)
                }
            }
            return (columns, best)
        }

        /// Negamax with alpha-beta pruning: the value of `position` for the
        /// side to move, given that anything outside `alpha...beta` no longer
        /// matters to the moves already examined further up.
        mutating func score(_ position: Position, depth: Int, alpha: Int, beta: Int) -> Int {
            nodesLeft -= 1
            if nodesLeft < 0 { return 0 }

            let landing = position.landingCells
            if landing == 0 { return 0 }    // board full: a draw
            if position.winningCells(for: position.mine) & landing != 0 {
                return winScore - position.pieceCount
            }
            if depth <= 0 { return position.estimate() }

            // If the opponent is one move from winning, only the moves that
            // block are worth looking at.
            let threats = position.winningCells(for: position.all ^ position.mine) & landing
            let choices = threats == 0 ? landing : threats

            var alpha = alpha
            for column in centreFirst {
                let cell = choices & Position.column(column)
                if cell == 0 { continue }
                let value = -score(position.playing(cell), depth: depth - 1, alpha: -beta, beta: -alpha)
                if value > alpha { alpha = value }
                if alpha >= beta { break }
            }
            return alpha
        }
    }

    // MARK: Packed board

    /// The board squeezed into two 64-bit numbers, for the search only.
    ///
    /// The search visits tens of thousands of positions per move, so it needs
    /// a board that copies instantly and can test for four in a row with a
    /// handful of bit operations.
    ///
    /// Each column gets 7 bits, bottom cell first: column 0 uses bits 0 to 6,
    /// column 1 bits 7 to 13, and so on. Only 6 of the 7 are real cells. The
    /// spare bit on top always stays empty, so a line can never appear to run
    /// off the top of one column and continue at the bottom of the next.
    ///
    /// With this layout a neighbour is always a fixed number of bits away:
    /// 1 up the column, 7 across the row, 8 up a rising diagonal and 6 down
    /// a falling one.
    private struct Position {
        /// Pieces belonging to the side about to move.
        var mine: UInt64
        /// Every piece on the board.
        var all: UInt64
        var pieceCount: Int

        init(mine: UInt64, all: UInt64, pieceCount: Int) {
            self.mine = mine
            self.all = all
            self.pieceCount = pieceCount
        }

        init(_ board: FourInARowBoard, toMove side: Side) {
            self.init(mine: 0, all: 0, pieceCount: 0)
            for column in 1...FourInARowBoard.columnCount {
                for (index, piece) in board.pieces(inColumn: column).enumerated() {
                    let bit = UInt64(1) << UInt64(7 * (column - 1) + index)
                    all |= bit
                    if piece == side { mine |= bit }
                    pieceCount += 1
                }
            }
        }

        /// The bottom cell of every column.
        static let bottomRow: UInt64 = (0..<7).reduce(0) { $0 | UInt64(1) << UInt64(7 * $1) }
        /// The 42 real cells.
        static let wholeBoard: UInt64 = bottomRow * 0b111111
        /// Rows 1, 3 and 5, and rows 2, 4 and 6, as the player counts them.
        static let oddRows: UInt64 = bottomRow * 0b010101
        static let evenRows: UInt64 = bottomRow * 0b101010
        /// The middle five columns, the middle three and the middle one. A
        /// piece scores a point for each band it is in, so the centre column
        /// is worth three and the two edge columns nothing.
        static let middleBands: [UInt64] = [
            column(1) | column(2) | column(3) | column(4) | column(5),
            column(2) | column(3) | column(4),
            column(3),
        ]

        /// The six real cells of one column (index 0 to 6).
        static func column(_ index: Int) -> UInt64 {
            UInt64(0b111111) << UInt64(7 * index)
        }

        /// One bit per column that still has room: the cell a piece dropped
        /// there would land in. Adding 1 at the foot of a column carries up
        /// through its pieces and comes to rest on the first empty cell.
        var landingCells: UInt64 {
            (all + Position.bottomRow) & Position.wholeBoard
        }

        /// The position after the side to move plays on `cell`. The opponent
        /// is then the side to move, so their pieces become `mine`.
        func playing(_ cell: UInt64) -> Position {
            Position(mine: all ^ mine, all: all | cell, pieceCount: pieceCount + 1)
        }

        /// The empty cells that would complete four in a row for the owner
        /// of `pieces`, whether or not a piece could land there yet.
        func winningCells(for pieces: UInt64) -> UInt64 {
            let found = Position.gaps(in: pieces, step: 1) | Position.gaps(in: pieces, step: 7)
                | Position.gaps(in: pieces, step: 6) | Position.gaps(in: pieces, step: 8)
            return found & Position.wholeBoard & ~all
        }

        /// Cells that have three of `pieces` lined up with them in one
        /// direction. Shifting the whole board by `step` slides every piece
        /// onto its neighbour, so "three in line next to this cell" becomes
        /// one AND of three shifted copies.
        private static func gaps(in pieces: UInt64, step: UInt64) -> UInt64 {
            let twoBehind = (pieces << step) & (pieces << (2 * step))
            let twoAhead = (pieces >> step) & (pieces >> (2 * step))
            return (twoBehind & (pieces << (3 * step)))     // X X X _
                | (twoBehind & (pieces >> step))            // X X _ X
                | (twoAhead & (pieces << step))             // X _ X X
                | (twoAhead & (pieces >> (3 * step)))       // _ X X X
        }

        /// A rough value for a position the search has no time to play out.
        ///
        /// Mostly it counts who has more empty cells that would complete a
        /// four. Those on a player's "own" rows count three times over: late
        /// in the game, when the columns fill up and nobody has a free
        /// choice left, the player who moved first is the one who lands on
        /// rows 1, 3 and 5, and the other player on rows 2, 4 and 6. A small
        /// preference for pieces near the middle settles the rest.
        func estimate() -> Int {
            let theirs = all ^ mine
            let myChances = winningCells(for: mine)
            let theirChances = winningCells(for: theirs)
            // Whoever is to move with an even number of pieces down moved first.
            let movedFirst = pieceCount % 2 == 0
            let myRows = movedFirst ? Position.oddRows : Position.evenRows
            let theirRows = movedFirst ? Position.evenRows : Position.oddRows

            var score = 10 * (myChances.nonzeroBitCount - theirChances.nonzeroBitCount)
            score += 20 * ((myChances & myRows).nonzeroBitCount - (theirChances & theirRows).nonzeroBitCount)
            for band in Position.middleBands {
                score += (mine & band).nonzeroBitCount - (theirs & band).nonzeroBitCount
            }
            return score
        }
    }
}
