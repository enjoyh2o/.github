import SwiftUI

/// The first screen: pick a game. Every control is large, plainly labelled
/// and reachable in one step.
struct HomeView: View {
    @Environment(AppServices.self) private var services
    @State private var hasWelcomed = false

    var body: some View {
        @Bindable var settings = services.settings

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Board games you can play by ear.")
                        .font(.title2.weight(.semibold))
                    Text("Say your move. Ask anything about the board, any time — you never have to hold it all in your head.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                GameCard(
                    title: "Chess",
                    detail: "A full game. Ask where pieces are, what is in danger, or what a piece can do.",
                    symbol: "crown.fill",
                    route: .chess
                )
                GameCard(
                    title: "Chess practice position",
                    detail: "Start in the middle of a game and try the questions straight away.",
                    symbol: "questionmark.bubble.fill",
                    route: .chessPractice
                )
                GameCard(
                    title: "Four in a Row",
                    detail: "Drop pieces into seven columns. First to line up four wins.",
                    symbol: "circle.grid.3x3.fill",
                    route: .fourInARow
                )
                GameCard(
                    title: "Tic-Tac-Toe",
                    detail: "A two-minute warm-up for playing by voice.",
                    symbol: "number",
                    route: .ticTacToe
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("How to play")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    Picker("Opponent", selection: $settings.opponent) {
                        ForEach(Opponent.allCases) { opponent in
                            Text(opponent.title).tag(opponent)
                        }
                    }
                    .pickerStyle(.segmented)

                    if settings.opponent == .computer {
                        Picker("Computer strength", selection: $settings.difficulty) {
                            ForEach(Difficulty.allCases) { difficulty in
                                Text(difficulty.title).tag(difficulty)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(settings.difficulty.blurb)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Toggle("Move first", isOn: $settings.playsWhite)
                    }
                }
                .padding()
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))

                HStack(spacing: 12) {
                    NavigationLink(value: Route.help) {
                        Label("What can I say?", systemImage: "questionmark.circle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    NavigationLink(value: Route.settings) {
                        Label("Settings", systemImage: "gearshape")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .buttonStyle(.bordered)
                .font(.headline)

                Label("Everything runs on this device. Nothing you say leaves it.", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("TableTalk")
        .navigationDestination(for: Route.self) { route in
            destination(for: route)
        }
        .onAppear(perform: welcome)
    }

    /// Greets people who are not using VoiceOver, once per launch. VoiceOver
    /// users hear the screen described by VoiceOver itself.
    private func welcome() {
        guard !hasWelcomed else { return }
        hasWelcomed = true
        guard !UIAccessibility.isVoiceOverRunning else { return }
        services.narrator.say(
            "Welcome to TableTalk: board games you can play by ear. Choose a game to begin.",
            settings: services.settings
        )
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        let settings = services.settings
        switch route {
        case .chess:
            GameHost(make: { () -> ChessSession in
                let session = ChessSession(
                    opponent: settings.opponent,
                    humanColor: settings.playsWhite ? .white : .black,
                    difficulty: settings.difficulty
                )
                session.announceThreats = settings.announceThreats
                session.detailedMoves = settings.detailedMoves
                return session
            }, configure: { table in HomeView.attachLanguageModel(to: table) }) { table in
                ChessBoardView(table: table)
            }
        case .chessPractice:
            GameHost(make: { () -> ChessSession in
                let session = ChessSession.practice(difficulty: settings.difficulty)
                session.announceThreats = settings.announceThreats
                session.detailedMoves = settings.detailedMoves
                return session
            }, configure: { table in HomeView.attachLanguageModel(to: table) }) { table in
                ChessBoardView(table: table)
            }
        case .fourInARow:
            GameHost(make: { () -> FourInARowSession in
                let session = FourInARowSession(
                    opponent: settings.opponent,
                    difficulty: settings.difficulty,
                    humanStarts: settings.playsWhite
                )
                session.announceThreats = settings.announceThreats
                return session
            }) { table in
                FourInARowBoardView(table: table)
            }
        case .ticTacToe:
            GameHost(make: { () -> TicTacToeSession in
                let session = TicTacToeSession(
                    opponent: settings.opponent,
                    difficulty: settings.difficulty,
                    humanStarts: settings.playsWhite
                )
                session.announceThreats = settings.announceThreats
                return session
            }) { table in
                TicTacToeBoardView(table: table)
            }
        case .settings:
            SettingsView()
        case .help:
            HelpView()
        }
    }

    /// Lets the on-device language model rescue chess sentences the built-in
    /// parser cannot read. The model only names the request; the session
    /// still produces the answer.
    private static func attachLanguageModel(to table: GameTable<ChessSession>) {
        table.interpreter = { [weak table] text in
            guard let table, let intent = await ChessInterpreter.interpret(text) else { return nil }
            return table.session.handle(interpreted: intent, heard: text)
        }
    }
}

/// A large, whole-card button for one game.
struct GameCard: View {
    let title: String
    let detail: String
    let symbol: String
    let route: Route

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.largeTitle)
                    .frame(width: 56)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.primary)
                    Text(detail)
                        .font(.body)
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color.secondary)
                    .accessibilityHidden(true)
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
