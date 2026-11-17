import Foundation

/// Who the words "you" and "your" refer to.
struct ChessPerspective: Equatable, Sendable {
    /// The colour the listener plays, or nil when two people share the device
    /// (then both sides are simply called White and Black).
    var viewer: PieceColor?

    /// "your" / "White's" / "Black's"
    func owner(_ color: PieceColor) -> String {
        color == viewer ? "your" : "\(color.name)'s"
    }

    /// "you" / "White" / "Black"
    func side(_ color: PieceColor) -> String {
        color == viewer ? "you" : color.name
    }

    /// "You have" / "Black has"
    func has(_ color: PieceColor) -> String {
        color == viewer ? "You have" : "\(color.name) has"
    }

    /// "You are" / "Black is"
    func isAre(_ color: PieceColor) -> String {
        color == viewer ? "You are" : "\(color.name) is"
    }
}

/// Answers questions about a position in plain sentences.
///
/// This is the heart of TableTalk. Every fact comes straight from the rules
/// engine, never from a language model, so a player who cannot see the board
/// can trust every word.
struct ChessDescriber: Sendable {
    let position: ChessPosition
    let perspective: ChessPerspective

    // MARK: Naming things

    /// "your knight on f3", or just "f3" for an empty square.
    func name(_ square: Square) -> String {
        guard let piece = position[square] else { return square.name }
        return "\(perspective.owner(piece.color)) \(piece.kind.name) on \(square.name)"
    }

    /// Names several pieces of one colour without repeating the owner:
    /// "your knight on c3 and queen on d1".
    func names(_ squares: [Square]) -> String {
        var parts: [String] = []
        var lastOwner: PieceColor?
        for square in squares {
            guard let piece = position[square] else { parts.append(square.name); continue }
            if piece.color == lastOwner {
                parts.append("\(piece.kind.name) on \(square.name)")
            } else {
                parts.append(name(square))
                lastOwner = piece.color
            }
        }
        return Phrase.list(parts)
    }

    /// Squares in the order a player lists them: a-file across to h-file.
    private func listed(_ kind: PieceKind, _ color: PieceColor) -> [Square] {
        position.squares(of: kind, color: color).sorted { ($0.file, $0.rank) < ($1.file, $1.rank) }
    }

    // MARK: Where are my knights?

    func whereAre(_ kind: PieceKind, color: PieceColor) -> String {
        let squares = listed(kind, color).map(\.name)
        let owner = Phrase.capitalized(perspective.owner(color))
        switch squares.count {
        case 0:
            let none = kind == .queen || kind == .king ? "no \(kind.name)" : "no \(kind.plural) left"
            return "\(perspective.has(color)) \(none)."
        case 1:
            return "\(owner) \(kind.name) is on \(squares[0])."
        default:
            return "\(owner) \(kind.plural) are on \(Phrase.list(squares))."
        }
    }

    /// Every piece one side has, most valuable first.
    func allPieces(of color: PieceColor) -> String {
        var groups: [String] = []
        for kind in [PieceKind.king, .queen, .rook, .bishop, .knight, .pawn] {
            let squares = listed(kind, color).map(\.name)
            guard !squares.isEmpty else { continue }
            let label = squares.count == 1 ? kind.name : kind.plural
            groups.append("\(label) on \(Phrase.list(squares))")
        }
        let owner = Phrase.capitalized(perspective.owner(color))
        return "\(owner) pieces: \(groups.joined(separator: "; "))."
    }

    func readBoard() -> String {
        let first = perspective.viewer ?? .white
        return allPieces(of: first) + " " + allPieces(of: first.opposite)
    }

    func readRank(_ rank: Int) -> String {
        let squares = (0..<8).map { Square(file: $0, rank: rank) }.filter { position[$0] != nil }
        if squares.isEmpty { return "Rank \(rank + 1) is empty." }
        let rest = squares.count == 8 ? "" : " The other squares are empty."
        return "Rank \(rank + 1), from a to h: \(Phrase.list(squares.map(name))).\(rest)"
    }

