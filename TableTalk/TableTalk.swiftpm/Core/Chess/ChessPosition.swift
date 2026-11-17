import Foundation

/// Precomputed "who can reach whom" tables, built once on first use.
enum ChessGeometry {
    /// Directions 0...3 are rook lines, 4...7 are bishop lines.
    static let directions: [(df: Int, dr: Int)] = [
        (0, 1), (0, -1), (1, 0), (-1, 0),
        (1, 1), (1, -1), (-1, 1), (-1, -1),
    ]

    /// `rays[square][direction]` lists the squares met walking outward.
    static let rays: [[[Int]]] = (0..<64).map { sq in
        directions.map { d in
            var out: [Int] = []
            var f = (sq & 7) + d.df
            var r = (sq >> 3) + d.dr
            while (0..<8).contains(f) && (0..<8).contains(r) {
                out.append(r * 8 + f)
                f += d.df
                r += d.dr
            }
            return out
        }
    }

    static let knightTargets: [[Int]] = jumps([
        (1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2),
    ])

    static let kingTargets: [[Int]] = jumps([
        (0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1),
    ])

    private static func jumps(_ steps: [(Int, Int)]) -> [[Int]] {
        (0..<64).map { sq in
            steps.compactMap { step in
                let f = (sq & 7) + step.0
                let r = (sq >> 3) + step.1
                return (0..<8).contains(f) && (0..<8).contains(r) ? r * 8 + f : nil
            }
        }
    }
}

/// A complete chess position: where everything is, whose turn it is, and the
/// bits of history the rules need (castling rights, en passant, move clocks).
///
/// It is a value type on purpose. Copying a position is how the app looks
/// ahead, takes moves back, and hands work to a background thread safely.
struct ChessPosition: Equatable, Sendable {
    private(set) var board: [Piece?]
    var sideToMove: PieceColor
    var castling: CastlingRights
    var enPassant: Square?
    /// Half-moves since the last capture or pawn move (for the fifty-move rule).
    var halfmoveClock: Int
    var fullmoveNumber: Int
    /// King locations, kept up to date so check tests never scan the board.
    private var kingIndex: [Int]

