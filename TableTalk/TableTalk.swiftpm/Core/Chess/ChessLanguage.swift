import Foundation

/// Which side a question is about.
enum SideRef: String, Equatable, Sendable, CaseIterable {
    case mine, theirs, white, black, both
}

enum CastleRequest: Equatable, Sendable {
    case kingside, queenside, either
}

/// Everything the player said about a move. Any part may be missing —
/// "knight f3", "takes", "e4" and "castle" are all valid requests — and the
/// position fills in the rest.
struct MoveRequest: Equatable, Sendable {
    var piece: PieceKind?
    var from: Square?
    var fromFile: Int?
    var fromRank: Int?
    var to: Square?
    var capture = false
    /// The kind of piece being captured ("takes the bishop").
    var target: PieceKind?
    var castle: CastleRequest?
    var promotion: PieceKind?

    /// True when the player gave nothing to go on.
    var isEmpty: Bool {
        piece == nil && from == nil && fromFile == nil && fromRank == nil && to == nil
            && !capture && target == nil && castle == nil
    }

    /// The moves in `candidates` that fit everything the player specified.
    func matches(in position: ChessPosition, among candidates: [Move]) -> [Move] {
        var out = candidates.filter { move in
            guard let mover = position[move.from] else { return false }
            if let castle {
                guard let side = position.castleSide(of: move) else { return false }
                switch castle {
                case .kingside: return side == .kingside
                case .queenside: return side == .queenside
                case .either: return true
                }
            }
            if let piece, mover.kind != piece { return false }
            if let from, move.from != from { return false }
            if let fromFile, move.from.file != fromFile { return false }
            if let fromRank, move.from.rank != fromRank { return false }
            if let to, move.to != to { return false }
            let captured = position.captureSquare(of: move)
            if capture && captured == nil { return false }
            if let target {
                guard let captured, position[captured]?.kind == target else { return false }
            }
            if let promotion, move.promotion != promotion { return false }
            return true
        }
        // Promote to a queen unless told otherwise: one less thing to say.
        if promotion == nil {
            out = out.filter { $0.promotion == nil || $0.promotion == .queen }
        }
        // By chess convention a bare square ("e4") means a pawn step there.
        if piece == nil, from == nil, fromFile == nil, fromRank == nil, target == nil, !capture, to != nil {
            let pawnSteps = out.filter {
                position[$0.from]?.kind == .pawn && $0.from.file == $0.to.file
            }
            if !pawnSteps.isEmpty { out = pawnSteps }
        }
        return out
    }
}

/// What the player wants, once their words are understood.
enum ChessIntent: Equatable, Sendable {
    case common(CommonIntent)
    /// One or more readings of the same words (e.g. "bc4" is a bishop move
    /// or a pawn capture); whichever fits the board wins.
    case move([MoveRequest])
    /// "Can my knight take the bishop?" — answer first, then offer to play.
    case canMove([MoveRequest])
    case whereIs(PieceKind?, SideRef?)
    case whatIsOn(Square)
    case movesFor(Square?, PieceKind?, SideRef?)
    case safety(Square?, PieceKind?, SideRef?)
    case danger(SideRef?)
    case captures(SideRef?)
    case readRank(Int)
    case readFile(Int)
    case check
    case material
    case resign
    case unknown
}

enum ChessToken: Equatable, Sendable {
    case piece(PieceKind)
    case square(Square)
    case word(String)
}

/// Turns loose, spoken or typed English into a `ChessIntent`.
///
/// Speech recognisers were not trained on chess: "knight" comes back as
/// "night" or "Nate", "b5" as "be five", "a4" as "84". Most of this file is
/// about quietly forgiving that, so the player never has to repeat
/// themselves or learn a command language.
enum ChessLanguage {

    // MARK: Vocabulary

