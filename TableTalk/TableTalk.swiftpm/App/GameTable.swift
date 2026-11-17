import SwiftUI

/// One line of the on-screen conversation.
struct TranscriptLine: Identifiable, Equatable {
    enum Speaker { case player, table }
    let id: Int
    let speaker: Speaker
    let text: String
    let tone: Reply.Tone
}

/// The live table for one game: it owns the session and connects it to the
/// screen, the voice, the sounds and the computer opponent.
///
/// Whatever the player does — speak, type, tap a square, tap a suggestion,
/// use a VoiceOver action — ends up as a sentence passed to `send(_:)`.
/// One path in means every way of playing behaves the same.
@MainActor
@Observable
final class GameTable<Session: GameSession> {
    let session: Session
    private(set) var lines: [TranscriptLine] = []
    private(set) var isThinking = false
    /// What the player is typing.
    var draft = ""

    /// Bumped after every reply so views re-read the session.
    private var revision = 0
    /// Bumped whenever the board changes, to spot a computer move that was
    /// thought up for a position the player has since undone.
    @ObservationIgnored private var boardEpoch = 0
    @ObservationIgnored private var nextLineID = 0

    private let narrator: Narrator
    private let feedback: Feedback
    private let settings: AppSettings

    /// Optional second opinion for sentences the session cannot parse:
    /// the on-device language model. Returns nil when it cannot help.
    @ObservationIgnored var interpreter: ((String) async -> Reply?)?

    init(session: Session, narrator: Narrator, feedback: Feedback, settings: AppSettings) {
        self.session = session
        self.narrator = narrator
        self.feedback = feedback
        self.settings = settings
    }

    /// The board as it stands, for drawing.
    var snapshot: Session.Snapshot {
        _ = revision
        return session.snapshot
    }

    var suggestions: [String] {
        _ = revision
        return session.suggestions
    }

    var isOver: Bool {
        _ = revision
        return session.isOver
    }

    /// Greets the player and, if the computer moves first, lets it.
    func begin() {
        guard lines.isEmpty else { return }
        deliver(session.opening(), interrupt: true)
        Task { await letComputerMove() }
    }

    /// Handles something the player said, typed or tapped.
    /// - Parameter echo: show the player's words in the transcript. Board
    ///   taps pass false: the reply alone says what happened.
    func send(_ text: String, echo: Bool = true) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if echo { append(.player, trimmed, tone: .info) }
        Task { await process(trimmed) }
    }

    /// Sends whatever is in the text field.
    func sendDraft() {
        let text = draft
        draft = ""
        send(text)
    }

    /// Says something without adding it to the conversation — used while a
    /// finger explores the board, where every square speaks.
    func whisper(_ text: String) {
        narrator.say(text, settings: settings, interrupt: true)
    }

    private func process(_ text: String) async {
        var reply: Reply?
        if settings.useLanguageModel, let interpreter, session.needsInterpretation(text) {
            reply = await interpreter(text)
        }
        deliver(reply ?? session.handle(text), interrupt: true)
        await letComputerMove()
    }

    private func deliver(_ reply: Reply, interrupt: Bool) {
        revision += 1
        if reply.boardChanged { boardEpoch += 1 }
        guard !reply.text.isEmpty else { return }
        append(.table, reply.text, tone: reply.tone)
        feedback.play(reply.tone, settings: settings)
        narrator.say(reply.text, settings: settings, interrupt: interrupt)
    }

    private func append(_ speaker: TranscriptLine.Speaker, _ text: String, tone: Reply.Tone) {
        lines.append(TranscriptLine(id: nextLineID, speaker: speaker, text: text, tone: tone))
        nextLineID += 1
    }

    /// Runs the computer's turn off the main thread, then plays its move.
    private func letComputerMove() async {
        guard !isThinking, let job = session.computerMoveJob() else { return }
        isThinking = true
        let epoch = boardEpoch
        let move = await Task.detached(priority: .userInitiated) { job() }.value
        isThinking = false

        guard epoch == boardEpoch else {
            // The player took a move back or started over while the computer
            // was thinking. Its idea no longer applies; think again if needed.
            await letComputerMove()
            return
        }
        guard let move else { return }
        // Queued rather than interrupting, so the player's own move is
        // confirmed in full before the reply is read out.
        deliver(session.play(computerMove: move), interrupt: false)
    }
}
