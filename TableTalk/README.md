# TableTalk

Board games you can play by ear. Say your move. Ask anything about the board, any time.

TableTalk is an iOS app playground (`TableTalk.swiftpm`) built for blind and low-vision players, and for anyone who finds it tiring to hold a whole board in their head. It currently plays **Chess**, **Four in a Row** and **Tic-Tac-Toe**. Everything — game logic, speech recognition, speech output and the language model — runs on the device.

## The problem

The accessible chess that exists today is mostly "blind mode": the board is replaced by a text box, you type moves and short commands, and a screen reader reads back one line at a time. That works for strong players who can already picture all 64 squares. For everyone else it turns a relaxing game into a memory test.

TableTalk's starting point is different: **the player should never need to remember the board.** You can ask, in ordinary words, the things a sighted player would simply glance at:

| You say | TableTalk answers |
| --- | --- |
| "Where are my knights?" | "Your knights are on a3 and d2." |
| "What's in danger?" | "In danger: your knight on a3 is attacked by Black's pawn on b4." |
| "What can I take?" | "You can capture Black's pawn on c5 with the pawn on d4; nothing defends it." |
| "What can my knight on a3 do?" | "Your knight on a3 can go to b1, b5, c2 or c4." |
| "Is my queen safe?" | "Your queen on d1: it is not attacked. It is defended by your bishop on e2 and rook on f1." |
| "Knight to e5" (not possible) | "None of your knights can reach e5. Your knight on b1 can go to a3 or c3. …" |
| "Describe the position" | A five-sentence situation report: move number, turn, material, kings, dangers, chances. |

Those exact exchanges are unit tests (`Tests/CoreTests/ChessConversationTests.swift`).

## Design principles

1. **Ask anything, any time.** Questions never cost a turn and never change the board.
2. **The engine answers; the model only listens.** Every spoken fact comes from the rules engine. The on-device language model is used only to work out *what was asked* when the built-in parser is stumped, and a move it thinks it heard is offered back as a question, never played. A player who cannot check the board must be able to trust every word.
3. **Errors are directions.** A request that cannot be done says why and what is possible instead.
4. **No single way in.** Voice, typing, touch and VoiceOver all feed the same sentence handler, so they behave identically and any one of them is enough on its own.
5. **Forgive the microphone.** Speech recognisers were not trained on chess: "knight" arrives as "night" or "Nate", "b5" as "be five", "a4" as "84". The parser repairs these quietly.
6. **Say only what changed.** After the computer moves, TableTalk mentions a new threat or a possible recapture — one alert, not a board dump.
7. **Speak the user's way.** With VoiceOver on, replies go through VoiceOver (its voice, speed, braille). Squares are spoken unambiguously ("A 3", never "uh three"), optionally with the radio alphabet or the names FIDE suggests for games with blind players (Anna, Bella, Cesar, David, Eva, Felix, Gustav, Hector).

## Accessibility features

- **VoiceOver:** every square is a labelled button with state ("picked up", "can move here", "in check"); rotors for *My pieces*, *Opponent's pieces* and *Possible moves*; per-square actions to hear attackers/defenders or a piece's moves; Magic Tap (two-finger double tap) starts and stops listening.
- **Explore by touch (without VoiceOver):** slide a finger over the board and each square is spoken with a short note panned left-to-right and pitched low-to-high to match its position. A slow or sliding touch never moves a piece.
- **Low vision:** high-contrast board by default, outlined pieces, optional large-letter pieces, Dynamic Type throughout, marks that use shape as well as colour.
- **Everything spoken is also written** in a transcript, for people who read rather than listen (including on a braille display).
- **Earcons and haptics:** a move, a capture, a warning and a mistake each sound and feel different. Tones are synthesised in code; there are no audio assets.
- **Hands-free option:** listen again automatically after each reply.

## What runs on the device

| Job | Technology | Notes |
| --- | --- | --- |
| Speech to text | `SpeechAnalyzer` + `SpeechTranscriber`, falling back to `SFSpeechRecognizer` with `requiresOnDeviceRecognition` | Never falls back to server recognition. If neither is installed, typing and touch still work. |
| Understanding | A hand-written parser (`ChessLanguage`), then the Foundation Models framework (`LanguageModelSession` with guided generation) for sentences the parser cannot read | The model is optional. Without Apple Intelligence the app behaves the same, minus the rescue. |
| Answers | Pure-Swift rules engine and describer | Deterministic and unit-tested. |
| Opponent | Alpha-beta search with three strengths | Time-boxed so it stays responsive in debug builds. |
| Text to speech | `AVSpeechSynthesizer`, or VoiceOver announcements when VoiceOver is running | |

