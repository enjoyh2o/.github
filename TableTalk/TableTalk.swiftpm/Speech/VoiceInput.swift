import AVFoundation
import Speech
import SwiftUI

/// Turns the player's voice into text — entirely on this device.
///
/// Two engines are supported and tried in order:
///   1. `SpeechAnalyzer` with `SpeechTranscriber`, Apple's current on-device
///      speech model, when its English model is already installed.
///   2. `SFSpeechRecognizer` with `requiresOnDeviceRecognition`, which is
///      available on more devices.
/// Neither path ever sends audio to a server. If neither is available the
/// app says so and everything still works by typing and by touch.
@MainActor
@Observable
final class VoiceInput {
    enum State: Equatable {
        case idle
        case preparing
        case listening
        /// Voice cannot be used right now; the text says why and what to do.
        case unavailable(String)
    }

    private(set) var state: State = .idle
    /// What has been heard so far in the current turn.
    private(set) var heard = ""

    /// Called once with the finished sentence when the player stops talking.
    @ObservationIgnored var onSentence: ((String) -> Void)?

    private let engine = AVAudioEngine()
    @ObservationIgnored private var transcription: Transcription?
    @ObservationIgnored private var silenceTimer: Task<Void, Never>?

    /// How long a pause ends the sentence.
    private let pauseToFinish = 1.4
    /// How long to wait for the first word before giving up.
    private let waitForSpeech = 7.0

    var isListening: Bool { state == .listening }

    func toggle() {
        switch state {
        case .listening:
            Task { await stop(submit: true) }
        case .preparing:
            break
        case .idle, .unavailable:
            Task { await start() }
        }
    }

    func start() async {
        guard state != .listening, state != .preparing else { return }
        state = .preparing
        heard = ""

        guard await AVAudioApplication.requestRecordPermission() else {
            state = .unavailable("The microphone is switched off for TableTalk. You can turn it on in Settings, or type your move instead.")
            return
        }

        let locale = VoiceInput.englishLocale()
        var chosen: Transcription? = await AnalyzerTranscription.make(locale: locale)
        if chosen == nil { chosen = await RecognizerTranscription.make(locale: locale) }
        guard let chosen else {
            state = .unavailable("On-device speech recognition for English is not set up on this device. You can type your move, or use the dictation key on the keyboard.")
            return
        }

        chosen.onText = { [weak self] text in
            Task { @MainActor in self?.received(text) }
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                state = .unavailable("No microphone was found. You can type your move instead.")
                return
            }
            try await chosen.start()
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
                chosen.append(buffer)
            }
            engine.prepare()
            try engine.start()
        } catch {
            chosen.cancel()
            engine.inputNode.removeTap(onBus: 0)
            state = .unavailable("The microphone could not be started. You can type your move instead.")
            return
        }

        transcription = chosen
        state = .listening
        restartSilenceTimer(after: waitForSpeech)
    }

    /// Stops listening. With `submit`, whatever was heard is delivered.
    func stop(submit: Bool) async {
        guard state == .listening else { return }
        state = .preparing
        silenceTimer?.cancel()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        if submit {
            await transcription?.finish()
        } else {
            transcription?.cancel()
        }
        // Let any last result that was already on its way arrive.
        await Task.yield()

        let sentence = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        transcription = nil
        heard = ""
        state = .idle
        if submit, !sentence.isEmpty { onSentence?(sentence) }
    }

    private func received(_ text: String) {
        guard state == .listening || state == .preparing else { return }
        guard text != heard else { return }
        heard = text
        if state == .listening { restartSilenceTimer(after: pauseToFinish) }
    }

    private func restartSilenceTimer(after seconds: Double) {
        silenceTimer?.cancel()
        silenceTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            // Stopping cancels this timer, so hand over to a fresh task
            // rather than cancelling the one that is doing the stopping.
            Task { @MainActor in await self?.stop(submit: true) }
        }
    }

    private static func englishLocale() -> Locale {
        Locale.current.language.languageCode?.identifier == "en" ? Locale.current : Locale(identifier: "en-US")
    }

    /// Words worth hinting to the recogniser so it expects chess talk.
    static let vocabulary = [
        "knight", "bishop", "rook", "queen", "king", "pawn", "castle", "kingside", "queenside",
        "takes", "check", "checkmate", "rank", "file", "undo", "hint", "column",
    ]
}

