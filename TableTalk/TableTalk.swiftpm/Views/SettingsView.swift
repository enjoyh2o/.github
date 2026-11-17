import SwiftUI

struct SettingsView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var settings = services.settings

        Form {
            Section {
                Toggle("Speak replies aloud", isOn: $settings.speakReplies)
                VStack(alignment: .leading) {
                    Text("Speaking speed")
                    Slider(value: $settings.speechRate, in: 0.3...0.65, step: 0.05) {
                        Text("Speaking speed")
                    } minimumValueLabel: {
                        Image(systemName: "tortoise").accessibilityHidden(true)
                    } maximumValueLabel: {
                        Image(systemName: "hare").accessibilityHidden(true)
                    }
                    .accessibilityValue("\(Int((settings.speechRate * 200).rounded())) percent")
                }
                Picker("Say squares as", selection: $settings.squareNaming) {
                    ForEach(SquareNaming.allCases) { naming in
                        Text(naming.title).tag(naming)
                    }
                }
                Button("Hear a sample") {
                    services.narrator.say("Knight from g1 to f3. Your bishop is on a3.", settings: settings)
                }
            } header: {
                Text("Voice")
            } footer: {
                Text("When VoiceOver is on, TableTalk speaks through VoiceOver, using the voice and speed you chose there.")
            }

            Section {
                Toggle("Sounds", isOn: $settings.tonesEnabled)
                Toggle("Vibration", isOn: $settings.hapticsEnabled)
            } header: {
                Text("Sound and touch")
            } footer: {
                Text("Moves, captures, warnings and mistakes each have their own sound and feel. Sliding a finger over a board plays a note for each square: further right sounds further right, and higher up sounds higher.")
            }

            Section {
                Toggle("Keep listening after each reply", isOn: $settings.handsFree)
                Toggle("Use Apple Intelligence for unusual phrases", isOn: $settings.useLanguageModel)
                LabeledContent("On-device model", value: ChessInterpreter.statusText)
            } header: {
                Text("Listening")
            } footer: {
                Text("Speech is recognised on this device. The language model also runs on this device, and only helps work out what you asked — the answers always come from the game's own rules.")
            }

            Section {
                Toggle("Warn me when a piece comes under attack", isOn: $settings.announceThreats)
                Toggle("Say where a piece moved from", isOn: $settings.detailedMoves)
            } header: {
                Text("Announcements")
            }

            Section {
                Picker("Board colours", selection: $settings.boardTheme) {
                    ForEach(BoardTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                Picker("Chess pieces", selection: $settings.pieceStyle) {
                    ForEach(PieceStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
            } header: {
                Text("Display")
            }

            Section {
                Text("TableTalk works without an internet connection. It has no account and collects nothing. Your voice, your games and your questions stay on this device.")
            } header: {
                Text("Privacy")
            }
        }
        .navigationTitle("Settings")
    }
}
