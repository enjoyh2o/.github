import Foundation

/// The upright grid for Four in a Row: 7 columns by 6 rows. A piece dropped
/// into a column falls to the lowest free space.
///
/// Columns and rows are numbered the way the player says them: columns 1 to 7
/// from the left, rows 1 to 6 from the bottom. Using the spoken numbers in
/// code as well means no sentence ever has to add or subtract one.
struct FourInARowBoard: Equatable, Sendable {

    static let columnCount = 7
    static let rowCount = 6

    /// The two players. Red always moves first.
    enum Side: String, CaseIterable, Sendable {
        case red, yellow

        var other: Side { self == .red ? .yellow : .red }
        var name: String { self == .red ? "Red" : "Yellow" }
    }

    /// One space on the board.
    struct Cell: Hashable, Sendable {
        var column: Int
        var row: Int
    }

    /// A finished game: who made four in a row, and where.
    struct Win: Equatable, Sendable {
        var side: Side
        /// Each winning line, starting from its left end (or its bottom end
        /// for a line straight up). Nearly always one line, but a single
        /// piece can complete two at once.
        var lines: [[Cell]]

        /// Every space on a winning line, for highlighting.
        var cells: [Cell] {
            var seen: Set<Cell> = []
            return lines.joined().filter { seen.insert($0).inserted }
        }
    }

    /// The pieces in each column, bottom first. A column really is a stack:
    /// dropping a piece appends to it, and taking a move back removes the last.
    private var stacks: [[Side]] = Array(repeating: [], count: FourInARowBoard.columnCount)

    // MARK: Looking

    /// The piece on a space, or nil if the space is empty or off the board.
    subscript(column column: Int, row row: Int) -> Side? {
        guard (1...Self.columnCount).contains(column), row >= 1 else { return nil }
        let stack = stacks[column - 1]
        return row <= stack.count ? stack[row - 1] : nil
    }

    /// The pieces in one column, bottom first.
    func pieces(inColumn column: Int) -> [Side] {
        (1...Self.columnCount).contains(column) ? stacks[column - 1] : []
    }

    func height(ofColumn column: Int) -> Int {
        pieces(inColumn: column).count
    }

    func isFull(column: Int) -> Bool {
        height(ofColumn: column) >= Self.rowCount
    }

    /// Columns that can still take a piece, left to right.
    var openColumns: [Int] {
        (1...Self.columnCount).filter { !isFull(column: $0) }
    }

    var fullColumns: [Int] {
        (1...Self.columnCount).filter { isFull(column: $0) }
    }

    var pieceCount: Int {
        stacks.reduce(0) { $0 + $1.count }
    }

    var isFull: Bool {
        pieceCount == Self.columnCount * Self.rowCount
    }

    /// Where one side's pieces are, column by column and bottom first.
    func cells(of side: Side) -> [Cell] {
        var found: [Cell] = []
        for column in 1...Self.columnCount {
            for (index, piece) in stacks[column - 1].enumerated() where piece == side {
                found.append(Cell(column: column, row: index + 1))
            }
        }
        return found
    }

    // MARK: Changing

    /// Drops a piece and returns where it landed, or nil (changing nothing)
    /// if the column is full or does not exist.
    @discardableResult
    mutating func drop(_ side: Side, inColumn column: Int) -> Cell? {
        guard (1...Self.columnCount).contains(column), !isFull(column: column) else { return nil }
        stacks[column - 1].append(side)
        return Cell(column: column, row: stacks[column - 1].count)
    }

    /// Lifts the top piece back out of a column. Used to take a move back.
    @discardableResult
    mutating func removeTopPiece(fromColumn column: Int) -> Side? {
        guard (1...Self.columnCount).contains(column) else { return nil }
        return stacks[column - 1].popLast()
    }

    // MARK: Winning

    /// The four ways a line can run: across, straight up, and the two
    /// diagonals. The opposite directions are the same lines seen from the
    /// other end, so they do not need checking.
    private static let directions = [
        (column: 1, row: 0), (column: 0, row: 1), (column: 1, row: 1), (column: 1, row: -1),
    ]

    /// The winner and the winning line or lines, or nil if nobody has four in
    /// a row. A line longer than four is reported whole.
    var win: Win? {
        var winner: Side?
        var lines: [[Cell]] = []
        for column in 1...Self.columnCount {
            for (index, side) in stacks[column - 1].enumerated() {
                let start = Cell(column: column, row: index + 1)
                for step in Self.directions {
                    // Count each line once, from its first piece.
                    if self[column: start.column - step.column, row: start.row - step.row] == side { continue }
                    var line = [start]
                    var next = Cell(column: start.column + step.column, row: start.row + step.row)
                    while self[column: next.column, row: next.row] == side {
                        line.append(next)
                        next = Cell(column: next.column + step.column, row: next.row + step.row)
                    }
                    if line.count >= 4 {
                        winner = side
                        lines.append(line)
                    }
                }
            }
        }
        guard let winner else { return nil }
        return Win(side: winner, lines: lines)
    }

    /// The columns where `side` would complete four in a row with one piece.
    func winningColumns(for side: Side) -> [Int] {
        openColumns.filter { column in
            var trial = self
            trial.drop(side, inColumn: column)
            return trial.win?.side == side
        }
    }
}
