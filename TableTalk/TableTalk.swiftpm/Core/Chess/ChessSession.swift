import Foundation

/// Everything the chess board view needs to draw one moment of the game.
struct ChessSnapshot: Equatable, Sendable {
    var position: ChessPosition
    var lastMove: Move?
    /// The colour "you" are, or nil when two people share the device.
    var viewer: PieceColor?
    var outcome: ChessOutcome?
    var isComputerTurn: Bool
    /// The game so far in written notation: ["e4", "e5", "Nf3", …].
    var notation: [String]
    /// The king currently in check, if any.
    var checkedKing: Square?
}

/// A conversation about a game of chess.
///
/// Words go in through `handle(_:)`; a sentence comes out. The session keeps
/// just enough dialogue state to ask a follow-up question ("Which knight?")
/// and understand the answer.
final class ChessSession: GameSession {
    let title = "Chess"
    let opponent: Opponent
    /// The colour the person plays against the computer.
    let humanColor: PieceColor
    var difficulty: Difficulty
    /// Say where a piece came from as well as where it went.
    var detailedMoves = true
    /// After the computer moves, mention anything of yours it now attacks.
    var announceThreats = true

    private(set) var game: ChessGame
    private var intro: String?
    private var pending: Pending?
    private var lastReply: Reply?

    /// A question the session asked and is waiting to hear back about.
    private enum Pending {
        case choose([Move])
        case offer(Move)
        case confirmNewGame
        case confirmResign
    }

    init(
        opponent: Opponent = .computer,
        humanColor: PieceColor = .white,
        difficulty: Difficulty = .gentle,
        position: ChessPosition = .start,
        intro: String? = nil
    ) {
        self.opponent = opponent
        self.humanColor = humanColor
        self.difficulty = difficulty
        self.game = ChessGame(position: position)
        self.intro = intro
    }

    /// A ready-made middlegame for trying out questions straight away.
    static func practice(difficulty: Difficulty = .gentle) -> ChessSession {
        let position = ChessPosition(fen: "r1bq1rk1/p4pbp/2n1pnp1/2pp4/1p1P4/N1P1P3/PP1NBPPP/R1BQ1RK1 w - - 0 10")!
        return ChessSession(
            difficulty: difficulty,
            position: position,
            intro: "Practice position. You are White, at move 10, and Black has just pushed a pawn to b4. "
                + "Try asking: where are my knights? Or: what's in danger?"
        )
    }

    // MARK: State

    var perspective: ChessPerspective {
        ChessPerspective(viewer: opponent == .computer ? humanColor : nil)
    }

    private var describer: ChessDescriber {
        ChessDescriber(position: game.position, perspective: perspective)
    }

    /// The side the words "my" and "mine" refer to right now.
    private var mySide: PieceColor {
        opponent == .computer ? humanColor : game.position.sideToMove
    }

    var isOver: Bool { game.outcome != nil }

    var isComputerTurn: Bool {
        opponent == .computer && game.outcome == nil && game.position.sideToMove != humanColor
    }

    var snapshot: ChessSnapshot {
        let position = game.position
        return ChessSnapshot(
            position: position,
            lastMove: game.lastMove?.move,
            viewer: perspective.viewer,
            outcome: game.outcome,
            isComputerTurn: isComputerTurn,
            notation: game.history.map(\.notation),
            checkedKing: position.isCheck ? position.kingSquare(position.sideToMove) : nil
        )
    }

    var suggestions: [String] {
        if isOver { return ["New game", "Read the moves", "Describe the position"] }
        switch pending {
        case .offer, .confirmNewGame, .confirmResign:
            return ["Yes", "No"]
        case .choose(let moves):
            let starts = Set(moves.map(\.from))
            let names = (starts.count > 1 ? moves.map(\.from.name) : moves.map(\.to.name))
            var seen = Set<String>()
            return Array(names.filter { seen.insert($0).inserted }.prefix(6)) + ["Never mind"]
        case nil:
            return ["Describe the position", "What's in danger?", "What can I take?",
                    "Where are my knights?", "Hint", "Undo"]
        }
    }