    func readFile(_ file: Int) -> String {
        let label = "\(Square.fileLetter(file))-file"
        let squares = (0..<8).map { Square(file: file, rank: $0) }.filter { position[$0] != nil }
        if squares.isEmpty { return "The \(label) is empty." }
        let rest = squares.count == 8 ? "" : " The other squares are empty."
        return "The \(label), from rank 1 up: \(Phrase.list(squares.map(name))).\(rest)"
    }

    // MARK: What's on e4?

    func whatIsOn(_ square: Square) -> String {
        guard let piece = position[square] else {
            var out = "\(square.name) is empty."
            let white = position.attackers(of: square, by: .white)
            let black = position.attackers(of: square, by: .black)
            let first = perspective.viewer ?? .white
            let ordered = first == .white ? [white, black] : [black, white]
            let covering = ordered.filter { !$0.isEmpty }.map { names($0) }
            if covering.isEmpty {
                out += " Nothing attacks it."
            } else {
                out += " It is covered by \(covering.joined(separator: ", and by "))."
            }
            return out
        }
        let what = "\(Phrase.capitalized(perspective.owner(piece.color))) \(piece.kind.name) is on \(square.name)."
        return what + " " + safety(of: square)
    }

    /// "It is attacked by … and defended by …" for an occupied square.
    func safety(of square: Square) -> String {
        guard let piece = position[square] else { return whatIsOn(square) }
        let attackers = position.attackers(of: square, by: piece.color.opposite)
        let defenders = position.attackers(of: square, by: piece.color)
        if piece.kind == .king {
            return attackers.isEmpty ? "It is not in check." : "It is in check from \(names(attackers))."
        }
        if attackers.isEmpty {
            return defenders.isEmpty
                ? "It is not attacked, and nothing defends it."
                : "It is not attacked. It is defended by \(names(defenders))."
        }
        let defence = defenders.isEmpty ? "nothing defends it" : "it is defended by \(names(defenders))"
        return "It is attacked by \(names(attackers)), and \(defence)."
    }

    /// The full answer to "is my queen safe?" / "what is attacking e4?".
    func attackReport(on square: Square) -> String {
        guard position[square] != nil else { return whatIsOn(square) }
        return "\(Phrase.capitalized(name(square))): " + lowercasedFirst(safety(of: square))
    }

    // MARK: What can my knight do?

    func moves(from square: Square) -> String {
        guard let piece = position[square] else { return "There is no piece on \(square.name)." }
        let board = position.withSideToMove(piece.color)
        let legal = board.legalMoves(from: square)
        let subject = Phrase.capitalized(name(square))
        if legal.isEmpty {
            let why = board.isCheck && piece.kind != .king ? " It cannot help against the check." : ""
            return "\(subject) has no legal moves.\(why)"
        }

        var quiet: [String] = []
        var captures: [String] = []
        var castles: [String] = []
        var seen = Set<Square>()
        // Alphabetical order is the easiest to follow by ear.
        for move in legal.sorted(by: { $0.to.name < $1.to.name }) where seen.insert(move.to).inserted {
            if let side = board.castleSide(of: move) {
                castles.append("castle \(side.name)")
            } else if let target = board.captureSquare(of: move), let victim = board[target] {
                let enPassant = target != move.to ? " en passant" : ""
                captures.append("the \(victim.kind.name) on \(target.name)\(enPassant)")
            } else {
                quiet.append(move.to.name + (move.promotion != nil ? " to promote" : ""))
            }
        }

        var sentences: [String] = []
        if !quiet.isEmpty {
            sentences.append("\(subject) can go to \(Phrase.list(quiet, conjunction: "or")).")
        }
        if !captures.isEmpty {
            let lead = quiet.isEmpty ? subject : "It"
            sentences.append("\(lead) can capture \(Phrase.list(captures, conjunction: "or")).")
        }
        if !castles.isEmpty {
            let lead = sentences.isEmpty ? subject : "It"
            sentences.append("\(lead) can \(Phrase.list(castles, conjunction: "or")).")
        }
        return sentences.joined(separator: " ")
    }

