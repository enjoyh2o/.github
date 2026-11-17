import Foundation

enum PieceColor: Int, CaseIterable, Sendable {
    case white, black

    var opposite: PieceColor { self == .white ? .black : .white }
    var name: String { self == .white ? "White" : "Black" }
}

enum PieceKind: Int, CaseIterable, Sendable {
    case pawn, knight, bishop, rook, queen, king

    var name: String {
        switch self {
        case .pawn: return "pawn"
        case .knight: return "knight"
        case .bishop: return "bishop"
        case .rook: return "rook"
        case .queen: return "queen"
        case .king: return "king"
        }
    }

    var plural: String { name + "s" }

    /// The usual teaching values: pawn 1, knight and bishop 3, rook 5, queen 9.
    var points: Int {
        switch self {
        case .pawn: return 1
        case .knight, .bishop: return 3
        case .rook: return 5
        case .queen: return 9
        case .king: return 0
        }
    }

    /// Value used when asking "is this trade bad for me?". The king counts as
    /// priceless so it is never treated as a cheap attacker.
    var tradeValue: Int { self == .king ? 100 : points }

    /// Upper-case letter used in written notation ("N" for knight).
    var letter: Character {
        switch self {
        case .pawn: return "P"
        case .knight: return "N"
        case .bishop: return "B"
        case .rook: return "R"
        case .queen: return "Q"
        case .king: return "K"
        }
    }

    init?(letter: Character) {
        switch letter {
        case "p", "P": self = .pawn
        case "n", "N": self = .knight
        case "b", "B": self = .bishop
        case "r", "R": self = .rook
        case "q", "Q": self = .queen
        case "k", "K": self = .king
        default: return nil
        }
    }
}

struct Piece: Hashable, Sendable {
    var color: PieceColor
    var kind: PieceKind
}

/// One of the 64 squares. `index` 0 is a1, 7 is h1, 56 is a8 and 63 is h8.
struct Square: Hashable, Comparable, Sendable {
    let index: Int

    init(index: Int) {
        precondition((0..<64).contains(index), "square index out of range")
        self.index = index
    }

    /// `file` 0...7 is a...h, `rank` 0...7 is rank 1...8.
    init(file: Int, rank: Int) {
        self.init(index: rank * 8 + file)
    }

    /// Parses "e4". Returns nil for anything else.
    init?(_ name: String) {
        let chars = Array(name.lowercased())
        guard chars.count == 2,
              let file = Square.fileIndex(chars[0]),
              let rank = chars[1].wholeNumberValue, (1...8).contains(rank)
        else { return nil }
        self.init(file: file, rank: rank - 1)
    }

    var file: Int { index & 7 }
    var rank: Int { index >> 3 }
    var name: String { "\(Square.fileLetter(file))\(rank + 1)" }
    var isLight: Bool { (file + rank) % 2 == 1 }

    static func < (a: Square, b: Square) -> Bool { a.index < b.index }

    static let all: [Square] = (0..<64).map { Square(index: $0) }

    static func fileLetter(_ file: Int) -> Character {
        Character(UnicodeScalar(UInt8(97 + file)))
    }

    static func fileIndex(_ ch: Character) -> Int? {
        guard let ascii = ch.asciiValue, ascii >= 97, ascii <= 104 else { return nil }
        return Int(ascii) - 97
    }
}

struct Move: Hashable, Sendable {
    let from: Square
    let to: Square
    var promotion: PieceKind? = nil

    /// Coordinate form, e.g. "e2e4" or "e7e8q".
    var coordinates: String {
        var s = from.name + to.name
        if let promotion { s.append(Character(String(promotion.letter).lowercased())) }
        return s
    }
}

enum CastleSide: Sendable, Equatable {
    case kingside, queenside

    var name: String { self == .kingside ? "kingside" : "queenside" }
}

struct CastlingRights: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let whiteKingside = CastlingRights(rawValue: 1)
    static let whiteQueenside = CastlingRights(rawValue: 2)
    static let blackKingside = CastlingRights(rawValue: 4)
    static let blackQueenside = CastlingRights(rawValue: 8)
    static let all: CastlingRights = [.whiteKingside, .whiteQueenside, .blackKingside, .blackQueenside]

    static func right(_ color: PieceColor, _ side: CastleSide) -> CastlingRights {
        switch (color, side) {
        case (.white, .kingside): return .whiteKingside
        case (.white, .queenside): return .whiteQueenside
        case (.black, .kingside): return .blackKingside
        case (.black, .queenside): return .blackQueenside
        }
    }
}

/// How a game ended.
enum ChessOutcome: Equatable, Sendable {
    enum DrawReason: Equatable, Sendable {
        case stalemate, repetition, fiftyMoves, insufficientMaterial
    }

    case checkmate(winner: PieceColor)
    case resignation(winner: PieceColor)
    case draw(DrawReason)

    var winner: PieceColor? {
        switch self {
        case .checkmate(let winner), .resignation(let winner): return winner
        case .draw: return nil
        }
    }
}
