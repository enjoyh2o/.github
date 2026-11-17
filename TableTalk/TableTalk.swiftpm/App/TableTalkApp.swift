import AVFoundation
import SwiftUI

/// TableTalk: board games you can play by ear.
///
/// Everything in this app runs on the device — the game logic, the speech
/// recognition, the spoken replies and the language model. There is no
/// account, no server and no network use.
@main
struct TableTalkApp: App {
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView()
            }
            .environment(services)
        }
    }
}

/// The long-lived helpers every screen shares.
@MainActor
@Observable
final class AppServices {
    let settings = AppSettings()
    let narrator = Narrator()
    let feedback = Feedback()
    let voice = VoiceInput()

    init() {
        // One audio setup for the whole app: speak through the speaker and
        // allow the microphone, so nothing has to switch mid-conversation.
        try? AVAudioSession.sharedInstance().setCategory(
            .playAndRecord, mode: .default, options: [.defaultToSpeaker]
        )
    }
}

/// The screens the home page can open.
enum Route: Hashable {
    case chess
    case chessPractice
    case fourInARow
    case ticTacToe
    case settings
    case help
}
