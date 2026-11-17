import Foundation

/// The three-by-three grid for Tic-Tac-Toe.
///
/// Squares are numbered 1 to 9 in reading order (left to right, top to
/// bottom) and each also has a name such as "top left" or "centre". Players
/// may say either; replies always use the name, which needs no counting.
struct TicTacToeBoard: Equatable, Sendable {

    /// The two players. X always moves first.
    enum Mark: String, CaseIterable, Sendable {
        case x, o

        var other: Mark { self == .x ? .o : .x }
        var name: String { self == .x ? "X" : "O" }
    }

    /// A finished game: who made three in a row, and where.
    struct Win: Equatable, Sendable {
        var mark: Mark
        /// Each winning line as three square numbers. Nearly always one
        /// line, but the last mark can complete two at once.
        var lines: [[Int]]

        /// Every square on a winning line, for highlighting.
        var squares: [Int] {
            Array(Set(lines.joined())).sorted()
        }
    }

    static let squareNumbers = 1...9

    /// The eight ways to make three in a row.
    static let lines: [[Int]] = [
        [1, 2, 3], [4, 5, 6], [7, 8, 9],    // rows
        [1, 4, 7], [2, 5, 8], [3, 6, 9],    // columns
        [1, 5, 9], [3, 5, 7],               // diagonals
    ]

    private static let names = [
        "top left", "top middle", "top right",
        "middle left", "centre", "middle right",
        "bottom left", "bottom middle", "bottom right",
    ]

    /// What is on each square, in reading order: `marks[0]` is square 1.
    private(set) var marks: [Mark?] = Array(repeating: nil, count: 9)

    // MARK: Naming squares

    /// "top left", "centre", "bottom middle" and so on.
    static func name(of square: Int) -> String {
        squareNumbers.contains(square) ? names[square - 1] : "square \(square)"
    }

    /// Rows are numbered 1 to 3 from the top.
    static func row(of square: Int) -> Int { (square - 1) / 3 + 1 }

    /// Columns are numbered 1 to 3 from the left.
    static func column(of square: Int) -> Int { (square - 1) % 3 + 1 }

    static func square(row: Int, column: Int) -> Int? {
        guard (1...3).contains(row), (1...3).contains(column) else { return nil }
        return (row - 1) * 3 + column
    }

    /// "top", "middle" or "bottom".
    static func name(ofRow row: Int) -> String {
        ["top", "middle", "bottom"][min(max(row, 1), 3) - 1]
    }

    /// "left", "middle" or "right".
    static func name(ofColumn column: Int) -> String {
        ["left", "middle", "right"][min(max(column, 1), 3) - 1]
    }

    // MARK: Looking

    /// The mark on a square, or nil if it is free or not on the board.
    subscript(square: Int) -> Mark? {
        Self.squareNumbers.contains(square) ? marks[square - 1] : nil
    }

    var freeSquares: [Int] {
        Self.squareNumbers.filter { marks[$0 - 1] == nil }
    }

    func squares(of mark: Mark) -> [Int] {
        Self.squareNumbers.filter { marks[$0 - 1] == mark }
    }

    var markCount: Int { 9 - freeSquares.count }

    var isFull: Bool { freeSquares.isEmpty }

    // MARK: Changing

    /// Marks a square. Returns false (changing nothing) if the square is
    /// taken or not on the board.
    @discardableResult
    mutating func place(_ mark: Mark, on square: Int) -> Bool {
        guard Self.squareNumbers.contains(square), marks[square - 1] == nil else { return false }
        marks[square - 1] = mark
        return true
    }

    /// Wipes a square clean. Used to take a move back.
    mutating func clear(_ square: Int) {
        guard Self.squareNumbers.contains(square) else { return }
        marks[square - 1] = nil
    }

    // MARK: Winning

    /// True if `mark` has three in a row anywhere.
    func hasLine(of mark: Mark) -> Bool {
        for line in Self.lines
        where marks[line[0] - 1] == mark && marks[line[1] - 1] == mark && marks[line[2] - 1] == mark {
            return true
        }
        return false
    }

    /// The winner and the winning line or lines, or nil if nobody has three in a row.
    var win: Win? {
        for mark in Mark.allCases {
            let lines = Self.lines.filter { line in line.allSatisfy { marks[$0 - 1] == mark } }
            if !lines.isEmpty { return Win(mark: mark, lines: lines) }
        }
        return nil
    }

    /// The free squares where `mark` would complete three in a row.
    func winningSquares(for mark: Mark) -> [Int] {
        freeSquares.filter { square in
            var trial = self
            trial.place(mark, on: square)
            return trial.hasLine(of: mark)
        }
    }
}