    func moves(of kind: PieceKind, color: PieceColor) -> String {
        let squares = listed(kind, color)
        if squares.isEmpty { return whereAre(kind, color: color) }
        if kind == .pawn && squares.count > 3 {
            // Eight separate sentences is too much to listen to; summarise.
            let board = position.withSideToMove(color)
            let movable = squares.filter { !board.legalMoves(from: $0).isEmpty }
            if movable.isEmpty { return "None of \(perspective.owner(color)) pawns can move." }
            return "\(Phrase.capitalized(perspective.owner(color))) pawns on \(Phrase.list(movable.map(\.name))) can move. "
                + "Ask about one, for example: what can the pawn on \(movable[0].name) do?"
        }
        return squares.map { moves(from: $0) }.joined(separator: " ")
    }

    // MARK: What's in danger?

    struct Danger: Equatable, Sendable {
        let square: Square
        let attackers: [Square]
        let defended: Bool
    }

    /// Pieces of `color` that could be lost: attacked with no defender, or
    /// attacked by something cheaper than themselves.
    func dangers(to color: PieceColor) -> [Danger] {
        var out: [Danger] = []
        for square in position.squares(color: color) {
            guard let piece = position[square], piece.kind != .king else { continue }
            let attackers = position.attackers(of: square, by: color.opposite)
            guard let cheapest = attackers.first, let attacker = position[cheapest] else { continue }
            let defended = position.isAttacked(square, by: color)
            if !defended || attacker.kind.tradeValue < piece.kind.tradeValue {
                out.append(Danger(square: square, attackers: attackers, defended: defended))
            }
        }
        // Most valuable first.
        return out.sorted {
            let a = position[$0.square]!.kind.tradeValue
            let b = position[$1.square]!.kind.tradeValue
            return a != b ? a > b : $0.square < $1.square
        }
    }

    func describe(_ danger: Danger) -> String {
        let defence = danger.defended ? "" : " and has no defender"
        return "\(name(danger.square)) is attacked by \(names(danger.attackers))\(defence)"
    }

    func dangerReport(for color: PieceColor) -> String {
        var sentences: [String] = []
        if position.sideToMove == color, position.isCheck, let king = position.kingSquare(color) {
            let checkers = position.attackers(of: king, by: color.opposite)
            sentences.append("\(perspective.isAre(color)) in check from \(names(checkers)).")
        }
        let dangers = dangers(to: color)
        if dangers.isEmpty {
            if sentences.isEmpty {
                let whose = color == perspective.viewer ? "of yours" : "of \(color.name)'s"
                sentences.append("Nothing \(whose) is in danger right now.")
            }
        } else {
            sentences.append("In danger: " + dangers.map { describe($0) }.joined(separator: "; ") + ".")
        }
        return sentences.joined(separator: " ")
    }

    // MARK: What can I take?

    func captureReport(for color: PieceColor) -> String {
        let board = position.withSideToMove(color)
        var byTarget: [(target: Square, from: [Square])] = []
        for move in board.legalMoves() {
            guard let target = board.captureSquare(of: move) else { continue }
            if let i = byTarget.firstIndex(where: { $0.target == target }) {
                if !byTarget[i].from.contains(move.from) { byTarget[i].from.append(move.from) }
            } else {
                byTarget.append((target, [move.from]))
            }
        }
        if byTarget.isEmpty {
            return "\(perspective.has(color)) no captures available."
        }
        byTarget.sort {
            let a = board[$0.target]!.kind.tradeValue
            let b = board[$1.target]!.kind.tradeValue
            return a != b ? a > b : $0.target < $1.target
        }
        let can = color == perspective.viewer ? "You can" : "\(color.name) can"
        // Four targets is plenty to listen to; the rest are the least valuable.
        var sentences = byTarget.prefix(4).map { entry -> String in
            let guarded = board.isAttacked(entry.target, by: color.opposite)
                ? "it is defended" : "nothing defends it"
            let with = Phrase.list(entry.from.map { "the \(board[$0]!.kind.name) on \($0.name)" }, conjunction: "or")
            return "\(can) capture \(name(entry.target)) with \(with); \(guarded)."
        }
        if byTarget.count > 4 {
            sentences.append("There are \(byTarget.count - 4) more captures of lesser pieces.")
        }
        return sentences.joined(separator: " ")
    }

