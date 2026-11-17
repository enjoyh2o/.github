import Foundation

/// A game of Four in a Row you can hold a conversation with.
///
/// The session owns the board and remembers the conversation around it: the
/// moves so far, the last thing it said, and any question it is waiting to
/// have answered. Everything the player does arrives as words through
/// `handle(_:)`, and every result leaves as one short `Reply`.
final class FourInARowSession: GameSession {

    typealias Side = FourInARowBoard.Side
    typealias Cell = FourInARowBoard.Cell
    /// The column the computer chose, 1 to 7.
    typealias ComputerMove = Int

    /// Everything a view needs to draw the board and describe it to VoiceOver.
    struct Snapshot: Equatable, Sendable {
        var board: FourInARowBoard
        /// Whose move it is. Once the game is over nobody is to move.
        var turn: Side
        /// The side the player has against the computer. Nil when two people
        /// share the device, because then nobody is "you".
        var you: Side?
        var lastMove: Cell?
        var winner: Side?
        var winningCells: [Cell]
        var isDraw: Bool
        var moveCount: Int

        var isOver: Bool { winner != nil || isDraw }

        /// A VoiceOver label for one space, such as
        /// "Column 4, row 2, your piece, last move".
        func label(for cell: Cell) -> String {
            var parts = ["Column \(cell.column)", "row \(cell.row)"]
            if let side = board[column: cell.column, row: cell.row] {
                if let you {
                    parts.append(side == you ? "your piece" : "the computer's piece")
                } else {
                    parts.append(side.name)
                }
            } else {
                parts.append("empty")
            }
            if winningCells.contains(cell) { parts.append("winning line") }
            if lastMove == cell { parts.append("last move") }
            return parts.joined(separator: ", ")
        }
    }

    let title = "Four in a Row"
    let opponent: Opponent
    let difficulty: Difficulty
    let humanStarts: Bool

    /// After the computer moves, warn the player if it is now one piece away
    /// from winning. A sighted player would see that at a glance.
    var announceThreats = true

    private var board = FourInARowBoard()
    /// Where each piece landed, in the order played. Red moves first, so the
    /// moves at even positions are Red's.
    private var history: [Cell] = []
    /// A yes-or-no question the session has asked and not yet had answered.
    private var pending: Question?
    private var lastReply: Reply?

    private enum Question {
        case newGame
        case playHint(column: Int)
    }

    init(opponent: Opponent = .computer, difficulty: Difficulty = .gentle, humanStarts: Bool = true) {
        self.opponent = opponent
        self.difficulty = difficulty
        self.humanStarts = humanStarts
    }

    // MARK: State

    var snapshot: Snapshot {
        let win = board.win
        return Snapshot(
            board: board,
            turn: turn,
            you: human,
            lastMove: history.last,
            winner: win?.side,
            winningCells: win?.cells ?? [],
            isDraw: win == nil && board.isFull,
            moveCount: history.count
        )
    }

    var isOver: Bool { board.win != nil || board.isFull }

    private var turn: Side { player(ofMove: history.count) }

    private func player(ofMove index: Int) -> Side { index % 2 == 0 ? .red : .yellow }

    /// The side the player has against the computer, or nil with two players.
    private var human: Side? {
        guard opponent == .computer else { return nil }
        return humanStarts ? .red : .yellow
    }

    private var isComputerTurn: Bool {
        guard let human else { return false }
        return !isOver && turn != human
    }

    var suggestions: [String] {
        if pending != nil { return ["Yes", "No", "Repeat"] }
        if isOver { return ["New game", "Read the board", "History"] }
        if isComputerTurn { return ["Read the board", "Can anyone win?", "Whose turn is it?"] }
        if history.isEmpty { return ["Column 4", "Hint", "Help"] }
        var phrases = ["Read the board", "Can anyone win?", "Hint", "Last move"]
        // Against the computer there is nothing to take back until the player has moved.
        if human == nil || history.count >= 2 { phrases.append("Undo") }
        return phrases
    }