    static let start = ChessPosition(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")!

    // MARK: Reading the board

    subscript(square: Square) -> Piece? { board[square.index] }

    func kingSquare(_ color: PieceColor) -> Square? {
        let i = kingIndex[color.rawValue]
        return i >= 0 ? Square(index: i) : nil
    }

    /// Squares holding pieces of one colour, optionally of one kind, a1 first.
    func squares(of kind: PieceKind? = nil, color: PieceColor) -> [Square] {
        var out: [Square] = []
        for i in 0..<64 {
            guard let p = board[i], p.color == color else { continue }
            if kind == nil || p.kind == kind { out.append(Square(index: i)) }
        }
        return out
    }

    // MARK: Attacks

    /// True if any piece of `color` attacks `target`. Written for speed: this
    /// runs for every move the app considers.
    func isAttacked(_ target: Square, by color: PieceColor) -> Bool {
        isAttacked(index: target.index, by: color)
    }

    private func isAttacked(index t: Int, by color: PieceColor) -> Bool {
        let f = t & 7
        let r = t >> 3
        // A white pawn attacks diagonally upward, so it stands one rank below.
        let pawnRank = color == .white ? r - 1 : r + 1
        if (0..<8).contains(pawnRank) {
            if f > 0, let p = board[pawnRank * 8 + f - 1], p.kind == .pawn, p.color == color { return true }
            if f < 7, let p = board[pawnRank * 8 + f + 1], p.kind == .pawn, p.color == color { return true }
        }
        for s in ChessGeometry.knightTargets[t] {
            if let p = board[s], p.kind == .knight, p.color == color { return true }
        }
        for s in ChessGeometry.kingTargets[t] {
            if let p = board[s], p.kind == .king, p.color == color { return true }
        }
        let rays = ChessGeometry.rays[t]
        for d in 0..<8 {
            let lineKind: PieceKind = d < 4 ? .rook : .bishop
            for s in rays[d] {
                guard let p = board[s] else { continue }
                if p.color == color && (p.kind == .queen || p.kind == lineKind) { return true }
                break
            }
        }
        return false
    }

    /// Every square holding a piece of `color` that attacks `target`.
    /// Asked about a square holding a piece of the same colour, this returns
    /// that piece's defenders.
    func attackers(of target: Square, by color: PieceColor) -> [Square] {
        let t = target.index
        let f = t & 7
        let r = t >> 3
        var out: [Int] = []
        let pawnRank = color == .white ? r - 1 : r + 1
        if (0..<8).contains(pawnRank) {
            if f > 0, let p = board[pawnRank * 8 + f - 1], p.kind == .pawn, p.color == color {
                out.append(pawnRank * 8 + f - 1)
            }
            if f < 7, let p = board[pawnRank * 8 + f + 1], p.kind == .pawn, p.color == color {
                out.append(pawnRank * 8 + f + 1)
            }
        }
        for s in ChessGeometry.knightTargets[t] {
            if let p = board[s], p.kind == .knight, p.color == color { out.append(s) }
        }
        for s in ChessGeometry.kingTargets[t] {
            if let p = board[s], p.kind == .king, p.color == color { out.append(s) }
        }
        let rays = ChessGeometry.rays[t]
        for d in 0..<8 {
            let lineKind: PieceKind = d < 4 ? .rook : .bishop
            for s in rays[d] {
                guard let p = board[s] else { continue }
                if p.color == color && (p.kind == .queen || p.kind == lineKind) { out.append(s) }
                break
            }
        }
        // Cheapest attacker first: that is the one a player worries about.
        return out.map { Square(index: $0) }.sorted {
            let a = board[$0.index]!.kind.tradeValue
            let b = board[$1.index]!.kind.tradeValue
            return a != b ? a < b : $0 < $1
        }
    }

    /// True when the side to move is in check.
    var isCheck: Bool {
        guard let king = kingSquare(sideToMove) else { return false }
        return isAttacked(king, by: sideToMove.opposite)
    }

    // MARK: Move generation

    /// Every move that obeys how the pieces move, including ones that would
    /// leave the mover's own king in check. `legalMoves()` filters those out.
    func pseudoLegalMoves() -> [Move] {
        var moves: [Move] = []
        moves.reserveCapacity(48)
        let us = sideToMove
        for i in 0..<64 {
            guard let piece = board[i], piece.color == us else { continue }
            switch piece.kind {
            case .pawn:
                addPawnMoves(from: i, color: us, into: &moves)
            case .knight:
                addJumps(from: i, targets: ChessGeometry.knightTargets[i], color: us, into: &moves)
            case .king:
                addJumps(from: i, targets: ChessGeometry.kingTargets[i], color: us, into: &moves)
                addCastling(from: i, color: us, into: &moves)
            case .bishop:
                addSlides(from: i, directions: 4..<8, color: us, into: &moves)
            case .rook:
                addSlides(from: i, directions: 0..<4, color: us, into: &moves)
            case .queen:
                addSlides(from: i, directions: 0..<8, color: us, into: &moves)
            }
        }
        return moves
    }

    private func addJumps(from i: Int, targets: [Int], color: PieceColor, into moves: inout [Move]) {
        let from = Square(index: i)
        for t in targets {
            if let p = board[t], p.color == color { continue }
            moves.append(Move(from: from, to: Square(index: t)))
        }
    }

    private func addSlides(from i: Int, directions: Range<Int>, color: PieceColor, into moves: inout [Move]) {
        let from = Square(index: i)
        let rays = ChessGeometry.rays[i]
        for d in directions {
            for t in rays[d] {
                if let p = board[t] {
                    if p.color != color { moves.append(Move(from: from, to: Square(index: t))) }
                    break
                }
                moves.append(Move(from: from, to: Square(index: t)))
            }
        }
    }

    private func addPawnMoves(from i: Int, color: PieceColor, into moves: inout [Move]) {
        let f = i & 7
        let r = i >> 3
        let step = color == .white ? 1 : -1
        let startRank = color == .white ? 1 : 6
        let lastRank = color == .white ? 7 : 0
        let nextRank = r + step
        guard (0..<8).contains(nextRank) else { return }
        let from = Square(index: i)

        func add(_ t: Int) {
            let to = Square(index: t)
            if nextRank == lastRank {
                for kind in [PieceKind.queen, .rook, .bishop, .knight] {
                    moves.append(Move(from: from, to: to, promotion: kind))
                }
            } else {
                moves.append(Move(from: from, to: to))
            }
        }

        let one = nextRank * 8 + f
        if board[one] == nil {
            add(one)
            if r == startRank {
                let two = (r + 2 * step) * 8 + f
                if board[two] == nil { moves.append(Move(from: from, to: Square(index: two))) }
            }
        }
        for df in [-1, 1] {
            let nf = f + df
            guard (0..<8).contains(nf) else { continue }
            let t = nextRank * 8 + nf
            if let target = board[t] {
                if target.color != color { add(t) }
            } else if let ep = enPassant, ep.index == t {
                moves.append(Move(from: from, to: ep))
            }
        }
    }

    private func addCastling(from i: Int, color: PieceColor, into moves: inout [Move]) {
        let home = color == .white ? 4 : 60
        guard i == home else { return }
        let them = color.opposite
        let hasKingside = castling.contains(.right(color, .kingside))
        let hasQueenside = castling.contains(.right(color, .queenside))
        guard hasKingside || hasQueenside else { return }
        // No castling out of check.
        guard !isAttacked(index: home, by: them) else { return }

        func isOwnRook(_ s: Int) -> Bool {
            if let p = board[s], p.kind == .rook, p.color == color { return true }
            return false
        }

        // The king may not pass through or land on an attacked square.
        if hasKingside, board[home + 1] == nil, board[home + 2] == nil, isOwnRook(home + 3),
           !isAttacked(index: home + 1, by: them), !isAttacked(index: home + 2, by: them) {
            moves.append(Move(from: Square(index: home), to: Square(index: home + 2)))
        }
        if hasQueenside, board[home - 1] == nil, board[home - 2] == nil, board[home - 3] == nil,
           isOwnRook(home - 4),
           !isAttacked(index: home - 1, by: them), !isAttacked(index: home - 2, by: them) {
            moves.append(Move(from: Square(index: home), to: Square(index: home - 2)))
        }
    }

    /// Plays a pseudo-legal move and returns the result, or nil if the move
    /// would leave the mover's own king in check.
    func applyingIfLegal(_ move: Move) -> ChessPosition? {
        let us = sideToMove
        var next = self
        next.apply(move)
        let king = next.kingIndex[us.rawValue]
        guard king >= 0, !next.isAttacked(index: king, by: us.opposite) else { return nil }
        return next
    }

    func legalMoves() -> [Move] {
        pseudoLegalMoves().filter { applyingIfLegal($0) != nil }
    }

    func legalMoves(from square: Square) -> [Move] {
        legalMoves().filter { $0.from == square }
    }

    // MARK: Understanding a move

    func isEnPassant(_ move: Move) -> Bool {
        guard let piece = board[move.from.index], piece.kind == .pawn else { return false }
        return move.from.file != move.to.file && board[move.to.index] == nil
    }

    func castleSide(of move: Move) -> CastleSide? {
        guard let piece = board[move.from.index], piece.kind == .king else { return nil }
        let distance = move.to.file - move.from.file
        if distance == 2 { return .kingside }
        if distance == -2 { return .queenside }
        return nil
    }

    /// The square of the piece `move` would capture, if any. For en passant
    /// this is not the destination square.
    func captureSquare(of move: Move) -> Square? {
        if board[move.to.index] != nil { return move.to }
        if isEnPassant(move) { return Square(file: move.to.file, rank: move.from.rank) }
        return nil
    }

    // MARK: Making a move

    /// Plays a pseudo-legal move. Legality is the caller's responsibility.
    mutating func apply(_ move: Move) {
        let from = move.from.index
        let to = move.to.index
        guard var piece = board[from] else { return }
        let color = piece.color
        var resetClock = piece.kind == .pawn || board[to] != nil

        if piece.kind == .pawn, from & 7 != to & 7, board[to] == nil {
            // En passant: the captured pawn stands beside the capturer.
            board[(from >> 3) * 8 + (to & 7)] = nil
            resetClock = true
        }
        if piece.kind == .king {
            let distance = (to & 7) - (from & 7)
            if distance == 2 {
                board[to - 1] = board[to + 1]
                board[to + 1] = nil
            } else if distance == -2 {
                board[to + 1] = board[to - 2]
                board[to - 2] = nil
            }
            kingIndex[color.rawValue] = to
        }
        if let captured = board[to], captured.kind == .king {
            kingIndex[captured.color.rawValue] = -1
        }
        if let promotion = move.promotion { piece.kind = promotion }
        board[to] = piece
        board[from] = nil

        // Any move from or to a king or rook home square ends that right.
        for s in [from, to] {
            switch s {
            case 4: castling.subtract([.whiteKingside, .whiteQueenside])
            case 60: castling.subtract([.blackKingside, .blackQueenside])
            case 0: castling.remove(.whiteQueenside)
            case 7: castling.remove(.whiteKingside)
            case 56: castling.remove(.blackQueenside)
            case 63: castling.remove(.blackKingside)
            default: break
            }
        }

        if piece.kind == .pawn, move.promotion == nil, abs(to - from) == 16 {
            enPassant = Square(index: (from + to) / 2)
        } else {
            enPassant = nil
        }
        halfmoveClock = resetClock ? 0 : halfmoveClock + 1
        if color == .black { fullmoveNumber += 1 }
        sideToMove = color.opposite
    }

    func applying(_ move: Move) -> ChessPosition {
        var next = self
        next.apply(move)
        return next
    }

    /// The same board with the other side to move. Used to answer "what could
    /// that piece do?" about a piece whose turn it is not.
    func withSideToMove(_ color: PieceColor) -> ChessPosition {
        guard color != sideToMove else { return self }
        var copy = self
        copy.sideToMove = color
        copy.enPassant = nil
        return copy
    }

    // MARK: Endings

    /// Neither side can ever give checkmate: bare kings, or one lone minor piece.
    var hasInsufficientMaterial: Bool {
        var minors = 0
        for piece in board {
            guard let piece else { continue }
            switch piece.kind {
            case .king: continue
            case .knight, .bishop: minors += 1
            case .pawn, .rook, .queen: return false
            }
        }
        return minors <= 1
    }

    /// The result this position forces on its own. Repetition and resignation
    /// need the game's history, so `ChessGame` adds those.
    func outcomeFromRules() -> ChessOutcome? {
        if legalMoves().isEmpty {
            return isCheck ? .checkmate(winner: sideToMove.opposite) : .draw(.stalemate)
        }
        if halfmoveClock >= 100 { return .draw(.fiftyMoves) }
        if hasInsufficientMaterial { return .draw(.insufficientMaterial) }
        return nil
    }

    /// True if the two positions count as "the same" for threefold repetition.
    func repeats(_ other: ChessPosition) -> Bool {
        sideToMove == other.sideToMove && castling == other.castling
            && enPassant == other.enPassant && board == other.board
    }

    // MARK: FEN

    /// Reads Forsyth–Edwards Notation, the standard one-line way to write a
    /// position. Only the board field is required.
    init?(fen: String) {
        let fields = fen.split(separator: " ").map(String.init)
        guard let placement = fields.first else { return nil }
        let rows = placement.split(separator: "/", omittingEmptySubsequences: false)
        guard rows.count == 8 else { return nil }

        var board = [Piece?](repeating: nil, count: 64)
        var kings = [-1, -1]
        for (rowIndex, row) in rows.enumerated() {
            let rank = 7 - rowIndex
            var file = 0
            for ch in row {
                if let skip = ch.wholeNumberValue {
                    file += skip
                } else if let kind = PieceKind(letter: ch) {
                    guard file < 8 else { return nil }
                    let color: PieceColor = ch.isUppercase ? .white : .black
                    board[rank * 8 + file] = Piece(color: color, kind: kind)
                    if kind == .king { kings[color.rawValue] = rank * 8 + file }
                    file += 1
                } else {
                    return nil
                }
            }
            guard file == 8 else { return nil }
        }

        self.board = board
        self.kingIndex = kings
        self.sideToMove = fields.count > 1 && fields[1] == "b" ? .black : .white

        var rights: CastlingRights = []
        if fields.count > 2 {
            for ch in fields[2] {
                switch ch {
                case "K": rights.insert(.whiteKingside)
                case "Q": rights.insert(.whiteQueenside)
                case "k": rights.insert(.blackKingside)
                case "q": rights.insert(.blackQueenside)
                default: break
                }
            }
        }
        self.castling = rights
        self.enPassant = fields.count > 3 ? Square(fields[3]) : nil
        self.halfmoveClock = fields.count > 4 ? Int(fields[4]) ?? 0 : 0
        self.fullmoveNumber = fields.count > 5 ? max(1, Int(fields[5]) ?? 1) : 1
    }

    var fen: String {
        var rows: [String] = []
        for rank in stride(from: 7, through: 0, by: -1) {
            var row = ""
            var empty = 0
            for file in 0..<8 {
                if let piece = board[rank * 8 + file] {
                    if empty > 0 { row += String(empty); empty = 0 }
                    let letter = String(piece.kind.letter)
                    row += piece.color == .white ? letter : letter.lowercased()
                } else {
                    empty += 1
                }
            }
            if empty > 0 { row += String(empty) }
            rows.append(row)
        }
        var rights = ""
        if castling.contains(.whiteKingside) { rights += "K" }
        if castling.contains(.whiteQueenside) { rights += "Q" }
        if castling.contains(.blackKingside) { rights += "k" }
        if castling.contains(.blackQueenside) { rights += "q" }
        if rights.isEmpty { rights = "-" }
        let side = sideToMove == .white ? "w" : "b"
        let ep = enPassant?.name ?? "-"
        return "\(rows.joined(separator: "/")) \(side) \(rights) \(ep) \(halfmoveClock) \(fullmoveNumber)"
    }
}