    static let pieceWords: [String: PieceKind] = [
        "king": .king, "kings": .king,
        "queen": .queen, "queens": .queen,
        "rook": .rook, "rooks": .rook, "rock": .rook, "rocks": .rook, "brook": .rook,
        "ruk": .rook, "rookie": .rook, "tower": .rook, "towers": .rook,
        "bishop": .bishop, "bishops": .bishop, "bishup": .bishop,
        "knight": .knight, "knights": .knight, "night": .knight, "nights": .knight,
        "nite": .knight, "nate": .knight, "nates": .knight, "knit": .knight,
        "horse": .knight, "horses": .knight, "horsey": .knight,
        "pawn": .pawn, "pawns": .pawn, "pon": .pawn, "pons": .pawn, "pond": .pawn,
        "ponds": .pawn, "porn": .pawn, "paun": .pawn, "prawn": .pawn, "prawns": .pawn,
        "pawned": .pawn,
    ]

    /// Ways a file letter is said or misheard. Only trusted when a rank
    /// follows, so the article "a" and the verb "be" are safe elsewhere.
    static let fileWords: [String: Int] = [
        "a": 0, "ay": 0, "eh": 0, "alpha": 0, "alfa": 0, "anna": 0,
        "b": 1, "be": 1, "bee": 1, "bravo": 1, "bella": 1,
        "c": 2, "see": 2, "sea": 2, "si": 2, "charlie": 2, "cesar": 2, "caesar": 2,
        "d": 3, "dee": 3, "de": 3, "delta": 3, "david": 3,
        "e": 4, "ee": 4, "echo": 4, "eva": 4,
        "f": 5, "ef": 5, "eff": 5, "foxtrot": 5, "felix": 5,
        "g": 6, "gee": 6, "ji": 6, "jee": 6, "golf": 6, "gustav": 6,
        "h": 7, "aitch": 7, "age": 7, "hotel": 7, "hector": 7,
    ]

    /// File names that can never be an ordinary English word in a chess chat.
    static let unmistakableFileWords: [String: Int] = [
        "a": 0, "alpha": 0, "alfa": 0, "anna": 0,
        "b": 1, "bravo": 1, "bella": 1,
        "c": 2, "charlie": 2, "cesar": 2, "caesar": 2,
        "d": 3, "delta": 3, "david": 3,
        "e": 4, "echo": 4, "eva": 4,
        "f": 5, "foxtrot": 5, "felix": 5,
        "g": 6, "golf": 6, "gustav": 6,
        "h": 7, "hotel": 7, "hector": 7,
    ]

    static let captureVerbs: Set<String> = [
        "take", "takes", "taking", "took", "capture", "captures", "capturing",
        "x", "eat", "eats", "kill", "kills", "grab", "grabs",
    ]

    static let promotionWords: Set<String> = [
        "promote", "promotes", "promoting", "promotion", "equals", "becomes", "become", "into",
    ]

    static let questionStarters: Set<String> = [
        "what", "whats", "where", "wheres", "which", "who", "whos", "whose", "is", "are", "am",
        "can", "could", "do", "does", "did", "how", "tell", "list", "show", "read", "any",
        "anything", "name", "find", "describe", "may", "have", "has",
    ]

    // MARK: Tokens

    /// Splits input into pieces, squares and leftover words, repairing the
    /// usual speech-recognition slips along the way.
    static func tokens(_ input: String) -> [ChessToken] {
        let words = Phrase.words(input)
        var out: [ChessToken] = []
        var i = 0
        while i < words.count {
            let w = words[i]
            let chars = Array(w)

            // "e4"
            if let square = Square(w) {
                out.append(.square(square)); i += 1; continue
            }
            // "e2e4"
            if chars.count == 4, let a = Square(String(chars[0...1])), let b = Square(String(chars[2...3])) {
                out.append(.square(a)); out.append(.square(b)); i += 1; continue
            }
            // "nf3" inside a longer sentence
            if chars.count == 3, "kqrnb".contains(chars[0]), let kind = PieceKind(letter: chars[0]),
               let square = Square(String(chars[1...2])) {
                out.append(.piece(kind)); out.append(.square(square)); i += 1; continue
            }
            // "84" is how "a 4" often comes back from dictation.
            if chars.count == 2, chars[0] == "8", let rank = chars[1].wholeNumberValue, (1...8).contains(rank) {
                out.append(.square(Square(file: 0, rank: rank - 1))); i += 1; continue
            }
            // "e 4", "echo four", "be five"
            if let file = fileWords[w], i + 1 < words.count,
               let rank = Phrase.looseNumber(words[i + 1]), (1...8).contains(rank),
               Phrase.ordinalWords[words[i + 1]] == nil {
                out.append(.square(Square(file: file, rank: rank - 1))); i += 2; continue
            }
            // "before" is "b 4" when it sits where a square belongs.
            if w == "before" {
                let previous = i > 0 ? words[i - 1] : ""
                if words.count == 1 || previous == "to" || captureVerbs.contains(previous) || pieceWords[previous] != nil {
                    out.append(.square(Square(file: 1, rank: 3))); i += 1; continue
                }
            }
            if let kind = pieceWords[w] {
                out.append(.piece(kind)); i += 1; continue
            }
            out.append(.word(w))
            i += 1
        }
        return out
    }