    // MARK: Conversation

    func opening() -> Reply {
        history.isEmpty ? say(introduction) : say("Four in a Row. " + summaryText)
    }

    func handle(_ input: String) -> Reply {
        let words = Phrase.words(input)
        guard !words.isEmpty else {
            return say("I did not hear anything. \(prompt)", .error)
        }
        let request = FourInARowRequest.parse(words)

        // Asking to hear something again must not cancel a question that is
        // still waiting for its answer.
        if request == .common(.repeatLast) { return repeatLast() }

        if let question = pending {
            pending = nil
            if request == .common(.yes) { return confirm(question) }
            if request == .common(.no) { return decline(question) }
            // Anything else drops the question and is handled as usual.
        }

        switch request {
        case .drop(let column): return drop(inColumn: column)
        case .common(let common): return respond(to: common)
        case .readColumn(let column): return readColumn(column)
        case .readRow(let row): return readRow(row)
        case .readCell(let column, let row): return readCell(column: column, row: row)
        case .heights: return say(heightsText)
        case .openColumns: return say(openColumnsText)
        case .threats: return say(isOver ? gameOverText : threatsText)
        case .pieces(let owner): return say(piecesText(for: owner))
        case .gameStatus: return say(isOver ? gameOverText : "The game is still going. \(whoseTurnText)")
        case .whoAmI: return say(whoAmIText)
        case .unknown: return say("Sorry, I did not understand that. \(prompt)", .error)
        }
    }

    private func respond(to request: CommonIntent) -> Reply {
        switch request {
        case .yes: return say("There is nothing to say yes to right now. \(prompt)", .error)
        case .no: return say("Okay.")
        case .help: return say(helpText)
        case .repeatLast: return repeatLast()
        case .hint: return hint()
        case .undo: return undo()
        case .newGame: return newGame()
        case .lastMove: return say(lastMoveText)
        case .history: return say(historyText)
        case .turn: return say(isOver ? gameOverText : turnText)
        case .readBoard: return say(boardText)
        case .summary: return say(summaryText)
        }
    }

    /// Records a reply so that "repeat" can say it again.
    private func say(_ text: String, _ tone: Reply.Tone = .info, boardChanged: Bool = false) -> Reply {
        let reply = Reply(text, tone: tone, boardChanged: boardChanged)
        lastReply = reply
        return reply
    }

    private func repeatLast() -> Reply {
        guard let last = lastReply else { return say(introduction) }
        // Same words and tone, but the board does not change a second time.
        return Reply(last.text, tone: last.tone)
    }

    private func confirm(_ question: Question) -> Reply {
        switch question {
        case .newGame: return startNewGame()
        case .playHint(let column): return drop(inColumn: column)
        }
    }

    private func decline(_ question: Question) -> Reply {
        switch question {
        case .newGame: return say("Okay, the game carries on. \(whoseTurnText)")
        case .playHint: return say("Okay. \(whoseTurnText)")
        }
    }

    // MARK: Moves

    private func drop(inColumn column: Int) -> Reply {
        if isOver {
            return say(gameOverText, .error)
        }
        if isComputerTurn {
            return say("It is the computer's turn. Say your column once it has moved.", .error)
        }
        guard (1...FourInARowBoard.columnCount).contains(column) else {
            return say("There is no column \(column). Columns are numbered 1 to 7 from the left.", .error)
        }
        guard !board.isFull(column: column) else {
            return say("Column \(column) is full. \(openColumnsList)", .error)
        }
        return play(column, for: turn)
    }

