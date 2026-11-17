import Foundation

/// A move that was actually played, with everything needed to describe it
/// later without replaying the game.
struct PlayedMove: Equatable, Sendable {
    let move: Move
    let piece: Piece
    let captured: Piece?
    let isEnPassant: Bool
    let castle: CastleSide?
    let givesCheck: Bool
    let isCheckmate: Bool
    /// Standard written notation, e.g. "Nf3" or "exd5+".
    let notation: String
    /// Which full move this belongs to (White and Black share a number).
    let moveNumber: Int

    var color: PieceColor { piece.color }
}

/// A game in progress: the current position plus how we got here.
struct ChessGame: Sendable {
    private(set) var position: ChessPosition
    private(set) var history: [PlayedMove] = []
    /// The position before each move in `history`, for undo and repetition.
    private var earlier: [ChessPosition] = []
    private(set) var resignedBy: PieceColor?

    init(position: ChessPosition = .start) {
        self.position = position
    }

    var lastMove: PlayedMove? { history.last }

    /// How the game ended, or nil while it is still going.
    var outcome: ChessOutcome? {
        if let resignedBy { return .resignation(winner: resignedBy.opposite) }
        if let natural = position.outcomeFromRules() { return natural }
        let repeats = earlier.reduce(1) { $0 + ($1.repeats(position) ? 1 : 0) }
        return repeats >= 3 ? .draw(.repetition) : nil
    }

    /// Plays `move`, which must be one of `position.legalMoves()`.
    @discardableResult
    mutating func play(_ move: Move) -> PlayedMove {
        let before = position
        let legal = before.legalMoves()
        precondition(legal.contains(move), "illegal move \(move.coordinates)")

        let piece = before[move.from]!
        let captureSquare = before.captureSquare(of: move)
        let captured = captureSquare.flatMap { before[$0] }
        var notation = ChessNotation.write(move, in: before, legal: legal)

        position.apply(move)
        let givesCheck = position.isCheck
        let isMate = givesCheck && position.legalMoves().isEmpty
        if isMate { notation += "#" } else if givesCheck { notation += "+" }

        let played = PlayedMove(
            move: move,
            piece: piece,
            captured: captured,
            isEnPassant: before.isEnPassant(move),
            castle: before.castleSide(of: move),
            givesCheck: givesCheck,
            isCheckmate: isMate,
            notation: notation,
            moveNumber: before.fullmoveNumber
        )
        earlier.append(before)
        history.append(played)
        return played
    }

    /// Takes back the last move and returns it, or nil if there is none.
    @discardableResult
    mutating func undo() -> PlayedMove? {
        guard let last = history.popLast(), let before = earlier.popLast() else { return nil }
        position = before
        resignedBy = nil
        return last
    }

    mutating func resign(_ color: PieceColor) {
        resignedBy = color
    }
}

/// Reading and writing standard algebraic notation.
enum ChessNotation {

    /// Writes `move` the way a scoresheet would, without the check mark.
    static func write(_ move: Move, in position: ChessPosition, legal: [Move]) -> String {
        guard let piece = position[move.from] else { return move.coordinates }
        if let side = position.castleSide(of: move) {
            return side == .kingside ? "O-O" : "O-O-O"
        }
        let isCapture = position.captureSquare(of: move) != nil
        var out = ""

        if piece.kind == .pawn {
            if isCapture { out.append(Square.fileLetter(move.from.file)) }
        } else {
            out.append(piece.kind.letter)
            // If another piece of the same kind could also get there, say which.
            let rivals = legal.filter {
                $0.to == move.to && $0.from != move.from && position[$0.from]?.kind == piece.kind
            }
            if !rivals.isEmpty {
                let sharesFile = rivals.contains { $0.from.file == move.from.file }
                let sharesRank = rivals.contains { $0.from.rank == move.from.rank }
                if !sharesFile {
                    out.append(Square.fileLetter(move.from.file))
                } else if !sharesRank {
                    out += String(move.from.rank + 1)
                } else {
                    out += move.from.name
                }
            }
        }
        if isCapture { out += "x" }
        out += move.to.name
        if let promotion = move.promotion {
            out += "="
            out.append(promotion.letter)
        }
        return out
    }
}
