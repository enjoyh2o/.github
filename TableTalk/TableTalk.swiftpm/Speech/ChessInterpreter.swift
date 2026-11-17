import Foundation
import FoundationModels

/// Uses the on-device Apple Intelligence language model to make sense of a
/// sentence the app's own parser could not.
///
/// The division of labour is strict, and it is the reason the app can be
/// trusted by someone who cannot check the board with their eyes:
///
///   * The model only *listens*. It maps free-form words onto a small, fixed
///     menu of requests — it never describes the position and never chooses
///     a move.
///   * The chess engine *answers*. Every fact that is spoken comes from the
///     rules engine, so the model cannot invent a piece or a square.
///   * A move the model thinks it heard is offered back as a question
///     ("Yes: knight from g1 to f3. Say yes to play it."), never played
///     outright.
///
/// The model runs entirely on the device. Where it is not available — older
/// hardware, Apple Intelligence switched off, or the model still preparing —
/// the app simply carries on with its built-in parser.
enum ChessInterpreter {

    @Generable(description: "What a chess player asked their chess app to do")
    struct Request {
        @Generable
        enum Action {
            case makeMove
            case findPieces
            case describeSquare
            case listMovesOfPiece
            case checkIfPieceIsSafe
            case listPiecesInDanger
            case listPossibleCaptures
            case describePosition
            case readWholeBoard
            case repeatLastMove
            case compareMaterial
            case giveHint
            case undoMove
            case explainCommands
            case notAboutTheGame
        }

        @Generable
        enum PieceName {
            case noPiece, king, queen, rook, bishop, knight, pawn
        }

        @Generable
        enum Side {
            case player, opponent, unspecified
        }

        @Guide(description: "The single best matching kind of request")
        var action: Action

        @Guide(description: "The chess piece the player mentioned, or none")
        var piece: PieceName

        @Guide(description: "Whose pieces the request is about")
        var side: Side

        @Guide(description: "The board square the request is about, a letter a to h then a digit 1 to 8, like e4. Empty if no square was mentioned. For a move, this is where the piece starts, if the player said so.")
        var square: String

        @Guide(description: "For a move only: the square the piece should go to, like f3. Otherwise empty.")
        var destination: String
    }

    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// Why the model cannot be used, in words for the Settings screen.
    static var statusText: String {
        let fallback = "TableTalk uses its built-in parser instead."
        switch SystemLanguageModel.default.availability {
        case .available:
            return "Ready. Runs on this device."
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "Not supported on this device. \(fallback)"
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence is turned off in Settings. \(fallback)"
            case .modelNotReady:
                return "The system is still preparing the model. \(fallback)"
            @unknown default:
                return "Not available right now. \(fallback)"
            }
        }
    }

    private static let instructions = """
        You convert what a chess player says into a structured request for a chess app. \
        The player may be blind and is speaking aloud, so speech recognition may have \
        misheard chess words: "night" or "Nate" means knight, "rock" means rook, \
        "pond" means pawn, "be five" means b5. \
        Never answer the question yourself and never suggest a move. Only classify what \
        was asked and copy out any piece and squares that were mentioned. \
        If the words are not about the chess game, choose notAboutTheGame.
        """

    /// Returns the request the model believes the player made, or nil if the
    /// model is unavailable, unsure, or the words are not about the game.
    static func interpret(_ text: String) async -> ChessIntent? {
        guard isAvailable else { return nil }
        do {
            // A fresh session per sentence: nothing carries over, so one odd
            // request cannot colour the next.
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: "The player said: \(text)",
                generating: Request.self,
                options: GenerationOptions(sampling: .greedy)
            )
            return intent(from: response.content)
        } catch {
            return nil
        }
    }

    /// Translates the model's structured output into the app's own intent
    /// type, discarding anything that is not a real square or piece.
    private static func intent(from request: Request) -> ChessIntent? {
        let kind: PieceKind?
        switch request.piece {
        case .noPiece: kind = nil
        case .king: kind = .king
        case .queen: kind = .queen
        case .rook: kind = .rook
        case .bishop: kind = .bishop
        case .knight: kind = .knight
        case .pawn: kind = .pawn
        }
        let side: SideRef?
        switch request.side {
        case .player: side = .mine
        case .opponent: side = .theirs
        case .unspecified: side = nil
        }
        let square = Square(request.square.trimmingCharacters(in: .whitespaces))
        let destination = Square(request.destination.trimmingCharacters(in: .whitespaces))

        switch request.action {
        case .makeMove:
            var move = MoveRequest(piece: kind)
            if let destination {
                move.from = square
                move.to = destination
            } else {
                move.to = square
            }
            // Offered back as a question, never played directly.
            return move.isEmpty ? nil : .canMove([move])
        case .findPieces:
            return .whereIs(kind, side)
        case .describeSquare:
            return square.map { .whatIsOn($0) }
        case .listMovesOfPiece:
            return square == nil && kind == nil ? nil : .movesFor(square, kind, side)
        case .checkIfPieceIsSafe:
            return square == nil && kind == nil ? .danger(side) : .safety(square, kind, side)
        case .listPiecesInDanger:
            return .danger(side)
        case .listPossibleCaptures:
            return .captures(side)
        case .describePosition:
            return .common(.summary)
        case .readWholeBoard:
            return .common(.readBoard)
        case .repeatLastMove:
            return .common(.lastMove)
        case .compareMaterial:
            return .material
        case .giveHint:
            return .common(.hint)
        case .undoMove:
            return .common(.undo)
        case .explainCommands:
            return .common(.help)
        case .notAboutTheGame:
            return nil
        }
    }
}