No network, no account, no analytics.

## Project layout

```
TableTalk/
├── TableTalk.swiftpm/        ← the app playground (this is the submission)
│   ├── Package.swift
│   ├── Core/                 ← pure Swift, no Apple-only frameworks
│   │   ├── Shared/           Reply, GameSession protocol, phrase helpers, speech formatting
│   │   ├── Chess/            rules, notation, describer, language parser, AI, session
│   │   ├── FourInARow/
│   │   └── TicTacToe/
│   ├── Speech/               Narrator, VoiceInput, Feedback (tones + haptics), ChessInterpreter
│   ├── App/                  app entry, settings, GameTable (view model)
│   └── Views/                SwiftUI screens and boards
├── Package.swift             ← development only: builds Core as a library for testing
└── Tests/CoreTests/          ← unit tests for Core
```

Every game implements one small protocol, `GameSession`: a sentence goes in, a `Reply` comes out. Adding a game means writing a session and a board view; speech, transcript, sounds and the computer-turn plumbing are shared.

## Running it

- **Xcode 27 or Swift Playground 4.7 or later:** open `TableTalk.swiftpm`. Minimum deployment target is iOS/iPadOS 26.
- **Tests** (macOS or Linux, any recent Swift toolchain), from this folder:

  ```
  swift test
  ```

  The chess move generator is validated against published perft counts (castling, en passant, promotion and pins all exercised).

## Status — read this before relying on it

- **Verified:** everything under `Core/` compiles and its unit tests pass (Swift 6.1 on Linux).
- **Not yet compiled:** `App/`, `Speech/` and `Views/` were written without access to Xcode — they pass a syntax check only. API signatures were checked against Apple's documentation, but expect a handful of compiler errors and some layout tuning the first time it is opened in Xcode. Voice input, the Foundation Models fallback, rotors and haptics need testing on a real device with VoiceOver.
- **Not yet tested with blind or low-vision players.** This matters more than anything above. The design follows published guidance and the conventions of blind chess, but only real users can say whether it works.

## Swift Student Challenge 2027

Checked against the [eligibility page](https://developer.apple.com/swift-student-challenge/eligibility/) and [terms](https://developer.apple.com/swift-student-challenge/policy/) (submissions 8–28 February 2027):

| Requirement | TableTalk |
| --- | --- |
| App playground or Xcode app, in a ZIP up to 500 MB | `TableTalk.swiftpm`, a few hundred KB, no bundled assets |
| Built with and runs on Xcode 27 / Swift Playground 4.7 or later | Targets iOS 26+; must be confirmed in Xcode 27 |
| Must not rely on a network; judged offline | No networking code. On-device Apple Intelligence frameworks are explicitly permitted by the terms |
| Experienced within three minutes | "Chess practice position" opens mid-game with one-tap suggested questions |
| Third-party content credited | See Credits |
| All content in English | Yes |
| Created by you as an individual | **See below** |

**Authorship — important.** The terms say the app "must be created entirely by you as an individual", that AI tools "may be used to assist with specific tasks of your project, provided that all usage is fully disclosed", and that entrants must "demonstrate significant individual contributions and technical understanding". This repository was drafted with substantial AI assistance. Submitting it as-is would not meet that bar. Treat it as a prototype and a reference: rebuild and extend it yourself, be able to explain every part, test it with real users, and disclose the AI assistance in your submission.

## Next steps

- Compile and fix in Xcode 27; test on device with VoiceOver, a braille display and Switch Control.
- Play-test with blind and low-vision players and older players; rewrite replies based on what they actually ask.
- Give `SpeechAnalyzer` chess vocabulary through `AnalysisContext.contextualStrings`.
- Save and resume games; chess clock; opening names; "explain that move".
- More games behind the same `GameSession` protocol: checkers, Reversi, Mancala, card games.
- Localisation, starting with the spoken square names.

## Credits

- Piece-square tables in `ChessAI.swift` are the "Simplified Evaluation Function" values published by Tomasz Michniewski on the Chess Programming Wiki. They give the computer opponent a basic sense of good squares.
- The alternative square names (Anna, Bella, Cesar, David, Eva, Felix, Gustav, Hector) are those suggested in the FIDE Laws of Chess for play with visually impaired players.
- Perft reference positions and counts are the standard ones from the Chess Programming Wiki.