    /// Puts a piece on the board and describes what happened.
    private func play(_ column: Int, for side: Side) -> Reply {
        guard let cell = board.drop(side, inColumn: column) else {
            return say("Column \(column) cannot take a piece. \(openColumnsList)", .error)
        }
        history.append(cell)
        var text = "\(subject(side)) dropped in column \(column). It landed on row \(cell.row)."

        if let win = board.win {
            text += " Four in a row \(describe(win.lines[0])). \(victoryCry(for: side)) Say new game to play again."
            return say(text, .gameOver, boardChanged: true)
        }
        if board.isFull {
            text += " The board is full, so the game is a draw. Say new game to play again."
            return say(text, .gameOver, boardChanged: true)
        }
        guard let human else {
            // Two players: say who is next, since they share one device.
            return say(text + " \(turn.name)'s turn.", .move, boardChanged: true)
        }
        if side != human, announceThreats {
            let threats = board.winningColumns(for: side)
            if !threats.isEmpty {
                text += " Careful: the computer can win in \(columns(threats, "or"))."
                return say(text, .alert, boardChanged: true)
            }
        }
        return say(text, .move, boardChanged: true)
    }

    func computerMoveJob() -> (@Sendable () -> Int?)? {
        guard isComputerTurn else { return nil }
        // Copies, so the job touches nothing that belongs to the session.
        let board = self.board
        let side = turn
        let difficulty = self.difficulty
        return {
            var rng = SystemRandomNumberGenerator()
            return FourInARowAI.chooseColumn(on: board, for: side, difficulty: difficulty, using: &rng)
        }
    }

    func play(computerMove column: Int) -> Reply {
        // A job can come back late, after an undo or a new game. Its move is
        // then out of date and must not be played.
        guard isComputerTurn, !board.isFull(column: column),
              (1...FourInARowBoard.columnCount).contains(column) else {
            return say("The computer has no move to make right now. \(isOver ? gameOverText : whoseTurnText)", .error)
        }
        return play(column, for: turn)
    }

    // MARK: Undo, new game, hint

    private func undo() -> Reply {
        if isComputerTurn {
            return say("The computer is about to move. Say undo after that to take both moves back.", .error)
        }
        guard !history.isEmpty else {
            return say("There is nothing to undo yet. \(prompt)", .error)
        }
        guard let human else {
            // Two players: one move at a time.
            let side = player(ofMove: history.count - 1)
            let cell = takeBackLastMove()
            return say("Took back \(side.name)'s piece from column \(cell.column). It is \(side.name)'s turn again.",
                       boardChanged: true)
        }

        // Against the computer: take back its reply together with the
        // player's move, so that it is the player's turn again.
        var undone: [String] = []
        if player(ofMove: history.count - 1) != human {
            guard history.count >= 2 else {
                return say("There is nothing to undo: you have not moved yet. \(prompt)", .error)
            }
            undone.append("the computer's piece from column \(takeBackLastMove().column)")
        }
        undone.append("your piece from column \(takeBackLastMove().column)")
        return say("Took back \(Phrase.list(undone)). It is your turn again.", boardChanged: true)
    }

    /// Removes the latest move. Only call when there is one.
    private func takeBackLastMove() -> Cell {
        let cell = history.removeLast()
        board.removeTopPiece(fromColumn: cell.column)
        return cell
    }

    private func newGame() -> Reply {
        // Nothing would be lost, so there is nothing to confirm.
        if history.isEmpty || isOver { return startNewGame() }
        pending = .newGame
        return say("Start a new game? Say yes or no.", .question)
    }

    private func startNewGame() -> Reply {
        board = FourInARowBoard()
        history = []
        let text: String
        switch human {
        case .red?: text = "New game. You are Red and go first."
        case .yellow?: text = "New game. The computer is Red and goes first."
        case nil: text = "New game. Red goes first."
        }
        return say(text, boardChanged: true)
    }

    private func hint() -> Reply {
        if isOver {
            return say(gameOverText, .error)
        }
        if isComputerTurn {
            return say("It is the computer's turn. Ask for a hint once it has moved.", .error)
        }
        let side = turn
        guard let column = FourInARowAI.bestColumn(on: board, for: side) else {
            return say("There are no moves left. \(prompt)", .error)
        }
        let text: String
        if board.winningColumns(for: side).contains(column) {
            text = "Column \(column) wins the game."
        } else if board.winningColumns(for: side.other).contains(column) {
            text = "Column \(column) stops \(name(side.other)) making four in a row."
        } else {
            text = "Try column \(column)."
        }
        pending = .playHint(column: column)
        return say(text + " Say yes to play it.")
    }

