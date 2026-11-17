import SwiftUI

/// How pieces are drawn. Letters in bold type are easier for some people
/// with low vision than the traditional figurines.
enum PieceStyle: String, CaseIterable, Identifiable {
    case figures, letters
    var id: String { rawValue }
    var title: String { self == .figures ? "Chess figures" : "Large letters" }
}

/// Everything the player can adjust. Each value is saved the moment it changes.
@Observable
final class AppSettings {
    private let store = UserDefaults.standard

    // Speech out
    var speakReplies: Bool { didSet { store.set(speakReplies, forKey: "speakReplies") } }
    /// 0...1 on AVSpeechUtterance's scale; 0.5 is the system default.
    var speechRate: Double { didSet { store.set(speechRate, forKey: "speechRate") } }
    var squareNaming: SquareNaming { didSet { store.set(squareNaming.rawValue, forKey: "squareNaming") } }

    // Sound and touch
    var tonesEnabled: Bool { didSet { store.set(tonesEnabled, forKey: "tonesEnabled") } }
    var hapticsEnabled: Bool { didSet { store.set(hapticsEnabled, forKey: "hapticsEnabled") } }

    // Speech in
    /// Start listening again as soon as the app finishes speaking.
    var handsFree: Bool { didSet { store.set(handsFree, forKey: "handsFree") } }
    /// Let the on-device language model help with phrases the app's own
    /// parser does not recognise.
    var useLanguageModel: Bool { didSet { store.set(useLanguageModel, forKey: "useLanguageModel") } }

    // Play
    var opponent: Opponent { didSet { store.set(opponent.rawValue, forKey: "opponent") } }
    var difficulty: Difficulty { didSet { store.set(difficulty.rawValue, forKey: "difficulty") } }
    var playsWhite: Bool { didSet { store.set(playsWhite, forKey: "playsWhite") } }
    var announceThreats: Bool { didSet { store.set(announceThreats, forKey: "announceThreats") } }
    var detailedMoves: Bool { didSet { store.set(detailedMoves, forKey: "detailedMoves") } }

    // Display
    var boardTheme: BoardTheme { didSet { store.set(boardTheme.rawValue, forKey: "boardTheme") } }
    var pieceStyle: PieceStyle { didSet { store.set(pieceStyle.rawValue, forKey: "pieceStyle") } }

    init() {
        let store = UserDefaults.standard
        func flag(_ key: String, default value: Bool) -> Bool {
            store.object(forKey: key) == nil ? value : store.bool(forKey: key)
        }
        speakReplies = flag("speakReplies", default: true)
        speechRate = store.object(forKey: "speechRate") == nil ? 0.5 : store.double(forKey: "speechRate")
        squareNaming = SquareNaming(rawValue: store.string(forKey: "squareNaming") ?? "") ?? .letters
        tonesEnabled = flag("tonesEnabled", default: true)
        hapticsEnabled = flag("hapticsEnabled", default: true)
        handsFree = flag("handsFree", default: false)
        useLanguageModel = flag("useLanguageModel", default: true)
        opponent = Opponent(rawValue: store.string(forKey: "opponent") ?? "") ?? .computer
        difficulty = Difficulty(rawValue: store.string(forKey: "difficulty") ?? "") ?? .gentle
        playsWhite = flag("playsWhite", default: true)
        announceThreats = flag("announceThreats", default: true)
        detailedMoves = flag("detailedMoves", default: true)
        boardTheme = BoardTheme(rawValue: store.string(forKey: "boardTheme") ?? "") ?? .highContrast
        pieceStyle = PieceStyle(rawValue: store.string(forKey: "pieceStyle") ?? "") ?? .figures
    }
}
