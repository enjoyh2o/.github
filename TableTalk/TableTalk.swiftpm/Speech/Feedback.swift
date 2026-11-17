import AVFoundation
import UIKit

/// Short sounds and taps that say what kind of thing just happened, before
/// any words do. A capture, a check and a mistake each sound and feel
/// different, so the player knows the gist instantly.
///
/// The tones are generated in code — there are no audio files to ship.
/// While exploring the board by touch, each square also plays a tiny note:
/// further right on the board sounds further right in the headphones, and
/// higher up the board sounds higher in pitch.
@MainActor
final class Feedback {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)
    private var isWired = false

    private let impact = UIImpactFeedbackGenerator(style: .medium)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    private typealias Note = (frequency: Double, duration: Double)

    /// The earcon and haptic for a reply.
    func play(_ tone: Reply.Tone, settings: AppSettings) {
        if settings.hapticsEnabled {
            switch tone {
            case .info: break
            case .move: impact.impactOccurred()
            case .capture: impact.impactOccurred(intensity: 1.0)
            case .alert: notification.notificationOccurred(.warning)
            case .gameOver: notification.notificationOccurred(.success)
            case .question: selection.selectionChanged()
            case .error: notification.notificationOccurred(.error)
            }
        }
        guard settings.tonesEnabled else { return }
        switch tone {
        case .info: break
        case .move: play([(523, 0.07)])
        case .capture: play([(659, 0.06), (440, 0.09)])
        case .alert: play([(659, 0.08), (880, 0.12)])
        case .gameOver: play([(523, 0.1), (659, 0.1), (784, 0.18)])
        case .question: play([(440, 0.07), (554, 0.09)])
        case .error: play([(196, 0.16)])
        }
    }

    /// Played when the microphone opens and closes.
    func listening(started: Bool, settings: AppSettings) {
        if settings.hapticsEnabled { soft.impactOccurred() }
        guard settings.tonesEnabled else { return }
        play(started ? [(784, 0.06), (988, 0.08)] : [(988, 0.06), (784, 0.08)])
    }

    /// A positional note for one square of a board `columns` wide and `rows`
    /// tall. `column` and `row` count from the player's bottom-left.
    func square(column: Int, row: Int, columns: Int, rows: Int, occupied: Bool, settings: AppSettings) {
        if settings.hapticsEnabled {
            if occupied { impact.impactOccurred(intensity: 0.7) } else { selection.selectionChanged() }
        }
        guard settings.tonesEnabled else { return }
        let pan = columns > 1 ? Float(column) / Float(columns - 1) * 2 - 1 : 0
        // One whole-tone step per row, starting from the A below middle C.
        let frequency = 220 * pow(2, Double(row) * 2 / 12)
        play([(frequency, occupied ? 0.09 : 0.04)], pan: pan * 0.9, volume: occupied ? 0.5 : 0.25)
    }

    // MARK: Tone generation

    private func play(_ notes: [Note], pan: Float = 0, volume: Float = 0.4) {
        guard let format, let buffer = makeBuffer(notes, format: format, pan: pan, volume: volume) else { return }
        if !isWired {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            isWired = true
        }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func makeBuffer(_ notes: [Note], format: AVAudioFormat, pan: Float, volume: Float) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let total = notes.reduce(0) { $0 + Int($1.duration * sampleRate) }
        guard total > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)),
              let channels = buffer.floatChannelData
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(total)

        // Equal-power panning keeps the loudness steady from left to right.
        let angle = Double(max(-1, min(1, pan)) + 1) * Double.pi / 4
        let leftGain = Float(cos(angle)) * volume
        let rightGain = Float(sin(angle)) * volume

        var index = 0
        for note in notes {
            let count = Int(note.duration * sampleRate)
            for n in 0..<count {
                // A quick fade in and out stops each note from clicking.
                let fade = min(1.0, Double(n) / 220.0, Double(count - n) / 660.0)
                let sample = Float(sin(2 * Double.pi * note.frequency * Double(n) / sampleRate) * fade)
                channels[0][index] = sample * leftGain
                channels[1][index] = sample * rightGain
                index += 1
            }
        }
        return buffer
    }
}
