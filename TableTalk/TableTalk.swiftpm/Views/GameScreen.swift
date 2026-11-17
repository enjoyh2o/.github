import SwiftUI

/// Builds the table for a game once the shared services are available,
/// then shows the game screen.
struct GameHost<Session: GameSession, Board: View>: View {
    let make: () -> Session
    var configure: (GameTable<Session>) -> Void = { _ in }
    @ViewBuilder let board: (GameTable<Session>) -> Board

    @Environment(AppServices.self) private var services
    @State private var table: GameTable<Session>?

    var body: some View {
        Group {
            if let table {
                GameScreen(table: table) { board(table) }
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard table == nil else { return }
            let new = GameTable(
                session: make(),
                narrator: services.narrator,
                feedback: services.feedback,
                settings: services.settings
            )
            configure(new)
            table = new
        }
    }
}

/// The screen every game shares: the board, the conversation, and the ways
/// to speak or type. Only the board differs from game to game.
struct GameScreen<Session: GameSession, Board: View>: View {
    @Bindable var table: GameTable<Session>
    @ViewBuilder let board: () -> Board

    @Environment(AppServices.self) private var services
    @State private var showingHelp = false

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width > proxy.size.height
            Group {
                if isWide {
                    HStack(alignment: .top, spacing: 16) {
                        board().frame(maxWidth: proxy.size.height)
                        panel
                    }
                } else {
                    VStack(spacing: 12) {
                        board()
                        panel
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .navigationTitle(table.session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(isPresented: $showingHelp) {
            NavigationStack { HelpView(showsDone: true) }
        }
        .onAppear(perform: connect)
        .onDisappear(perform: disconnect)
        // VoiceOver's two-finger double tap: the quickest way to start and
        // stop talking without finding a button.
        .accessibilityAction(.magicTap) { toggleListening() }
    }

    // MARK: Conversation panel

    private var panel: some View {
        VStack(spacing: 10) {
            TranscriptView(
                lines: table.lines,
                isThinking: table.isThinking,
                naming: services.settings.squareNaming
            )
            SuggestionBar(suggestions: table.suggestions) { table.send($0) }
            inputBar
        }
    }

    private var inputBar: some View {
        let voice = services.voice
        return VStack(spacing: 8) {
            Button(action: toggleListening) {
                HStack(spacing: 12) {
                    Image(systemName: voice.isListening ? "waveform" : "mic.fill")
                    Text(speakButtonTitle)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(voice.isListening ? Color.red : Color.accentColor)
            .disabled(voice.state == .preparing)
            .accessibilityLabel(voice.isListening ? "Listening" : "Speak")
            .accessibilityHint(voice.isListening
                ? "Double tap when you have finished talking"
                : "Double tap, then say a move or ask a question")

            if case .unavailable(let reason) = voice.state {
                Label(reason, systemImage: "mic.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                TextField("Type a move or a question", text: $table.draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .submitLabel(.send)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { table.sendDraft() }
                Button {
                    table.sendDraft()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.largeTitle)
                }
                .disabled(table.draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Send")
            }
        }
    }

    private var speakButtonTitle: String {
        let voice = services.voice
        switch voice.state {
        case .listening: return voice.heard.isEmpty ? "Listening…" : voice.heard
        case .preparing: return "One moment…"
        case .idle, .unavailable: return "Speak"
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if services.narrator.isSpeaking {
                Button {
                    services.narrator.stop()
                } label: {
                    Label("Stop speaking", systemImage: "speaker.slash.fill")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { table.send("new game") } label: { Label("New game", systemImage: "plus.circle") }
                Button { table.send("undo") } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                Button { table.send("hint") } label: { Label("Hint", systemImage: "lightbulb") }
                Button { table.send("repeat") } label: { Label("Repeat", systemImage: "repeat") }
                Divider()
                Button { showingHelp = true } label: { Label("What can I say?", systemImage: "questionmark.circle") }
            } label: {
                Label("Game menu", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: Voice

    private func toggleListening() {
        let voice = services.voice
        if voice.isListening {
            voice.toggle()
            return
        }
        // Talking over the app is allowed: it stops to listen.
        services.narrator.stop()
        services.feedback.listening(started: true, settings: services.settings)
        voice.toggle()
    }

    private func connect() {
        let services = services
        let table = table
        services.voice.onSentence = { sentence in
            services.feedback.listening(started: false, settings: services.settings)
            table.send(sentence)
        }
        // Hands-free: once the app has finished speaking, listen again.
        services.narrator.onFinished = {
            guard services.settings.handsFree, services.voice.state == .idle,
                  !table.isOver, !table.isThinking else { return }
            services.feedback.listening(started: true, settings: services.settings)
            services.voice.toggle()
        }
        table.begin()
    }

    private func disconnect() {
        services.narrator.onFinished = nil
        services.voice.onSentence = nil
        services.narrator.stop()
        let voice = services.voice
        Task { await voice.stop(submit: false) }
    }
}

/// The conversation so far. Everything that is spoken is also written here,
/// so the app works for people who read rather than listen — including with
/// a braille display.
struct TranscriptView: View {
    let lines: [TranscriptLine]
    let isThinking: Bool
    let naming: SquareNaming

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(lines) { line in
                        row(for: line).id(line.id)
                    }
                    if isThinking {
                        Label("The computer is thinking…", systemImage: "hourglass")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .id(-1)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: lines.count) {
                guard let last = lines.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        .frame(minHeight: 80)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Conversation")
    }

    @ViewBuilder
    private func row(for line: TranscriptLine) -> some View {
        switch line.speaker {
        case .player:
            Text(line.text)
                .font(.title3)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel("You said: \(line.text)")
        case .table:
            Label {
                Text(line.text)
                    .font(.title3)
                    .textSelection(.enabled)
            } icon: {
                Image(systemName: line.tone.symbolName)
                    .foregroundStyle(line.tone == .alert || line.tone == .error ? Color.orange : Color.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(SpeechFormatter.spoken(line.text, naming: naming))
        }
    }
}

/// One-tap versions of things worth saying right now.
struct SuggestionBar: View {
    let suggestions: [String]
    let choose: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) { choose(suggestion) }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggestions")
    }
}