    // MARK: Written notation

    /// Reads a single token of written notation: "Nf3", "exd5", "e2e4",
    /// "e8=Q", "O-O". Returns nil if `raw` is not notation.
    static func notation(_ raw: String) -> [MoveRequest]? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = text.last, "+#!?.,".contains(last) { text.removeLast() }
        guard !text.isEmpty, !text.contains(" ") else { return nil }

        let castle = text.lowercased().replacingOccurrences(of: "0", with: "o").replacingOccurrences(of: "-", with: "")
        if castle == "oo" { return [MoveRequest(castle: .kingside)] }
        if castle == "ooo" { return [MoveRequest(castle: .queenside)] }

        var chars = Array(text)
        var promotion: PieceKind?
        if chars.count >= 4, chars[chars.count - 2] == "=", let kind = PieceKind(letter: chars[chars.count - 1]),
           kind != .pawn, kind != .king {
            promotion = kind
            chars.removeLast(2)
        } else if chars.count >= 3, let kind = PieceKind(letter: chars[chars.count - 1]), kind != .pawn, kind != .king,
                  let rank = chars[chars.count - 2].wholeNumberValue, rank == 1 || rank == 8,
                  Square.fileIndex(chars[chars.count - 3]) != nil {
            promotion = kind
            chars.removeLast()
        }

        guard chars.count >= 2, let to = Square(String(chars[(chars.count - 2)...])),
              chars[chars.count - 2].isLowercase else { return nil }
        var prefix = Array(chars.dropLast(2))
        var capture = false
        if let last = prefix.last, last == "x" || last == "X" || last == "-" || last == ":" {
            capture = last != "-"
            prefix.removeLast()
        }