    // MARK: Naming the sides

    /// "you" and "the computer" against the computer; "Red" and "Yellow"
    /// when two people share the device.
    private func name(_ side: Side) -> String {
        guard let human else { return side.name }
        return side == human ? "you" : "the computer"
    }

    /// The same name, ready to start a sentence.
    private func subject(_ side: Side) -> String {
        Phrase.capitalized(name(side))
    }

    private func possessive(_ side: Side) -> String {
        guard let human else { return side.name + "'s" }
        return side == human ? "your" : "the computer's"
    }

    /// A one-word name for reading out what is on a space.
    private func tag(_ side: Side) -> String {
        guard let human else { return side.name }
        return side == human ? "you" : "computer"
    }

    /// Picks the verb form that agrees with the side: "you have", "Red has".
    private func verb(_ side: Side, _ withYou: String, _ otherwise: String) -> String {
        human == side ? withYou : otherwise
    }

    /// Who "my" means: the player against the computer, otherwise whoever is
    /// about to move.
    private var speaker: Side { human ?? turn }

    // MARK: Describing the game

    private var prompt: String { "Say a column from 1 to 7, or say help." }

    private var introduction: String {
        switch human {
        case .red?:
            return "Four in a Row against the computer, set to \(difficulty.title). "
                + "You are Red and go first. Say a column from 1 to 7, or say help."
        case .yellow?:
            return "Four in a Row against the computer, set to \(difficulty.title). "
                + "The computer is Red and goes first. You are Yellow."
        case nil:
            return "Four in a Row for two players. Red goes first. Say a column from 1 to 7, or say help."
        }
    }

    private var helpText: String {
        "Say a column from 1 to 7 to drop a piece. "
            + "Ask me to read the board, a column or a row, where your pieces are, "
            + "how full the columns are, or whether anyone can win. "
            + "You can also say hint, undo, repeat or new game."
    }

    /// "It is your turn.", "It is the computer's turn.", "It is Red's turn."
    private var whoseTurnText: String {
        "It is \(possessive(turn)) turn."
    }

    /// The answer to "whose turn is it?", with a reminder of which side the
    /// player has, since they cannot glance at the board to check.
    private var turnText: String {
        guard let human else { return whoseTurnText }
        return "\(whoseTurnText) You are \(human.name)."
    }

    private var whoAmIText: String {
        guard let human else { return "Red moves first and Yellow second. \(isOver ? gameOverText : whoseTurnText)" }
        return "You are \(human.name). The computer is \(human.other.name)."
    }

    private var gameOverText: String {
        "The game is over. \(resultText) Say new game to play again."
    }

    private var resultText: String {
        guard let win = board.win else { return "It was a draw: the board is full." }
        return "\(subject(win.side)) won with four in a row \(describe(win.lines[0]))."
    }

    private func victoryCry(for side: Side) -> String {
        guard let human else { return "\(side.name) wins!" }
        return side == human ? "You win!" : "The computer wins."
    }

    /// Where a winning line runs, in the player's own terms.
    private func describe(_ line: [Cell]) -> String {
        guard let first = line.first, let last = line.last else { return "" }
        if first.row == last.row {
            return "across row \(first.row), columns \(first.column) to \(last.column)"
        }
        if first.column == last.column {
            return "up column \(first.column), rows \(first.row) to \(last.row)"
        }
        return "on a diagonal from column \(first.column), row \(first.row) "
            + "to column \(last.column), row \(last.row)"
    }