    // MARK: Conversation

    func opening() -> Reply {
        var parts: [String] = []
        if let intro {
            parts.append(intro)
        } else {
            switch opponent {
            case .computer:
                parts.append("Chess. You are \(humanColor.name), playing the computer on \(difficulty.title.lowercased()).")
            case .person:
                parts.append("Chess for two players sharing this device.")
            }
            parts.append(turnSentence())
            parts.append("Say a move, or ask anything about the board. Say help to hear examples.")
        }
        let reply = Reply(parts.joined(separator: " "))
        lastReply = reply
        return reply
    }

    func handle(_ input: String) -> Reply {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return Reply("I didn't catch that. Say help to hear what you can ask.", tone: .error)
        }
        let intent = ChessLanguage.parse(text)
        if intent == .common(.repeatLast) {
            return lastReply ?? Reply("There is nothing to repeat yet.")
        }
        let reply = respond(to: intent, raw: text)
        lastReply = reply
        return reply
    }

    /// Handles a request whose meaning was worked out elsewhere — by the
    /// on-device language model, when the built-in parser was stumped.
    func handle(interpreted intent: ChessIntent, heard raw: String) -> Reply {
        let reply = respond(to: intent, raw: raw)
        lastReply = reply
        return reply
    }

    /// True when the built-in parser cannot make sense of `input` and no
    /// follow-up question is open — the moment to ask the language model.
    func needsInterpretation(_ input: String) -> Bool {
        pending == nil && ChessLanguage.parse(input) == .unknown
    }

    private func respond(to intent: ChessIntent, raw: String) -> Reply {
        // An open question of ours gets first refusal on the answer.
        if let open = pending {
            pending = nil
            if let reply = resolve(open, with: intent, raw: raw) { return reply }
        }

        switch intent {
        case .common(let common):
            return respond(to: common)
        case .move(let requests):
            return attempt(requests, asking: false)
        case .canMove(let requests):
            return attempt(requests, asking: true)

        case .whereIs(let kind, let side):
            let color = color(for: side)
            guard let kind else {
                return Reply(color.map { describer.allPieces(of: $0) } ?? describer.readBoard())
            }
            if let color { return Reply(describer.whereAre(kind, color: color)) }
            let first = mySide
            return Reply(describer.whereAre(kind, color: first) + " " + describer.whereAre(kind, color: first.opposite))

        case .whatIsOn(let square):
            return Reply(describer.whatIsOn(square))

        case .movesFor(let square, let kind, let side):
            if let square { return Reply(describer.moves(from: square)) }
            guard let kind else { return unknownReply() }
            return Reply(describer.moves(of: kind, color: color(for: side) ?? mySide))

        case .safety(let square, let kind, let side):
            if let square { return Reply(describer.attackReport(on: square)) }
            guard let kind else { return Reply(describer.dangerReport(for: color(for: side) ?? mySide)) }
            let color = color(for: side) ?? mySide
            let squares = game.position.squares(of: kind, color: color)
            if squares.isEmpty { return Reply(describer.whereAre(kind, color: color)) }
            return Reply(squares.map { describer.attackReport(on: $0) }.joined(separator: " "))

        case .danger(let side):
            if side == .both {
                return Reply(describer.dangerReport(for: mySide) + " " + describer.dangerReport(for: mySide.opposite))
            }
            return Reply(describer.dangerReport(for: color(for: side) ?? mySide))

        case .captures(let side):
            return Reply(describer.captureReport(for: color(for: side) ?? mySide))

        case .readRank(let rank):
            return Reply(describer.readRank(rank))
        case .readFile(let file):
            return Reply(describer.readFile(file))

        case .check:
            let position = game.position
            guard position.isCheck, let king = position.kingSquare(position.sideToMove) else {
                return Reply("No one is in check.")
            }
            let checkers = position.attackers(of: king, by: position.sideToMove.opposite)
            return Reply("\(perspective.isAre(position.sideToMove)) in check from \(describer.names(checkers)).")

        case .material:
            return Reply(describer.material())

        case .resign:
            if isOver { return Reply("The game is already over. Say new game to play again.", tone: .error) }
            pending = .confirmResign
            return Reply("Resign this game? Say yes or no.", tone: .question)

        case .unknown:
            return unknownReply()
        }
    }

    private func respond(to common: CommonIntent) -> Reply {
        switch common {
        case .yes, .no:
            return Reply("Nothing is waiting for a yes or no. Say a move, or ask about the board.")
        case .help:
            return Reply(Self.helpText)
        case .repeatLast:
            return lastReply ?? Reply("There is nothing to repeat yet.")
        case .hint:
            return hint()
        case .undo:
            return undo()
        case .newGame:
            if game.history.isEmpty || isOver { return startNewGame() }
            pending = .confirmNewGame
            return Reply("Start a new game? Say yes or no.", tone: .question)
        case .lastMove:
            return Reply(lastMoveSentence())
        case .history:
            return Reply(history())
        case .turn:
            return Reply(turnSentence())
        case .readBoard:
            return Reply(describer.readBoard())
        case .summary:
            return Reply(summary())
        }
    }

    private func unknownReply() -> Reply {
        Reply("Sorry, I didn't understand that. Try a move like knight to f3, or say help.", tone: .error)
    }

    static let helpText = """
        Say a move, like: knight to f3, e4, pawn takes d5, or castle kingside. \
        Ask about the board, like: where are my knights? What's on e4? What can my queen do? \
        Is my rook safe? What's in danger? What can I take? Read rank 4. Describe the position. \
        You can also say: hint, undo, last move, repeat, or new game.
        """

    // MARK: Follow-up questions

    /// Tries to read `intent` as the answer to a question we asked. Returns
    /// nil if it is not one, so the words are handled as a fresh request.
    private func resolve(_ open: Pending, with intent: ChessIntent, raw: String) -> Reply? {
        switch open {
        case .confirmNewGame:
            if intent == .common(.yes) { return startNewGame() }
            if intent == .common(.no) { return Reply("Okay, the game continues.") }
            return nil

        case .confirmResign:
            if intent == .common(.yes) {
                game.resign(mySide)
                let text = game.outcome.map { ChessNarration.describe($0, perspective: perspective) } ?? "Resigned."
                return Reply(text, tone: .gameOver, boardChanged: true)
            }
            if intent == .common(.no) { return Reply("Okay, the game continues.") }
            return nil

        case .offer(let move):
            if intent == .common(.yes) { return play(move) }
            if intent == .common(.no) { return Reply("Okay, no move made.") }
            return nil

        case .choose(let moves):
            if intent == .common(.no) { return Reply("Okay, no move made.") }
            let position = game.position
            var narrowed = moves
            var gaveClue = false
            let words = Phrase.words(raw)

            for token in ChessLanguage.tokens(raw) {
                switch token {
                case .square(let square):
                    let hits = narrowed.filter { $0.from == square || $0.to == square }
                    if !hits.isEmpty { narrowed = hits; gaveClue = true }
                case .piece(let kind):
                    let hits = narrowed.filter { position[$0.from]?.kind == kind || $0.promotion == kind }
                    if !hits.isEmpty { narrowed = hits; gaveClue = true }
                case .word(let w):
                    if w.count == 1, let file = ChessLanguage.unmistakableFileWords[w], w != "a" || words.count == 1 {
                        let hits = narrowed.filter { $0.from.file == file }
                        if !hits.isEmpty { narrowed = hits; gaveClue = true }
                    } else if let n = Phrase.ordinalWords[w], (1...moves.count).contains(n), words.count <= 3 {
                        narrowed = [moves[n - 1]]; gaveClue = true
                    }
                }
            }
            guard gaveClue else { return nil }
            if narrowed.count == 1 { return play(narrowed[0]) }
            pending = .choose(narrowed)
            return Reply(question(for: narrowed), tone: .question)
        }
    }

    /// "Which knight? The one on b1 or the one on g1?"
    private func question(for moves: [Move]) -> String {
        let position = game.position
        let starts = Array(Set(moves.map(\.from))).sorted()
        let ends = Set(moves.map(\.to))

        if starts.count == 1 {
            return "Where to? " + describer.moves(from: starts[0])
        }
        if ends.count == 1 {
            let kinds = Set(starts.compactMap { position[$0]?.kind })
            if kinds.count == 1, let kind = kinds.first {
                let options = starts.map { "the one on \($0.name)" }
                return "Which \(kind.name)? \(Phrase.capitalized(Phrase.list(options, conjunction: "or")))?"
            }
            return "Which piece? \(Phrase.capitalized(Phrase.list(starts.map { describer.name($0) }, conjunction: "or")))?"
        }
        if moves.count <= 4 {
            return "Which move? \(Phrase.capitalized(Phrase.list(moves.map { preview($0) }, conjunction: "or")))?"
        }
        return "That fits \(moves.count) different moves. Say the piece and where it goes, like knight to f3."
    }

    // MARK: Moves

    private func attempt(_ requests: [MoveRequest], asking: Bool) -> Reply {
        if let outcome = game.outcome {
            let ending = ChessNarration.describe(outcome, perspective: perspective)
            return Reply("The game is over. \(ending) Say new game to play again.", tone: .error)
        }
        if isComputerTurn {
            return Reply("\(game.position.sideToMove.name) is still thinking. One moment.", tone: .error)
        }
        let position = game.position
        let legal = position.legalMoves()
        var matches: [Move] = []
        for request in requests {
            for move in request.matches(in: position, among: legal) where !matches.contains(move) {
                matches.append(move)
            }
        }

        if matches.isEmpty {
            let reason = requests.first.map { explain($0) } ?? "That move is not possible."
            return asking ? Reply("No. " + reason) : Reply(reason, tone: .error)
        }
        if matches.count == 1 {
            guard asking else { return play(matches[0]) }
            pending = .offer(matches[0])
            return Reply("Yes: \(preview(matches[0])). Say yes to play it.", tone: .question)
        }
        pending = .choose(matches)
        return Reply((asking ? "Yes. " : "") + question(for: matches), tone: .question)
    }

    /// Describes a move without playing it.
    private func preview(_ move: Move) -> String {
        var copy = game
        let played = copy.play(move)
        var text = ChessNarration.describe(played, detailed: true)
        if played.isCheckmate { text += ", which is checkmate" } else if played.givesCheck { text += ", with check" }
        return text
    }

    private func play(_ move: Move) -> Reply {
        let mover = game.position.sideToMove
        let played = game.play(move)
        return announce(played, by: mover, dangersBefore: nil)
    }

    private func announce(_ played: PlayedMove, by mover: PieceColor, dangersBefore: Set<Square>?) -> Reply {
        let who = opponent == .computer && mover == humanColor ? "You" : mover.name
        var text = "\(who) played \(ChessNarration.describe(played, detailed: detailedMoves))."
        var tone: Reply.Tone = played.captured != nil ? .capture : .move

        if let outcome = game.outcome {
            text += " " + ChessNarration.describe(outcome, perspective: perspective)
            return Reply(text, tone: .gameOver, boardChanged: true)
        }
        if played.givesCheck {
            text += " Check."
            tone = .alert
        }
        if opponent == .person {
            text += " \(game.position.sideToMove.name) to move."
        }

        // After the computer moves, say what changed for the listener so
        // they do not have to work it out from memory.
        if let dangersBefore {
            let position = game.position
            let canRecapture = played.captured != nil
                && position.legalMoves().contains { position.captureSquare(of: $0) == played.move.to }
            if canRecapture {
                // One alert per move: taking back is the thing to consider first.
                text += " You can take back on \(played.move.to.name)."
            } else if announceThreats {
                let fresh = describer.dangers(to: humanColor).filter { !dangersBefore.contains($0.square) }
                if let first = fresh.first {
                    text += " Careful: \(describer.describe(first))."
                    if fresh.count > 1 {
                        text += " \(Phrase.count(fresh.count - 1, "more piece")) of yours \(fresh.count == 2 ? "is" : "are") in danger too."
                    }
                    tone = .alert
                }
            }
        }
        return Reply(text, tone: tone, boardChanged: true)
    }

    /// Says why a requested move is not possible and what is, so an error is
    /// always a way forward rather than a dead end.
    private func explain(_ request: MoveRequest) -> String {
        let position = game.position
        let us = position.sideToMove
        let you = us == perspective.viewer ? "You" : us.name
        let your = perspective.owner(us)

        if request.castle != nil {
            if position.isCheck { return "\(you) can't castle while in check." }
            let king = us == .white ? "e1" : "e8"
            if position.kingSquare(us)?.name != king || !position.castling.contains(.right(us, .kingside))
                && !position.castling.contains(.right(us, .queenside)) {
                return "\(you) can't castle any more: the king or rooks have already moved."
            }
            return "\(you) can't castle that way right now: there are pieces in between, the king would cross an attacked square, or that rook has moved."
        }

        // Would it work if check and pins did not matter?
        let blockedByCheck = !request.matches(in: position, among: position.pseudoLegalMoves()).isEmpty
        let becauseCheck = position.isCheck
            ? "That does not get \(us == perspective.viewer ? "you" : us.name) out of check."
            : "That piece is pinned: moving it would expose \(your) king."

        if let from = request.from {
            guard let piece = position[from] else { return "There is no piece on \(from.name)." }
            if piece.color != us {
                return "The piece on \(from.name) is \(describer.name(from)), not \(us == perspective.viewer ? "yours" : "\(us.name)'s")."
            }
            if blockedByCheck { return becauseCheck }
            let target = request.to.map { " go to \($0.name)" } ?? " do that"
            return "\(Phrase.capitalized(describer.name(from))) can't\(target). " + describer.moves(from: from)
        }

        if let kind = request.piece {
            let squares = position.squares(of: kind, color: us)
            if squares.isEmpty { return describer.whereAre(kind, color: us) }
            if blockedByCheck { return becauseCheck }
            let goal: String
            if let to = request.to {
                goal = request.capture ? "capture on \(to.name)" : "reach \(to.name)"
            } else if let target = request.target {
                goal = "capture a \(target.name)"
            } else if request.capture {
                goal = "capture anything"
            } else {
                goal = "move"
            }
            let subject = squares.count == 1
                ? Phrase.capitalized(describer.name(squares[0]))
                : "None of \(your) \(kind.plural)"
            var text = "\(subject) can\(squares.count == 1 ? "'t" : "") \(goal)."
            if squares.count <= 2 { text += " " + describer.moves(of: kind, color: us) }
            else { text += " " + describer.whereAre(kind, color: us) }
            return text
        }

        if blockedByCheck { return becauseCheck }
        if let to = request.to {
            return "Nothing of \(us == perspective.viewer ? "yours" : "\(us.name)'s") can \(request.capture ? "capture on" : "move to") \(to.name)."
        }
        if let target = request.target {
            return "\(you) can't capture a \(target.name) right now. " + describer.captureReport(for: us)
        }
        return describer.captureReport(for: us)
    }

    // MARK: Other requests

    private func hint() -> Reply {
        if isOver { return Reply("The game is over. Say new game to play again.", tone: .error) }
        if isComputerTurn { return Reply("It isn't your move yet.", tone: .error) }
        guard let move = ChessAI.chooseMove(in: game.position, settings: .hint) else {
            return Reply("There are no legal moves.", tone: .error)
        }
        pending = .offer(move)
        return Reply("Try \(preview(move)). Say yes to play it.", tone: .question)
    }

    private func undo() -> Reply {
        var undone: [PlayedMove] = []
        if let last = game.undo() { undone.append(last) }
        // Against the computer, take back your own move too so it is your turn.
        if opponent == .computer, game.position.sideToMove != humanColor, let earlier = game.undo() {
            undone.append(earlier)
        }
        guard !undone.isEmpty else { return Reply("There is nothing to take back.", tone: .error) }
        let described = undone.map {
            "\(perspective.owner($0.color)) \(ChessNarration.describe($0, detailed: false))"
        }
        return Reply("Took back \(Phrase.list(described)). \(turnSentence())", tone: .move, boardChanged: true)
    }

    private func startNewGame() -> Reply {
        game = ChessGame()
        pending = nil
        intro = nil
        return Reply("New game. \(turnSentence())", tone: .move, boardChanged: true)
    }

    private func turnSentence() -> String {
        if let outcome = game.outcome {
            return ChessNarration.describe(outcome, perspective: perspective)
        }
        let side = game.position.sideToMove
        switch opponent {
        case .computer:
            return side == humanColor ? "It's your move." : "\(side.name), the computer, is thinking."
        case .person:
            return "\(side.name) to move."
        }
    }

    private func lastMoveSentence() -> String {
        guard let last = game.lastMove else { return "No moves have been played yet." }
        let owner = Phrase.capitalized(perspective.owner(last.color))
        var text = "\(owner) last move was \(ChessNarration.describe(last, detailed: true))."
        if last.isCheckmate { text += " Checkmate." } else if last.givesCheck { text += " Check." }
        return text
    }

    private func history() -> String {
        guard !game.history.isEmpty else { return "No moves have been played yet." }
        let recent = game.history.suffix(10)
        var lines: [String] = []
        var current = -1
        for played in recent {
            let text = "\(played.color.name) \(ChessNarration.describe(played, detailed: false))"
            if played.moveNumber == current, !lines.isEmpty {
                lines[lines.count - 1] += ", \(text)"
            } else {
                lines.append("Move \(played.moveNumber): \(text)")
                current = played.moveNumber
            }
        }
        let lead = game.history.count > recent.count ? "The most recent moves. " : ""
        return lead + lines.joined(separator: ". ") + "."
    }

    /// A short situation report: the answer to "what's going on?".
    private func summary() -> String {
        let position = game.position
        var parts: [String] = []
        if game.outcome != nil {
            parts.append(turnSentence())
        } else {
            parts.append("Move \(position.fullmoveNumber). \(turnSentence())")
            if position.isCheck { parts.append("\(perspective.isAre(position.sideToMove)) in check.") }
        }
        parts.append(describer.materialBrief())
        if game.lastMove != nil { parts.append(lastMoveSentence()) }

        let first = mySide
        for color in [first, first.opposite] {
            if let king = position.kingSquare(color) {
                parts.append("\(Phrase.capitalized(perspective.owner(color))) king is on \(king.name).")
            }
        }
        if !describer.dangers(to: first).isEmpty {
            parts.append(describer.dangerReport(for: first))
        }
        if game.outcome == nil, position.sideToMove == first {
            let captures = position.legalMoves().filter { position.captureSquare(of: $0) != nil }
            let targets = Set(captures.compactMap { position.captureSquare(of: $0) })
            if !targets.isEmpty {
                let who = first == perspective.viewer ? "You have" : "\(first.name) has"
                parts.append("\(who) \(Phrase.count(targets.count, "capture")) available.")
            }
        }
        return parts.joined(separator: " ")
    }

    private func color(for side: SideRef?) -> PieceColor? {
        switch side {
        case .mine: return mySide
        case .theirs: return mySide.opposite
        case .white: return .white
        case .black: return .black
        case .both, nil: return nil
        }
    }

    // MARK: The computer's turn

    func computerMoveJob() -> (@Sendable () -> Move?)? {
        guard isComputerTurn else { return nil }
        let position = game.position
        let difficulty = difficulty
        return { ChessAI.chooseMove(in: position, difficulty: difficulty) }
    }

    func play(computerMove: Move) -> Reply {
        guard isComputerTurn, game.position.legalMoves().contains(computerMove) else {
            return Reply("The board changed while the computer was thinking.", tone: .error)
        }
        // Whatever is offered or asked no longer applies to the new position.
        pending = nil
        let mover = game.position.sideToMove
        let before = Set(describer.dangers(to: humanColor).map(\.square))
        let played = game.play(computerMove)
        let reply = announce(played, by: mover, dangersBefore: before)
        lastReply = reply
        return reply
    }
}
