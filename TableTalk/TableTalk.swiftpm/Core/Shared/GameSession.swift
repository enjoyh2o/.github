import Foundation

/// One thing the app says back to the player.
///
/// `text` is written for the eye ("Knight to f3"). The speech layer turns it
/// into something a synthesizer pronounces well ("Knight to F 3") — see
/// `SpeechFormatter`. Keeping one source of truth means the transcript on
/// screen, the VoiceOver announcement and the spoken audio can never disagree.
struct Reply: Equatable, Sendable {
    /// What kind of moment this is. Drives the earcon and the haptic.
    enum Tone: String, Sendable {
        case info       // an answer to a question
        case move       // a quiet move was played
        case capture    // something was taken
        case alert      // check, or a threat worth interrupting for
        case gameOver
        case question   // the app needs an answer ("Which knight?")
        case error      // the request could not be carried out
    }

    var text: String
    var tone: Tone = .info
    /// True when the board changed, so the UI knows to redraw and save.
    var boardChanged: Bool = false

    init(_ text: String, tone: Tone = .info, boardChanged: Bool = false) {
        self.text = text
        self.tone = tone
        self.boardChanged = boardChanged
    }
}

/// A game you can hold a conversation with.
///
/// Every game in TableTalk is driven the same way: plain language goes in,
/// a `Reply` comes out. Voice, typing, touch and VoiceOver actions all funnel
/// into `handle(_:)`, which is why they always behave identically.
protocol GameSession: AnyObject {
    /// A value-type picture of the board for the UI to draw.
    associatedtype Snapshot
    /// The computer's chosen move, in whatever form the game likes.
    associatedtype ComputerMove: Sendable

    var title: String { get }
    var snapshot: Snapshot { get }
    var isOver: Bool { get }

    /// Spoken when the game screen opens.
    func opening() -> Reply

    /// Handle one thing the player said, typed or tapped.
    func handle(_ input: String) -> Reply

    /// Phrases worth offering as one-tap buttons right now.
    var suggestions: [String] { get }

    /// If it is the computer's turn, returns a self-contained job that picks
    /// a move. The job captures only values, so it can run off the main thread.
    func computerMoveJob() -> (@Sendable () -> ComputerMove?)?

    /// Play the move the job came back with and describe it.
    func play(computerMove: ComputerMove) -> Reply

    /// True when the session's own parser cannot make sense of `input`.
    /// That is the cue for the app to ask the on-device language model to
    /// rephrase it. Simple games never need this, so it defaults to false.
    func needsInterpretation(_ input: String) -> Bool
}

extension GameSession {
    func needsInterpretation(_ input: String) -> Bool { false }
}

/// Who sits on the other side of the table.
enum Opponent: String, CaseIterable, Sendable, Identifiable {
    /// The device plays the other side.
    case computer
    /// Two people share one device and take turns.
    case person

    var id: String { rawValue }

    var title: String {
        switch self {
        case .computer: return "Play the computer"
        case .person: return "Two players, one device"
        }
    }
}

/// How strong the computer opponent plays. Shared by every game.
enum Difficulty: String, CaseIterable, Sendable, Identifiable {
    case gentle, steady, sharp
    var id: String { rawValue }

    var title: String {
        switch self {
        case .gentle: return "Gentle"
        case .steady: return "Steady"
        case .sharp: return "Sharp"
        }
    }

    var blurb: String {
        switch self {
        case .gentle: return "Makes friendly mistakes. Good for relaxing."
        case .steady: return "Plays sensibly without looking far ahead."
        case .sharp: return "Thinks a few moves ahead."
        }
    }
}