    /// "column 3", "columns 3 and 5", or with "or": "column 3 or 5".
    private func columns(_ list: [Int], _ conjunction: String = "and") -> String {
        let numbers = Phrase.list(list.map { String($0) }, conjunction: conjunction)
        return (list.count == 1 || conjunction == "or" ? "column " : "columns ") + numbers
    }

    private var boardText: String {
        guard board.pieceCount > 0 else { return "The board is empty." }
        let last = FourInARowBoard.columnCount
        var parts: [String] = []
        var column = 1
        while column <= last {
            let pieces = board.pieces(inColumn: column)
            if pieces.isEmpty {
                // Say a run of empty columns once rather than column by column.
                var end = column
                while end < last, board.height(ofColumn: end + 1) == 0 { end += 1 }
                switch end - column {
                case 0: parts.append("Column \(column): empty.")
                case 1: parts.append("Columns \(column) and \(end): empty.")
                default: parts.append("Columns \(column) to \(end): empty.")
                }
                column = end + 1
            } else {
                parts.append("Column \(column): \(pieces.map(tag).joined(separator: ", ")).")
                column += 1
            }
        }
        return "From the bottom up. " + parts.joined(separator: " ")
    }

    private func readColumn(_ column: Int) -> Reply {
        guard (1...FourInARowBoard.columnCount).contains(column) else {
            return say("There is no column \(column). Columns are numbered 1 to 7 from the left.", .error)
        }
        let pieces = board.pieces(inColumn: column)
        guard !pieces.isEmpty else { return say("Column \(column) is empty.") }
        let lead = board.isFull(column: column)
            ? "Column \(column) is full."
            : "Column \(column) has \(Phrase.count(pieces.count, "piece"))."
        return say("\(lead) From the bottom: \(pieces.map(tag).joined(separator: ", ")).")
    }

    private func readRow(_ row: Int) -> Reply {
        guard (1...FourInARowBoard.rowCount).contains(row) else {
            return say("There is no row \(row). Rows are numbered 1 to 6 from the bottom.", .error)
        }
        let first = human ?? .red
        var parts: [String] = []
        var filled = 0
        for side in [first, first.other] {
            let found = (1...FourInARowBoard.columnCount).filter { board[column: $0, row: row] == side }
            if found.isEmpty { continue }
            filled += found.count
            parts.append("\(name(side)) in \(columns(found))")
        }
        guard !parts.isEmpty else { return say("Row \(row) is empty.") }
        var text = "Row \(row): \(parts.joined(separator: "; "))."
        switch FourInARowBoard.columnCount - filled {
        case 0: break
        case 1: text += " The other column is empty."
        default: text += " The other columns are empty."
        }
        return say(text)
    }