        var base = MoveRequest(to: to, capture: capture, promotion: promotion)
        switch prefix.count {
        case 0:
            return [base]
        case 1:
            let ch = prefix[0]
            if ch == "b" {
                // Lower-case "b" is the b-pawn or, typed lazily, a bishop.
                var pawn = base; pawn.piece = .pawn; pawn.fromFile = 1
                var bishop = base; bishop.piece = .bishop
                return [pawn, bishop]
            }
            if let file = Square.fileIndex(ch) {
                base.piece = .pawn; base.fromFile = file
                return [base]
            }
            guard let kind = PieceKind(letter: ch), kind != .pawn else { return nil }
            base.piece = kind
            return [base]
        case 2:
            // "e2e4": a full starting square.
            if let from = Square(String(prefix)), prefix[0].isLowercase {
                base.from = from
                return [base]
            }
            guard let kind = PieceKind(letter: prefix[0]), kind != .pawn else { return nil }
            base.piece = kind
            if let file = Square.fileIndex(prefix[1]) {
                base.fromFile = file
            } else if let rank = prefix[1].wholeNumberValue, (1...8).contains(rank) {
                base.fromRank = rank - 1
            } else {
                return nil
            }
            return [base]
        case 3:
            guard let kind = PieceKind(letter: prefix[0]), kind != .pawn,
                  let from = Square(String(prefix[1...2])) else { return nil }
            base.piece = kind
            base.from = from
            return [base]
        default:
            return nil
        }
    }

    // MARK: Understanding

    static func parse(_ input: String) -> ChessIntent {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = Phrase.words(trimmed)
        let rawWords = trimmed.split(separator: " ").map(String.init)
        guard !rawWords.isEmpty else { return .unknown }
        let asksSomething = trimmed.contains("?") || (words.first.map { questionStarters.contains($0) } ?? false)

        // Written notation, alone ("Nf3") or inside a sentence ("play Nf3").
        if rawWords.count == 1, !trimmed.contains("?"), let requests = notation(trimmed) {
            return .move(requests)
        }
        if !asksSomething {
            for raw in rawWords where raw.count >= 3 {
                if let requests = notation(raw) { return .move(requests) }
            }
        }
        guard !words.isEmpty else { return .unknown }

        let tokens = tokens(trimmed)
        let squares: [Square] = tokens.compactMap { if case .square(let s) = $0 { return s } else { return nil } }
        let pieces: [PieceKind] = tokens.compactMap { if case .piece(let k) = $0 { return k } else { return nil } }
        let text = " " + words.joined(separator: " ") + " "
        func has(_ word: String) -> Bool { words.contains(word) }
        func hasAny(_ set: Set<String>) -> Bool { words.contains { set.contains($0) } }
        func says(_ phrase: String) -> Bool { text.contains(" " + phrase + " ") }
        let side = sideRef(words)
        let startsWithCan = ["can", "could", "may"].contains(words[0])
        let mentionsCapture = hasAny(captureVerbs)

        // Castling.
        if hasAny(["castle", "castles", "castling", "castled"]) {
            var request = MoveRequest()
            if pieces.contains(.queen) || has("queenside") || has("long") {
                request.castle = .queenside
            } else if pieces.contains(.king) || has("kingside") || has("short") {
                request.castle = .kingside
            } else {
                request.castle = .either
            }
            return startsWithCan || asksSomething ? .canMove([request]) : .move([request])
        }

        // Requests every game shares. A sentence that names a square or a
        // piece is about the board, so only the short forms apply to it.
        if squares.isEmpty && pieces.isEmpty, let common = CommonIntent.parse(words) {
            return .common(common)
        }
        if !squares.isEmpty || !pieces.isEmpty, let common = CommonIntent.parse(words),
           [.undo, .newGame, .lastMove, .history, .readBoard, .summary, .repeatLast].contains(common) {
            return .common(common)
        }
        if has("resign") || says("give up") || says("i quit") { return .resign }
        if says("should i") || says("what can i do") { return .common(.hint) }

        // Reading a rank or a file.
        if let rank = rankMention(words) { return .readRank(rank) }
        if let file = fileMention(words) { return .readFile(file) }

        // "Can my knight take the bishop?"
        if startsWithCan && (!squares.isEmpty || mentionsCapture) {
            let request = moveRequest(from: tokens)
            if request.capture && request.piece == nil && request.target == nil && request.to == nil
                && request.from == nil {
                return .captures(side)
            }
            return .canMove([request])
        }

        // "What can my knight do?", "moves for d2".
        let asksMoves = (hasAny(["can", "could"]) && hasAny(["do", "go", "move", "reach"]))
            || hasAny(["moves", "options"]) || says("legal move")
        if asksMoves && (!squares.isEmpty || !pieces.isEmpty) {
            return .movesFor(squares.first, pieces.first, side)
        }

        // Attack and defence.
        let attackWords: Set<String> = [
            "attack", "attacks", "attacking", "attacked", "attacker", "attackers",
            "threatening", "threatens", "threatened", "threaten", "safe", "defend", "defends",
            "defended", "defending", "defender", "defenders", "protect", "protects", "protected",
            "protecting", "guard", "guards", "guarded", "guarding", "covered", "covers", "covering",
        ]
        if hasAny(attackWords) {
            if !squares.isEmpty || !pieces.isEmpty {
                // "What is my bishop attacking?" asks what the bishop can take.
                let activeVerbs: Set<String> = ["attacking", "threatening", "attack", "attacks", "threatens", "threaten"]
                if let verbAt = tokens.firstIndex(where: {
                    if case .word(let w) = $0 { return activeVerbs.contains(w) } else { return false }
                }) {
                    let subjectBefore = tokens[..<verbAt].contains {
                        if case .word = $0 { return false } else { return true }
                    }
                    let objectAfter = tokens[(verbAt + 1)...].contains {
                        if case .word = $0 { return false } else { return true }
                    }
                    if subjectBefore && !objectAfter && !has("attacked") {
                        return .movesFor(squares.first, pieces.first, side)
                    }
                    // "Is the bishop attacking my queen?" is about the queen.
                    if subjectBefore && objectAfter {
                        for token in tokens[(verbAt + 1)...] {
                            if case .square(let s) = token { return .safety(s, nil, side) }
                            if case .piece(let k) = token { return .safety(nil, k, side) }
                        }
                    }
                }
                return .safety(squares.first, pieces.first, side)
            }
            if says("i attacking") || says("i threatening") || says("do i attack") || says("can i attack")
                || says("do i threaten") {
                return .captures(side ?? .mine)
            }
            return .danger(side)
        }
        if hasAny(["danger", "dangers", "hanging", "threat", "threats", "unsafe", "risk", "loose",
                   "undefended", "unprotected", "trouble"]) || says("en prise") || says("under attack") {
            return .danger(side)
        }
        if (mentionsCapture || has("captures")) && squares.isEmpty && pieces.isEmpty {
            return .captures(side)
        }

        // "Am I in check?"
        if says("in check") || text == " check " || says("check status") { return .check }
        if hasAny(["material", "score", "winning", "ahead", "behind", "points", "losing"])
            || says("who is better") || says("whos better") {
            return .material
        }

        // "Where are my knights?", "do I have any bishops?"
        let asksLocation = hasAny(["where", "wheres", "find", "locate"]) || says("how many")
        let mentionsPieces = !pieces.isEmpty || hasAny(["pieces", "piece", "everything"])
        if squares.isEmpty && !mentionsCapture && (asksLocation || (asksSomething && mentionsPieces)) {
            return .whereIs(pieces.first, side)
        }

        // "What's on e4?"
        // ("What about knight to f3?" names a piece heading somewhere, so it
        // is left for the move reader below.)
        if squares.count == 1 && (asksSomething || has("square"))
            && (pieces.isEmpty || has("on") || has("at")) {
            return .whatIsOn(squares[0])
        }

        // Anything else that names a piece or a square is a move.
        // A question is answered, never played: "what about knight f3?"
        // offers the move instead of making it.
        let request = moveRequest(from: tokens)
        if request.isEmpty { return .unknown }
        return asksSomething ? .canMove([request]) : .move([request])
    }

    /// Words that sit between a preposition and the thing it points at.
    static let fillerWords: Set<String> = [
        "my", "the", "a", "an", "your", "that", "this", "their", "his", "her", "its", "own",
    ]

    /// Builds a move request from spoken words: "knight on f3 takes the pawn",
    /// "take the bishop with my queen", "pawn to e8, promote to a knight".
    static func moveRequest(from tokens: [ChessToken]) -> MoveRequest {
        enum Role { case mover, target, promotion }
        var request = MoveRequest()
        var ordered: [Square] = []
        var sawCapture = false
        var expectPromotion = false
        var lastRole: Role?
        var lastPieceIndex: Int?

        /// The nearest earlier word, skipping "my", "the" and friends.
        func leadingWord(before index: Int) -> String? {
            var j = index - 1
            while j >= 0 {
                guard case .word(let w) = tokens[j] else { return nil }
                if !fillerWords.contains(w) { return w }
                j -= 1
            }
            return nil
        }
        func captureComesLater(_ index: Int) -> Bool {
            tokens[(index + 1)...].contains {
                if case .word(let w) = $0 { return captureVerbs.contains(w) } else { return false }
            }
        }

        for (i, token) in tokens.enumerated() {
            switch token {
            case .word(let w):
                if captureVerbs.contains(w) {
                    sawCapture = true
                    request.capture = true
                } else if promotionWords.contains(w) {
                    expectPromotion = true
                } else if w.count == 1, let file = unmistakableFileWords[w], i + 1 < tokens.count,
                          tokens[i + 1] == .piece(.pawn),
                          w != "a" || (i > 0 && tokens[i - 1] == .word("the")) {
                    // "the c pawn". A lone "a" is only a file after "the":
                    // "move a pawn" must not mean the a-file.
                    request.fromFile = file
                }

            case .piece(let kind):
                let previous = leadingWord(before: i)
                // A piece named after a destination on the last rank is what
                // the pawn becomes: "e8 queen".
                let onLastRank = ordered.last.map { $0.rank == 0 || $0.rank == 7 } ?? false
                let promotesHere = onLastRank && kind != .pawn && kind != .king
                    && (request.piece == nil || request.piece == .pawn)
                if expectPromotion {
                    request.promotion = kind
                    expectPromotion = false
                    lastRole = .promotion
                } else if previous == "with" || previous == "using" || previous == "by" {
                    request.piece = kind
                    lastRole = .mover
                } else if sawCapture && request.target == nil {
                    request.target = kind
                    lastRole = .target
                } else if promotesHere {
                    request.promotion = kind
                    lastRole = .promotion
                } else if request.piece == nil {
                    request.piece = kind
                    lastRole = .mover
                }
                lastPieceIndex = i

            case .square(let square):
                let previous = leadingWord(before: i)
                // "knight on f3": the square says where a named piece stands.
                let locatesPiece = (previous == "on" || previous == "at") && lastPieceIndex == i - 2
                if previous == "from" {
                    request.from = square
                } else if locatesPiece && lastRole == .mover && request.from == nil {
                    request.from = square
                } else if !locatesPiece && !sawCapture && captureComesLater(i) && request.from == nil {
                    // "f3 takes e5": the square before the verb is the start.
                    request.from = square
                } else {
                    ordered.append(square)
                }
            }
        }

        if request.from != nil {
            request.to = ordered.first
        } else if ordered.count >= 2 {
            request.from = ordered[0]
            request.to = ordered[1]
        } else {
            request.to = ordered.first
        }
        return request
    }

    // MARK: Small helpers

    static func sideRef(_ words: [String]) -> SideRef? {
        func hasAny(_ set: Set<String>) -> Bool { words.contains { set.contains($0) } }
        if hasAny(["white", "whites"]) { return .white }
        if hasAny(["black", "blacks"]) { return .black }
        if hasAny(["their", "theirs", "his", "her", "hers", "opponent", "opponents", "enemy", "enemies",
                   "computer", "computers", "they", "them", "he", "she", "other"]) { return .theirs }
        if hasAny(["my", "mine", "our", "ours", "own"]) { return .mine }
        if hasAny(["both", "everyone", "everything", "all"]) { return .both }
        if hasAny(["i", "me", "im"]) { return .mine }
        return nil
    }

    /// Finds "rank 4", "fourth rank", "row four". Returns 0...7.
    static func rankMention(_ words: [String]) -> Int? {
        guard let at = words.firstIndex(where: { $0 == "rank" || $0 == "row" }) else { return nil }
        if at + 1 < words.count, let n = Phrase.looseNumber(words[at + 1]), (1...8).contains(n) { return n - 1 }
        if at > 0, let n = Phrase.number(words[at - 1]), (1...8).contains(n) { return n - 1 }
        return nil
    }

    /// Finds "e file", "file e", "column echo". Returns 0...7.
    static func fileMention(_ words: [String]) -> Int? {
        guard let at = words.firstIndex(where: { $0 == "file" || $0 == "column" }) else { return nil }
        if at > 0, let file = unmistakableFileWords[words[at - 1]],
           words[at - 1] != "a" || (at > 1 && words[at - 2] == "the") { return file }
        if at + 1 < words.count, let file = unmistakableFileWords[words[at + 1]] { return file }
        return nil
    }
}
