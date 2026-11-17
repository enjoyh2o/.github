import Foundation

/// A game of Tic-Tac-Toe you can hold a conversation with.
///
/// The session owns the board and remembers the conversation around it: the
/// moves so far, the last thing it said, and any question it is waiting to
/// have answered. Everything the player does arrives as words through
/// `handle(_:)`, and every result leaves as one short `Reply`.
final class TicTacToeSession: GameSession {

    typealias Mark = TicTacToeBoard.Mark
    /// The square the computer chose, 1 to 9.
    typealias ComputerMove = Int

    /// Everything a view needs to draw the board and describe it to VoiceOver.
    struct Snapshot: Equatable, Sendable {
        var board: TicTacToeBoard
        /// Whose move it is. Once the game is over nobody is to move.
        var turn: Mark
        /// The mark the player has against the computer. Nil when two people
        /// share the device, because then nobody is "you".
        var you: Mark?
        /// The square taken most recently, 1 to 9.
        var lastMove: Int?
        var winner: Mark?
        var winningSquares: [Int]
        var isDraw: Bool
        var moveCount: Int

        var isOver: Bool { winner != nil || isDraw }

        /// A VoiceOver label for one square, such as "Centre, your X, last move".
        func label(for square: Int) -> String {
            var parts = [Phrase.capitalized(TicTacToeBoard.name(of: square))]
            if let mark = board[square] {
                if let you {
                    parts.append(mark == you ? "your \(mark.name)" : "the computer's \(mark.name)")
                } else {
                    parts.append(mark.name)
                }
            } else {
                parts.append("empty")
            }
            if winningSquares.contains(square) { parts.append("winning line") }
            if lastMove == square { parts.append("last move") }
            return parts.joined(separator: ", ")
        }
    }

    let title = "Tic-Tac-Toe"
    let opponent: Opponent
    let difficulty: Difficulty
    let humanStarts: Bool

    /// After the computer moves, warn the player if it is now one mark away
    /// from winning. A sighted player would see that at a glance.
    var announceThreats = true

    private var board = TicTacToeBoard()
    /// The squares taken, in the order played. X moves first, so the moves
    /// at even positions are X's.
    private var history: [Int] = []
    /// A yes-or-no question the session has asked and not yet had answered.
    private var pending: Question?
    private var lastReply: Reply?

