import AVFoundation
import SwiftUI
import UIKit

/// Speaks the app's replies.
///
/// If VoiceOver is running, the words are handed to VoiceOver as
/// announcements, so the player hears them in the voice, speed and language
/// settings they already chose — and never two voices at once. Otherwise the
/// app speaks for itself with the system's on-device synthesizer.
@MainActor
@Observable
final class Narrator: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var isSpeaking = false
    /// Called when the app's own voice finishes everything it had to say.
    @ObservationIgnored var onFinished: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var announcementQueue: [String] = []
    @ObservationIgnored private var isAnnouncing = false
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var voice: AVSpeechSynthesisVoice?
    @ObservationIgnored private var announcementObserver: NSObjectProtocol?
    @ObservationIgnored private var notifiesWhenFinished = false

    override init() {
        super.init()
        synthesizer.delegate = self
        voice = Narrator.bestEnglishVoice()
        announcementObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.announcementDidFinishNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.announcementFinished() }
        }
    }

    /// Says `text`. With `interrupt`, anything still being said is cut off —
    /// right for answering the player. Without it, the words wait their turn —
    /// right for the computer's move arriving just after the player's own.
    /// `endsTurn` marks a reply the player may want to answer; only those
    /// trigger `onFinished` (a square read out under a finger does not).
    func say(_ text: String, settings: AppSettings, interrupt: Bool = true, endsTurn: Bool = false) {
        let spoken = SpeechFormatter.spoken(text, naming: settings.squareNaming)
        guard !spoken.isEmpty else { return }
        notifiesWhenFinished = endsTurn

        if UIAccessibility.isVoiceOverRunning {
            if interrupt {
                announcementQueue.removeAll()
                announce(spoken)
            } else if isAnnouncing {
                announcementQueue.append(spoken)
            } else {
                announce(spoken)
            }
            return
        }

        guard settings.speakReplies else { return }
        if interrupt { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: spoken)
        utterance.voice = voice
        utterance.rate = Float(settings.speechRate)
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        announcementQueue.removeAll()
    }

    // MARK: VoiceOver announcements

    private func announce(_ text: String) {
        isAnnouncing = true
        var announcement = AttributedString(text)
        announcement.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(announcement).post()

        // VoiceOver normally reports when it is done. If that report never
        // comes, move on after roughly the time the words would take.
        watchdog?.cancel()
        let seconds = 1.0 + Double(text.count) * 0.07
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.announcementFinished()
        }
    }

    private func announcementFinished() {
        watchdog?.cancel()
        isAnnouncing = false
        if !announcementQueue.isEmpty {
            announce(announcementQueue.removeFirst())
        }
    }

    // MARK: The app's own voice

    /// The best English voice already on the device, matching the player's
    /// region when it can. Nothing is downloaded.
    private static func bestEnglishVoice() -> AVSpeechSynthesisVoice? {
        let preferred = Locale.current.language.languageCode?.identifier == "en"
            ? Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
            : "en-US"
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        let regional = english.filter { $0.language == preferred }
        let pool = regional.isEmpty ? english.filter { $0.language == "en-US" } : regional
        return pool.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // Several utterances can be queued; only the last one ends the turn.
            guard !self.synthesizer.isSpeaking else { return }
            self.isSpeaking = false
            if self.notifiesWhenFinished { self.onFinished?() }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if !self.synthesizer.isSpeaking { self.isSpeaking = false }
        }
    }
}