    // MARK: Material

    func points(_ color: PieceColor) -> Int {
        position.squares(color: color).reduce(0) { $0 + (position[$1]?.kind.points ?? 0) }
    }

    func material() -> String {
        let first = perspective.viewer ?? .white
        let second = first.opposite
        let a = points(first)
        let b = points(second)
        if a == b { return "Material is even, \(a) points each." }
        let leader = a > b ? first : second
        // `second` is never the listener, so "has" is always right for it.
        return "\(perspective.has(first)) \(a) points of material and \(second.name) has \(b). "
            + "\(perspective.isAre(leader)) ahead by \(abs(a - b))."
    }

    /// One short phrase for summaries: "material is even", "you are up 3 points".
    func materialBrief() -> String {
        let first = perspective.viewer ?? .white
        let diff = points(first) - points(first.opposite)
        if diff == 0 { return "Material is even." }
        let leader = diff > 0 ? first : first.opposite
        return "\(perspective.isAre(leader)) ahead by \(Phrase.count(abs(diff), "point"))."
    }

    private func lowercasedFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.lowercased() + s.dropFirst()
    }
}

/// Turns a played move into words.
enum ChessNarration {

    /// "knight from g1 to f3", "pawn on e4 takes pawn on d5", "castles kingside".
    /// With `detailed` off, the starting square of quiet piece moves is left out.
    static func describe(_ played: PlayedMove, detailed: Bool = true) -> String {
        if let castle = played.castle { return "castles \(castle.name)" }
        let piece = played.piece.kind.name
        let from = played.move.from.name
        let to = played.move.to.name
        var out: String

        if let captured = played.captured {
            if played.isEnPassant {
                out = "pawn on \(from) takes pawn en passant, landing on \(to)"
            } else if detailed || played.piece.kind == .pawn {
                out = "\(piece) on \(from) takes \(captured.kind.name) on \(to)"
            } else {
                out = "\(piece) takes \(captured.kind.name) on \(to)"
            }
        } else if played.piece.kind == .pawn || !detailed {
            out = "\(piece) to \(to)"
        } else {
            out = "\(piece) from \(from) to \(to)"
        }
        if let promotion = played.move.promotion {
            out += ", promoting to a \(promotion.name)"
        }
        return out
    }

    static func describe(_ outcome: ChessOutcome, perspective: ChessPerspective) -> String {
        func wins(_ color: PieceColor) -> String {
            color == perspective.viewer ? "You win" : "\(color.name) wins"
        }
        switch outcome {
        case .checkmate(let winner):
            return "Checkmate. \(wins(winner))."
        case .resignation(let winner):
            let loser = winner.opposite
            let who = loser == perspective.viewer ? "You resigned" : "\(loser.name) resigned"
            return "\(who). \(wins(winner))."
        case .draw(.stalemate):
            return "Stalemate. The game is a draw."
        case .draw(.repetition):
            return "The same position has come up three times. The game is a draw."
        case .draw(.fiftyMoves):
            return "Fifty moves without a capture or pawn move. The game is a draw."
        case .draw(.insufficientMaterial):
            return "Neither side has enough pieces left to checkmate. The game is a draw."
        }
    }
}