    private enum Question {
        case newGame
        case playHint(square: Int)
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
            winner: win?.mark,
            winningSquares: win?.squares ?? [],
            isDraw: win == nil && board.isFull,
            moveCount: history.count
        )
    }

    var isOver: Bool { board.win != nil || board.isFull }

    private var turn: Mark { player(ofMove: history.count) }

    private func player(ofMove index: Int) -> Mark { index % 2 == 0 ? .x : .o }

    /// The mark the player has against the computer, or nil with two players.
    private var human: Mark? {
        guard opponent == .computer else { return nil }
        return humanStarts ? .x : .o
    }

    private var isComputerTurn: Bool {
        guard let human else { return false }
        return !isOver && turn != human
    }

    var suggestions: [String] {
        if pending != nil { return ["Yes", "No", "Repeat"] }
        if isOver { return ["New game", "Read the board", "History"] }
        if isComputerTurn { return ["Read the board", "Can anyone win?", "Whose turn is it?"] }
        if history.isEmpty { return ["Centre", "Hint", "Help"] }
        var phrases = ["Read the board", "What's free?", "Can anyone win?", "Hint"]
        // Against the computer there is nothing to take back until the player has moved.
        if human == nil || history.count >= 2 { phrases.append("Undo") }
        return phrases
    }

    // MARK: Conversation

    func opening() -> Reply {
        history.isEmpty ? say(introduction) : say("Tic-Tac-Toe. " + summaryText)
    }

    func handle(_ input: String) -> Reply {
        let words = Phrase.words(input)
        guard !words.isEmpty else {
            return say("I did not hear anything. \(prompt)", .error)
        }
        let request = TicTacToeRequest.parse(words)

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
        case .take(let square): return take(square)
        case .common(let common): return respond(to: common)
        case .readSquare(let square): return readSquare(square)
        case .readRow(let row): return readRow(row)
        case .readColumn(let column): return readColumn(column)
        case .freeSquares: return say(freeSquaresText)
        case .threats: return say(isOver ? gameOverText : threatsText)
        case .marks(let owner): return say(marksText(for: owner))
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
        case .playHint(let square): return take(square)
        }
    }

    private func decline(_ question: Question) -> Reply {
        switch question {
        case .newGame: return say("Okay, the game carries on. \(whoseTurnText)")
        case .playHint: return say("Okay. \(whoseTurnText)")
        }
    }

    // MARK: Moves

    private func take(_ square: Int) -> Reply {
        if isOver {
            return say(gameOverText, .error)
        }
        if isComputerTurn {
            return say("It is the computer's turn. Say your square once it has moved.", .error)
        }
        guard TicTacToeBoard.squareNumbers.contains(square) else {
            return say("\(noSuchSquare(square)) Squares are numbered 1 to 9 across from the top left, "
                       + "and rows and columns 1 to 3.", .error)
        }
        if let owner = board[square] {
            let who = owner == human ? "you already have it" : "\(name(owner)) has it"
            return say("\(Phrase.capitalized(the(square))) is taken: \(who). \(freeSquaresText)", .error)
        }
        return play(square, for: turn)
    }

    /// Puts a mark on the board and describes what happened.
    private func play(_ square: Int, for mark: Mark) -> Reply {
        guard board.place(mark, on: square) else {
            return say("\(Phrase.capitalized(the(square))) cannot be taken. \(freeSquaresText)", .error)
        }
        history.append(square)
        var text = "\(subject(mark)) took \(the(square))."

        if let win = board.win {
            text += " Three in a row \(describe(win.lines[0])). \(victoryCry(for: mark)) Say new game to play again."
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
        if mark != human, announceThreats {
            let threats = board.winningSquares(for: mark)
            if !threats.isEmpty {
                text += " Careful: the computer can win \(byTaking(threats))."
                return say(text, .alert, boardChanged: true)
            }
        }
        return say(text, .move, boardChanged: true)
    }

    func computerMoveJob() -> (@Sendable () -> Int?)? {
        guard isComputerTurn else { return nil }
        // Copies, so the job touches nothing that belongs to the session.
        let board = self.board
        let mark = turn
        let difficulty = self.difficulty
        return {
            var rng = SystemRandomNumberGenerator()
            return TicTacToeAI.chooseSquare(on: board, for: mark, difficulty: difficulty, using: &rng)
        }
    }

    func play(computerMove square: Int) -> Reply {
        // A job can come back late, after an undo or a new game. Its move is
        // then out of date and must not be played.
        guard isComputerTurn, TicTacToeBoard.squareNumbers.contains(square), board[square] == nil else {
            return say("The computer has no move to make right now. \(isOver ? gameOverText : whoseTurnText)", .error)
        }
        return play(square, for: turn)
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
            let mark = player(ofMove: history.count - 1)
            let square = takeBackLastMove()
            return say("Took back \(mark.name)'s mark from \(the(square)). It is \(mark.name)'s turn again.",
                       boardChanged: true)
        }

        // Against the computer: take back its reply together with the
        // player's move, so that it is the player's turn again.
        var undone: [String] = []
        if player(ofMove: history.count - 1) != human {
            guard history.count >= 2 else {
                return say("There is nothing to undo: you have not moved yet. \(prompt)", .error)
            }
            undone.append("the computer's mark from \(the(takeBackLastMove()))")
        }
        undone.append("your mark from \(the(takeBackLastMove()))")
        return say("Took back \(Phrase.list(undone)). It is your turn again.", boardChanged: true)
    }

    /// Removes the latest move. Only call when there is one.
    private func takeBackLastMove() -> Int {
        let square = history.removeLast()
        board.clear(square)
        return square
    }

    private func newGame() -> Reply {
        // Nothing would be lost, so there is nothing to confirm.
        if history.isEmpty || isOver { return startNewGame() }
        pending = .newGame
        return say("Start a new game? Say yes or no.", .question)
    }

    private func startNewGame() -> Reply {
        board = TicTacToeBoard()
        history = []
        let text: String
        switch human {
        case .x?: text = "New game. You are X and go first."
        case .o?: text = "New game. The computer is X and goes first."
        case nil: text = "New game. X goes first."
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
        let mark = turn
        guard let square = TicTacToeAI.bestSquare(on: board, for: mark) else {
            return say("There are no moves left. \(prompt)", .error)
        }
        let text: String
        if board.winningSquares(for: mark).contains(square) {
            text = "Take \(the(square)) to win."
        } else if board.winningSquares(for: mark.other).contains(square) {
            text = "Take \(the(square)) to block \(name(mark.other))."
        } else {
            text = "Try \(the(square))."
        }
        pending = .playHint(square: square)
        return say(text + " Say yes to play it.")
    }

    // MARK: Naming the sides and squares

    /// "you" and "the computer" against the computer; "X" and "O" when two
    /// people share the device.
    private func name(_ mark: Mark) -> String {
        guard let human else { return mark.name }
        return mark == human ? "you" : "the computer"
    }

    /// The same name, ready to start a sentence.
    private func subject(_ mark: Mark) -> String {
        Phrase.capitalized(name(mark))
    }

    private func possessive(_ mark: Mark) -> String {
        guard let human else { return mark.name + "'s" }
        return mark == human ? "your" : "the computer's"
    }

    /// A one-word name for listing who moved.
    private func tag(_ mark: Mark) -> String {
        guard let human else { return mark.name }
        return mark == human ? "you" : "computer"
    }

    /// Picks the verb form that agrees with the side: "you have", "X has".
    private func verb(_ mark: Mark, _ withYou: String, _ otherwise: String) -> String {
        human == mark ? withYou : otherwise
    }

    /// Who "my" means: the player against the computer, otherwise whoever is
    /// about to move.
    private var speaker: Mark { human ?? turn }

    /// "the top left", "the centre".
    private func the(_ square: Int) -> String {
        "the " + TicTacToeBoard.name(of: square)
    }

    /// "by taking the top left", "by taking the top left or the centre".
    private func byTaking(_ squares: [Int]) -> String {
        "by taking " + Phrase.list(squares.map(the), conjunction: "or")
    }

    private func noSuchSquare(_ square: Int) -> String {
        square > 0 ? "There is no square \(square)." : "That square is not on the board."
    }

    // MARK: Describing the game

    private var prompt: String { "Say a square such as top left or centre, or say help." }

    private var introduction: String {
        let how = "Say a square such as top left or centre, or a number from 1 to 9."
        switch human {
        case .x?:
            return "Tic-Tac-Toe against the computer, set to \(difficulty.title). You are X and go first. \(how)"
        case .o?:
            return "Tic-Tac-Toe against the computer, set to \(difficulty.title). "
                + "The computer is X and goes first. You are O."
        case nil:
            return "Tic-Tac-Toe for two players. X goes first. \(how)"
        }
    }

    private var helpText: String {
        "Say a square to take it: a name such as top left, centre or bottom middle, "
            + "or a number from 1 to 9 counting across from the top left. "
            + "Ask me to read the board, what is free, where your marks are, or whether anyone can win. "
            + "You can also say hint, undo, repeat or new game."
    }

    /// "It is your turn.", "It is the computer's turn.", "It is X's turn."
    private var whoseTurnText: String {
        "It is \(possessive(turn)) turn."
    }

    /// The answer to "whose turn is it?", with a reminder of which mark the
    /// player has, since they cannot glance at the board to check.
    private var turnText: String {
        guard let human else { return whoseTurnText }
        return "\(whoseTurnText) You are \(human.name)."
    }

    private var whoAmIText: String {
        guard let human else { return "X moves first and O second. \(isOver ? gameOverText : whoseTurnText)" }
        return "You are \(human.name). The computer is \(human.other.name)."
    }

    private var gameOverText: String {
        "The game is over. \(resultText) Say new game to play again."
    }

    private var resultText: String {
        guard let win = board.win else { return "It was a draw: the board is full." }
        return "\(subject(win.mark)) won with three in a row \(describe(win.lines[0]))."
    }

    private func victoryCry(for mark: Mark) -> String {
        guard let human else { return "\(mark.name) wins!" }
        return mark == human ? "You win!" : "The computer wins."
    }

    /// Where a winning line runs, in the player's own terms.
    private func describe(_ line: [Int]) -> String {
        guard let first = line.first, let last = line.last else { return "" }
        if TicTacToeBoard.row(of: first) == TicTacToeBoard.row(of: last) {
            return "across the \(TicTacToeBoard.name(ofRow: TicTacToeBoard.row(of: first))) row"
        }
        if TicTacToeBoard.column(of: first) == TicTacToeBoard.column(of: last) {
            return "down the \(TicTacToeBoard.name(ofColumn: TicTacToeBoard.column(of: first))) column"
        }
        return "on the diagonal from \(the(first)) to \(the(last))"
    }

    /// "X", "O" or "empty" for each of a list of squares.
    private func contents(of squares: [Int]) -> String {
        squares.map { board[$0]?.name ?? "empty" }.joined(separator: ", ")
    }

    private func rowText(_ row: Int) -> String {
        let squares = (1...3).compactMap { TicTacToeBoard.square(row: row, column: $0) }
        return "\(Phrase.capitalized(TicTacToeBoard.name(ofRow: row))) row: \(contents(of: squares))."
    }

    private var boardText: String {
        guard board.markCount > 0 else { return "The board is empty." }
        return (1...3).map(rowText).joined(separator: " ")
    }

    private func readRow(_ row: Int) -> Reply {
        guard (1...3).contains(row) else {
            return say("There is no row \(row). Rows are numbered 1 to 3 from the top.", .error)
        }
        return say(rowText(row))
    }

    private func readColumn(_ column: Int) -> Reply {
        guard (1...3).contains(column) else {
            return say("There is no column \(column). Columns are numbered 1 to 3 from the left.", .error)
        }
        let squares = (1...3).compactMap { TicTacToeBoard.square(row: $0, column: column) }
        let name = Phrase.capitalized(TicTacToeBoard.name(ofColumn: column))
        return say("\(name) column, top to bottom: \(contents(of: squares)).")
    }

    private func readSquare(_ square: Int) -> Reply {
        guard TicTacToeBoard.squareNumbers.contains(square) else {
            return say("\(noSuchSquare(square)) Squares are numbered 1 to 9 across from the top left, "
                       + "and rows and columns 1 to 3.", .error)
        }
        let place = Phrase.capitalized(the(square))
        guard let mark = board[square] else { return say("\(place) is free.") }
        guard let human else { return say("\(place) has an \(mark.name).") }
        return say("\(place) is \(mark == human ? "yours" : "the computer's").")
    }

    private var freeSquaresText: String {
        let free = board.freeSquares
        switch free.count {
        case 0: return "No squares are free."
        case 1: return "Only \(the(free[0])) is free."
        case 9: return "All 9 squares are free."
        default:
            return "\(free.count) squares are free: \(Phrase.list(free.map { TicTacToeBoard.name(of: $0) }))."
        }
    }

    private func marksText(for owner: TicTacToeRequest.Owner) -> String {
        switch owner {
        case .mine: return marksText(for: speaker)
        case .theirs: return marksText(for: speaker.other)
        case .mark(let mark): return marksText(for: mark)
        case .everyone: return marksText(for: speaker) + " " + marksText(for: speaker.other)
        }
    }

    private func marksText(for mark: Mark) -> String {
        let squares = board.squares(of: mark)
        let have = verb(mark, "have", "has")
        guard !squares.isEmpty else { return "\(subject(mark)) \(have) no squares yet." }
        return "\(subject(mark)) \(have) \(Phrase.list(squares.map(the)))."
    }

    /// Who could finish three in a row with their very next mark.
    private var threatsText: String {
        let mover = turn
        let waiting = turn.other
        let mine = board.winningSquares(for: mover)
        let theirs = board.winningSquares(for: waiting)

        if mine.isEmpty && theirs.isEmpty { return "Nobody can win on the next move." }
        if theirs.isEmpty { return "\(subject(mover)) can win \(byTaking(mine))." }
        if mine.isEmpty {
            if theirs.count > 1 {
                return "\(subject(waiting)) can win \(byTaking(theirs)), and only one can be blocked."
            }
            let advice = mover == human ? "so block it" : "so \(name(mover)) must block it"
            return "\(subject(waiting)) can win \(byTaking(theirs)), \(advice)."
        }
        // Both sides have a winning move, but whoever moves first gets there first.
        return "\(subject(mover)) can win \(byTaking(mine)). "
            + "\(subject(waiting)) can also win \(byTaking(theirs)), "
            + "but \(name(mover)) \(verb(mover, "move", "moves")) first."
    }

    private var lastMoveText: String {
        guard let last = history.last else { return "No moves have been played yet." }
        let mark = player(ofMove: history.count - 1)
        var text = "\(subject(mark)) took \(the(last))."
        if history.count >= 2 {
            text += " Before that, \(name(mark.other)) took \(the(history[history.count - 2]))."
        }
        return text
    }

    private var historyText: String {
        guard !history.isEmpty else { return "No moves have been played yet." }
        let moves = history.enumerated().map { index, square in
            "\(tag(player(ofMove: index))) \(TicTacToeBoard.name(of: square))"
        }
        return "\(Phrase.count(history.count, "move")) so far: \(moves.joined(separator: ", "))."
    }

    private var summaryText: String {
        if isOver { return gameOverText }
        let text = "It is \(possessive(turn)) turn, move \(history.count + 1)."
        guard !history.isEmpty else { return text + " The board is empty." }
        return [text, marksText(for: speaker), marksText(for: speaker.other), threatsText].joined(separator: " ")
    }
}
