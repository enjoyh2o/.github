import SwiftUI

/// Examples of things to say. There is no command language to learn — these
/// are only starting points — but examples make the first minute easier.
struct HelpView: View {
    /// True when shown as a sheet, which needs its own way to close.
    var showsDone = false
    @Environment(\.dismiss) private var dismiss

    private struct Topic: Identifiable {
        let id: String
        let examples: [String]
    }

    private let topics: [Topic] = [
        Topic(id: "Three ways to play", examples: [
            "Press Speak and talk. With VoiceOver, a two-finger double tap starts and stops listening.",
            "Type in the box. The keyboard's dictation key works too.",
            "Touch the board: slide a finger to hear each square, tap a piece and then tap where it goes.",
        ]),
        Topic(id: "Making a chess move", examples: [
            "Knight to f3",
            "e4",
            "Pawn takes d5",
            "Take the bishop with my queen",
            "Castle kingside",
            "e8, promote to a knight",
        ]),
        Topic(id: "Finding your pieces", examples: [
            "Where are my knights?",
            "Where is the black queen?",
            "What pieces do I have left?",
            "What's on e4?",
            "Read rank 4",
            "Read the e file",
            "Read the board",
        ]),
        Topic(id: "Understanding the position", examples: [
            "Describe the position",
            "What's in danger?",
            "What can I take?",
            "What can my queen do?",
            "Is my rook safe?",
            "What is attacking e4?",
            "Can my knight take the bishop?",
            "Who's winning?",
            "Am I in check?",
        ]),
        Topic(id: "During any game", examples: [
            "What was the last move?",
            "Read the moves",
            "Whose turn is it?",
            "Hint",
            "Undo",
            "Repeat",
            "New game",
        ]),
        Topic(id: "Four in a Row", examples: [
            "Column 4",
            "Drop in the middle",
            "Read the board",
            "Read column 3",
            "Can anyone win?",
        ]),
        Topic(id: "Tic-Tac-Toe", examples: [
            "Top left",
            "Centre",
            "Five",
            "What's free?",
            "Can anyone win?",
        ]),
    ]

    var body: some View {
        List {
            ForEach(topics) { topic in
                Section(topic.id) {
                    ForEach(topic.examples, id: \.self) { example in
                        Text(example)
                            .font(.title3)
                    }
                }
            }
        }
        .navigationTitle("What can I say?")
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