    private func readCell(column: Int, row: Int) -> Reply {
        guard (1...FourInARowBoard.columnCount).contains(column), (1...FourInARowBoard.rowCount).contains(row) else {
            return say("There is no column \(column), row \(row). "
                       + "Columns go from 1 to 7 and rows from 1 at the bottom to 6.", .error)
        }
        let place = "Column \(column), row \(row)"
        if let side = board[column: column, row: row] {
            guard let human else { return say("\(place) is \(side.name).") }
            return say("\(place) is \(side == human ? "yours" : "the computer's").")
        }
        let landing = board.height(ofColumn: column) + 1
        if row == landing {
            return say("\(place) is empty. It is where the next piece in column \(column) will land.")
        }
        return say("\(place) is empty. The next piece in column \(column) will land on row \(landing).")
    }

    private var heightsText: String {
        let all = 1...FourInARowBoard.columnCount
        let used = all.filter { board.height(ofColumn: $0) > 0 }
        guard !used.isEmpty else { return "Every column is empty." }
        let parts = used.map { column in
            board.isFull(column: column)
                ? "column \(column) is full"
                : "column \(column) has \(board.height(ofColumn: column))"
        }
        var text = Phrase.capitalized(Phrase.list(parts)) + "."
        switch all.count - used.count {
        case 0: break
        case 1: text += " The other column is empty."
        default: text += " The other columns are empty."
        }
        return text
    }

    /// The columns that can still be played, as an instruction.
    private var openColumnsList: String {
        let open = board.openColumns
        switch open.count {
        case 0: return "No column has room."
        case 1: return "The only open column is \(open[0])."
        default: return "Open columns: \(Phrase.list(open.map { String($0) }))."
        }
    }

    private var openColumnsText: String {
        let full = board.fullColumns
        if full.isEmpty { return "No column is full. All 7 are open." }
        return "\(Phrase.capitalized(columns(full))) \(full.count == 1 ? "is" : "are") full. \(openColumnsList)"
    }

    private func piecesText(for owner: FourInARowRequest.Owner) -> String {
        switch owner {
        case .mine: return piecesText(for: speaker)
        case .theirs: return piecesText(for: speaker.other)
        case .side(let side): return piecesText(for: side)
        case .everyone: return piecesText(for: speaker) + " " + piecesText(for: speaker.other)
        }
    }

    private func piecesText(for side: Side) -> String {
        let cells = board.cells(of: side)
        let have = verb(side, "have", "has")
        guard !cells.isEmpty else { return "\(subject(side)) \(have) no pieces on the board yet." }
        // Group by column: "column 3, rows 1 and 2".
        var parts: [String] = []
        for column in 1...FourInARowBoard.columnCount {
            let rows = cells.filter { $0.column == column }.map { String($0.row) }
            if rows.isEmpty { continue }
            parts.append("column \(column), \(rows.count == 1 ? "row" : "rows") \(Phrase.list(rows))")
        }
        return "\(subject(side)) \(have) \(Phrase.count(cells.count, "piece")): \(parts.joined(separator: "; "))."
    }

    /// Who could finish four in a row with their very next piece.
    private var threatsText: String {
        let mover = turn
        let waiting = turn.other
        let mine = board.winningColumns(for: mover)
        let theirs = board.winningColumns(for: waiting)

        if mine.isEmpty && theirs.isEmpty { return "Nobody can win on the next move." }
        if theirs.isEmpty { return "\(subject(mover)) can win in \(columns(mine, "or"))." }
        if mine.isEmpty {
            if theirs.count > 1 {
                return "\(subject(waiting)) can win in \(columns(theirs, "or")), and only one can be blocked."
            }
            let advice = mover == human ? "so block it" : "so \(name(mover)) must block it"
            return "\(subject(waiting)) can win in \(columns(theirs)), \(advice)."
        }
        // Both sides have a winning move, but whoever moves first gets there first.
        return "\(subject(mover)) can win in \(columns(mine, "or")). "
            + "\(subject(waiting)) can also win in \(columns(theirs, "or")), "
            + "but \(name(mover)) \(verb(mover, "move", "moves")) first."
    }

    private var lastMoveText: String {
        guard let last = history.last else { return "No moves have been played yet." }
        let side = player(ofMove: history.count - 1)
        var text = "\(subject(side)) dropped in column \(last.column), landing on row \(last.row)."
        if history.count >= 2 {
            let earlier = history[history.count - 2]
            text += " Before that, \(name(side.other)) dropped in column \(earlier.column), "
                + "landing on row \(earlier.row)."
        }
        return text
    }

    private var historyText: String {
        guard !history.isEmpty else { return "No moves have been played yet." }
        let moves = history.enumerated().map { index, cell in "\(tag(player(ofMove: index))) \(cell.column)" }
        return "\(Phrase.count(history.count, "move")) so far, by column: \(moves.joined(separator: ", "))."
    }

    private var summaryText: String {
        if isOver { return gameOverText }
        var text = "It is \(possessive(turn)) turn, move \(history.count + 1)."
        guard !history.isEmpty else { return text + " The board is empty." }
        let heights = (1...FourInARowBoard.columnCount).map { String(board.height(ofColumn: $0)) }
        text += " Heights for columns 1 to 7: \(heights.joined(separator: ", ")). "
        return text + threatsText
    }
}