/// One way of turning microphone audio into text.
private protocol Transcription: AnyObject, Sendable {
    /// Called with the whole sentence so far, each time it changes.
    var onText: (@Sendable (String) -> Void)? { get set }
    func start() async throws
    /// Called on the audio thread with each chunk of microphone audio.
    func append(_ buffer: AVAudioPCMBuffer)
    /// No more audio is coming; wait briefly for the final words.
    func finish() async
    func cancel()
}

// MARK: - SpeechAnalyzer

private final class AnalyzerTranscription: Transcription, @unchecked Sendable {
    var onText: (@Sendable (String) -> Void)?

    private let transcriber: SpeechTranscriber
    private let analyzer: SpeechAnalyzer
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var results: Task<Void, Never>?
    private let lock = NSLock()
    private var isDone = false

    private init(transcriber: SpeechTranscriber) {
        self.transcriber = transcriber
        self.analyzer = SpeechAnalyzer(modules: [transcriber])
    }

    /// Returns a transcriber only if the device supports it and its speech
    /// model is already installed, so starting to listen never waits on a
    /// download. If the model is missing, a download is requested quietly in
    /// the background for next time (it simply fails when offline).
    static func make(locale: Locale) async -> AnalyzerTranscription? {
        guard SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        else { return nil }

        let transcriber = SpeechTranscriber(
            locale: supported,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        if await AssetInventory.status(forModules: [transcriber]) == .installed {
            return AnalyzerTranscription(transcriber: transcriber)
        }
        Task.detached(priority: .utility) {
            if let request = try? await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try? await request.downloadAndInstall()
            }
        }
        return nil
    }

    func start() async throws {
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw VoiceInputError.noAudioFormat
        }
        analyzerFormat = format
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        input = continuation

        let transcriber = transcriber
        results = Task { [weak self] in
            // Finished phrases are kept; the phrase still being spoken is
            // replaced each time the recogniser refines its guess.
            var finished = ""
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        finished += text
                        self?.onText?(finished)
                    } else {
                        self?.onText?(finished + text)
                    }
                }
            } catch {
                // The session ended; whatever was heard so far stands.
            }
            self?.markDone()
        }
        try await analyzer.start(inputSequence: stream)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let analyzerFormat, let converted = convert(buffer, to: analyzerFormat) else { return }
        input?.yield(AnalyzerInput(buffer: converted))
    }

    func finish() async {
        input?.finish()
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        await waitUntilDone(timeout: 2.0)
    }

    func cancel() {
        input?.finish()
        results?.cancel()
        let analyzer = analyzer
        Task { await analyzer.cancelAndFinishNow() }
    }

    private func markDone() {
        lock.withLock { isDone = true }
    }

    private func waitUntilDone(timeout: Double) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if lock.withLock({ isDone }) { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// The microphone's native format is rarely the one the speech model
    /// wants, so each chunk is resampled on the way in.
    private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
            converter?.primeMethod = .none
        }
        guard let converter else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var supplied = false
        var failure: NSError?
        let status = converter.convert(to: output, error: &failure) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        return status == .error ? nil : output
    }
}

// MARK: - SFSpeechRecognizer

private final class RecognizerTranscription: Transcription, @unchecked Sendable {
    var onText: (@Sendable (String) -> Void)?

    private let recognizer: SFSpeechRecognizer
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let lock = NSLock()
    private var isDone = false

    private init(recognizer: SFSpeechRecognizer) {
        self.recognizer = recognizer
    }

    /// Returns a recogniser only if it can work on the device. TableTalk
    /// never falls back to server-based recognition.
    static func make(locale: Locale) async -> RecognizerTranscription? {
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition
        else { return nil }
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { return nil }
        return RecognizerTranscription(recognizer: recognizer)
    }

    func start() async throws {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.contextualStrings = VoiceInput.vocabulary
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                self?.onText?(result.bestTranscription.formattedString)
            }
            if error != nil || result?.isFinal == true {
                self?.markDone()
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    func finish() async {
        request?.endAudio()
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            if lock.withLock({ isDone }) { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        task?.finish()
    }

    func cancel() {
        request?.endAudio()
        task?.cancel()
    }

    private func markDone() {
        lock.withLock { isDone = true }
    }
}

private enum VoiceInputError: Error {
    case noAudioFormat
}
