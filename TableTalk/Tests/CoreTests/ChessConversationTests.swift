import XCTest
@testable import TableTalkCore

final class ChessLanguageTests: XCTestCase {

    private func sq(_ name: String) -> Square { Square(name)! }

    private func moveRequest(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> MoveRequest {
        guard case .move(let requests) = ChessLanguage.parse(text), let first = requests.first else {
            XCTFail("\"\(text)\" was not read as a move: \(ChessLanguage.parse(text))", file: file, line: line)
            return MoveRequest()
        }
        return first
    }

    func testWrittenNotation() {
        XCTAssertEqual(moveRequest("Nf3"), MoveRequest(piece: .knight, to: sq("f3")))
        XCTAssertEqual(moveRequest("nf3"), MoveRequest(piece: .knight, to: sq("f3")))
        XCTAssertEqual(moveRequest("e4"), MoveRequest(to: sq("e4")))
        XCTAssertEqual(moveRequest("exd5"), MoveRequest(piece: .pawn, fromFile: 4, to: sq("d5"), capture: true))
        XCTAssertEqual(moveRequest("Nbd2"), MoveRequest(piece: .knight, fromFile: 1, to: sq("d2")))
        XCTAssertEqual(moveRequest("R1e2"), MoveRequest(piece: .rook, fromRank: 0, to: sq("e2")))
        XCTAssertEqual(moveRequest("e2e4"), MoveRequest(from: sq("e2"), to: sq("e4")))
        XCTAssertEqual(moveRequest("e7e8q"), MoveRequest(from: sq("e7"), to: sq("e8"), promotion: .queen))
        XCTAssertEqual(moveRequest("e8=N"), MoveRequest(to: sq("e8"), promotion: .knight))
        XCTAssertEqual(moveRequest("Qxd5+"), MoveRequest(piece: .queen, to: sq("d5"), capture: true))
        XCTAssertEqual(moveRequest("O-O"), MoveRequest(castle: .kingside))
        XCTAssertEqual(moveRequest("0-0-0"), MoveRequest(castle: .queenside))
        XCTAssertEqual(moveRequest("play Nf3"), MoveRequest(piece: .knight, to: sq("f3")))
        // Lower-case "bc4" could be the b-pawn or a bishop; both readings are kept.
        guard case .move(let both) = ChessLanguage.parse("bc4") else { return XCTFail() }
        XCTAssertEqual(both.map(\.piece), [.pawn, .bishop])
    }

    func testSpokenMoves() {
        XCTAssertEqual(moveRequest("knight to f3"), MoveRequest(piece: .knight, to: sq("f3")))
        XCTAssertEqual(moveRequest("Knight to F3."), MoveRequest(piece: .knight, to: sq("f3")))
        XCTAssertEqual(moveRequest("pawn takes d5"), MoveRequest(piece: .pawn, to: sq("d5"), capture: true))
        XCTAssertEqual(moveRequest("e2 to e4"), MoveRequest(from: sq("e2"), to: sq("e4")))
        XCTAssertEqual(moveRequest("move the knight from g1 to f3"),
                       MoveRequest(piece: .knight, from: sq("g1"), to: sq("f3")))
        XCTAssertEqual(moveRequest("knight on f3 takes pawn on e5"),
                       MoveRequest(piece: .knight, from: sq("f3"), to: sq("e5"), capture: true, target: .pawn))
        XCTAssertEqual(moveRequest("take the bishop with my queen"),
                       MoveRequest(piece: .queen, capture: true, target: .bishop))
        XCTAssertEqual(moveRequest("bishop takes knight"),
                       MoveRequest(piece: .bishop, capture: true, target: .knight))
        XCTAssertEqual(moveRequest("e7 to e8 promote to a knight"),
                       MoveRequest(from: sq("e7"), to: sq("e8"), promotion: .knight))
        XCTAssertEqual(moveRequest("pawn to e8 queen"), MoveRequest(piece: .pawn, to: sq("e8"), promotion: .queen))
        XCTAssertEqual(moveRequest("the c pawn takes"), MoveRequest(piece: .pawn, fromFile: 2, capture: true))
        XCTAssertEqual(moveRequest("move a pawn to e4"), MoveRequest(piece: .pawn, to: sq("e4")))
        XCTAssertEqual(moveRequest("castle kingside"), MoveRequest(castle: .kingside))
        XCTAssertEqual(moveRequest("castle queen side"), MoveRequest(castle: .queenside))
        XCTAssertEqual(moveRequest("long castle"), MoveRequest(castle: .queenside))
        XCTAssertEqual(moveRequest("castle"), MoveRequest(castle: .either))
    }

    /// What a speech recogniser really hands over for chess talk.
    func testMisheardSpeechIsRepaired() {
        XCTAssertEqual(moveRequest("night to F3"), MoveRequest(piece: .knight, to: sq("f3")))
        XCTAssertEqual(moveRequest("Nate f 3"), MoveRequest(piece: .knight, to: sq("f3")))
        XCTAssertEqual(moveRequest("E 4"), MoveRequest(to: sq("e4")))
        XCTAssertEqual(moveRequest("echo four"), MoveRequest(to: sq("e4")))
        XCTAssertEqual(moveRequest("bishop to be five"), MoveRequest(piece: .bishop, to: sq("b5")))
        XCTAssertEqual(moveRequest("bishop to before"), MoveRequest(piece: .bishop, to: sq("b4")))
        XCTAssertEqual(moveRequest("rock to a one"), MoveRequest(piece: .rook, to: sq("a1")))
        XCTAssertEqual(moveRequest("pond to see for"), MoveRequest(piece: .pawn, to: sq("c4")))
        XCTAssertEqual(moveRequest("84"), MoveRequest(to: sq("a4")))
        XCTAssertEqual(moveRequest("e to e 4"), MoveRequest(from: sq("e2"), to: sq("e4")))
        XCTAssertEqual(moveRequest("queen to delta 8"), MoveRequest(piece: .queen, to: sq("d8")))
        XCTAssertEqual(moveRequest("knight to Felix 3"), MoveRequest(piece: .knight, to: sq("f3")))
        XCTAssertEqual(ChessLanguage.parse("where are my nates"), .whereIs(.knight, .mine))
    }

    func testQuestions() {
        XCTAssertEqual(ChessLanguage.parse("Where are my knights?"), .whereIs(.knight, .mine))
        XCTAssertEqual(ChessLanguage.parse("where are black's bishops"), .whereIs(.bishop, .black))
        XCTAssertEqual(ChessLanguage.parse("where is the queen"), .whereIs(.queen, nil))
        XCTAssertEqual(ChessLanguage.parse("do I have any rooks left"), .whereIs(.rook, .mine))
        XCTAssertEqual(ChessLanguage.parse("what pieces does the computer have"), .whereIs(nil, .theirs))
        XCTAssertEqual(ChessLanguage.parse("what's on e4"), .whatIsOn(sq("e4")))
        XCTAssertEqual(ChessLanguage.parse("e4?"), .whatIsOn(sq("e4")))
        XCTAssertEqual(ChessLanguage.parse("is there anything on a 3"), .whatIsOn(sq("a3")))
        XCTAssertEqual(ChessLanguage.parse("what can my knight on d2 do"), .movesFor(sq("d2"), .knight, .mine))
        XCTAssertEqual(ChessLanguage.parse("where can my queen go"), .movesFor(nil, .queen, .mine))
        XCTAssertEqual(ChessLanguage.parse("moves for g1"), .movesFor(sq("g1"), nil, nil))
        XCTAssertEqual(ChessLanguage.parse("is my queen safe"), .safety(nil, .queen, .mine))
        XCTAssertEqual(ChessLanguage.parse("what is attacking e4"), .safety(sq("e4"), nil, nil))
        XCTAssertEqual(ChessLanguage.parse("what's attacking my rook"), .safety(nil, .rook, .mine))
        XCTAssertEqual(ChessLanguage.parse("is the bishop attacking my queen"), .safety(nil, .queen, .mine))
        XCTAssertEqual(ChessLanguage.parse("what is my bishop attacking"), .movesFor(nil, .bishop, .mine))
        XCTAssertEqual(ChessLanguage.parse("what's in danger"), .danger(nil))
        XCTAssertEqual(ChessLanguage.parse("is anything of mine hanging"), .danger(.mine))
        XCTAssertEqual(ChessLanguage.parse("what can I take"), .captures(.mine))
        XCTAssertEqual(ChessLanguage.parse("can I capture anything"), .captures(.mine))
        XCTAssertEqual(ChessLanguage.parse("read rank 4"), .readRank(3))
        XCTAssertEqual(ChessLanguage.parse("read the fourth rank"), .readRank(3))
        XCTAssertEqual(ChessLanguage.parse("read the e file"), .readFile(4))
        XCTAssertEqual(ChessLanguage.parse("what's on the a file"), .readFile(0))
        XCTAssertEqual(ChessLanguage.parse("am I in check"), .check)
        XCTAssertEqual(ChessLanguage.parse("who's winning"), .material)
        XCTAssertEqual(ChessLanguage.parse("I resign"), .resign)
        XCTAssertEqual(ChessLanguage.parse("describe the position"), .common(.summary))
        XCTAssertEqual(ChessLanguage.parse("what did black play"), .common(.lastMove))
        XCTAssertEqual(ChessLanguage.parse("take that back"), .common(.undo))
        XCTAssertEqual(ChessLanguage.parse("what should I do"), .common(.hint))
        XCTAssertEqual(ChessLanguage.parse("tell me a joke"), .unknown)
    }

    func testQuestionsNeverPlayAMove() {
        guard case .canMove = ChessLanguage.parse("can my knight take the bishop?") else { return XCTFail() }
        guard case .canMove = ChessLanguage.parse("can I castle") else { return XCTFail() }
        guard case .canMove = ChessLanguage.parse("what about knight to f3?") else { return XCTFail() }
    }
}

final class ChessSessionTests: XCTestCase {

    private func session(_ fen: String, opponent: Opponent = .computer, human: PieceColor = .white) -> ChessSession {
        ChessSession(opponent: opponent, humanColor: human, position: ChessPosition(fen: fen)!)
    }

    /// The exact scenario the app was imagined for.
    func testPracticePositionAnswersTheMotivatingQuestions() {
        let s = ChessSession.practice()
        XCTAssertEqual(s.handle("Where are my knights?").text, "Your knights are on a3 and d2.")
        XCTAssertEqual(s.handle("where are my nates").text, "Your knights are on a3 and d2.")
        XCTAssertEqual(s.handle("what's in danger?").text,
                       "In danger: your knight on a3 is attacked by Black's pawn on b4.")
        XCTAssertEqual(s.handle("what can my knight on a3 do").text,
                       "Your knight on a3 can go to b1, b5, c2 or c4.")
        XCTAssertEqual(s.handle("what can I take?").text,
                       "You can capture Black's pawn on b4 with the pawn on c3; it is defended. "
                       + "You can capture Black's pawn on c5 with the pawn on d4; nothing defends it.")
        XCTAssertEqual(s.handle("what's on b4").text,
                       "Black's pawn is on b4. It is attacked by your pawn on c3, and it is defended by Black's pawn on c5 and knight on c6.")
        XCTAssertEqual(s.handle("what's on h4").text, "h4 is empty. Nothing attacks it.")
        XCTAssertEqual(s.handle("is my queen safe").text,
                       "Your queen on d1: it is not attacked. It is defended by your bishop on e2 and rook on f1.")
        XCTAssertEqual(s.handle("where is black's queen").text, "Black's queen is on d8.")
        XCTAssertEqual(s.handle("read rank 4").text,
                       "Rank 4, from a to h: Black's pawn on b4 and your pawn on d4. The other squares are empty.")
        XCTAssertEqual(s.handle("who's winning").text, "Material is even, 39 points each.")
        XCTAssertEqual(s.handle("am I in check").text, "No one is in check.")
    }

    func testReadTheWholeBoard() {
        let s = ChessSession()
        XCTAssertEqual(
            s.handle("read the board").text,
            "Your pieces: king on e1; queen on d1; rooks on a1 and h1; bishops on c1 and f1; knights on b1 and g1; "
            + "pawns on a2, b2, c2, d2, e2, f2, g2 and h2. "
            + "Black's pieces: king on e8; queen on d8; rooks on a8 and h8; bishops on c8 and f8; knights on b8 and g8; "
            + "pawns on a7, b7, c7, d7, e7, f7, g7 and h7."
        )
    }

    func testPlayingAgainstTheComputer() throws {
        let s = ChessSession()
        XCTAssertNil(s.computerMoveJob(), "it is the person's move first")
        let mine = s.handle("e4")
        XCTAssertEqual(mine.text, "You played pawn to e4.")
        XCTAssertEqual(mine.tone, .move)
        XCTAssertTrue(mine.boardChanged)

        // While the computer thinks, questions work but moves wait.
        XCTAssertEqual(s.handle("d4").tone, .error)
        XCTAssertEqual(s.handle("where is my king").text, "Your king is on e1.")

        let job = try XCTUnwrap(s.computerMoveJob())
        let move = try XCTUnwrap(job())
        let reply = s.play(computerMove: move)
        XCTAssertTrue(reply.text.hasPrefix("Black played "), reply.text)
        XCTAssertNil(s.computerMoveJob())
        XCTAssertEqual(s.snapshot.notation.count, 2)
    }

    func testAmbiguousMoveAsksWhichPiece() {
        let s = session("4k3/8/8/8/8/1N3N2/8/4K3 w - - 0 1")
        let question = s.handle("knight to d2")
        XCTAssertEqual(question.tone, .question)
        XCTAssertEqual(question.text, "Which knight? The one on b3 or the one on f3?")
        XCTAssertEqual(s.suggestions, ["b3", "f3", "Never mind"])
        XCTAssertEqual(s.handle("the one on b3").text, "You played knight from b3 to d2.")
    }

    func testAmbiguityCanBeAbandonedForAnotherRequest() {
        let s = session("4k3/8/8/8/8/1N3N2/8/4K3 w - - 0 1")
        _ = s.handle("knight to d2")
        XCTAssertEqual(s.handle("where is my king").text, "Your king is on e1.")
        // The earlier question is gone; "b3" alone is now just a square.
        XCTAssertEqual(s.handle("yes").tone, .info)
    }

    func testNamingOnlyAPieceAsksWhereTo() {
        let s = ChessSession()
        let reply = s.handle("the knight on g1")
        XCTAssertEqual(reply.text, "Where to? Your knight on g1 can go to f3 or h3.")
        XCTAssertEqual(s.handle("h3").text, "You played knight from g1 to h3.")
    }

    func testVagueWordsNeverPlayAMoveOnTheirOwn() {
        // Only one rook move exists, but "move my rook" did not say where.
        let s = session("4k3/8/8/8/8/8/P7/R1K5 w - - 0 1")
        let reply = s.handle("I want to move my rook")
        XCTAssertEqual(reply.text, "That can only be rook from a1 to b1. Say yes to play it.")
        XCTAssertEqual(reply.tone, .question)
        XCTAssertEqual(s.snapshot.notation, [])
        XCTAssertEqual(s.handle("no").text, "Okay, no move made.")
    }

    func testCastlingIsAnnouncedNaturally() {
        let s = session("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", opponent: .person)
        XCTAssertEqual(s.handle("castle").text, "Castle kingside or queenside?")
        XCTAssertEqual(s.suggestions, ["Kingside", "Queenside", "Never mind"])
        XCTAssertEqual(s.handle("king side").text, "White castled kingside. Black to move.")
        XCTAssertEqual(s.handle("castle long").text, "Black castled queenside. White to move.")
        XCTAssertEqual(s.handle("what changed").text, "Black's last move was castling queenside.")
    }

    func testErrorsExplainWhatIsPossible() {
        let s = ChessSession()
        XCTAssertEqual(s.handle("knight to e5").text,
                       "None of your knights can reach e5. Your knight on b1 can go to a3 or c3. "
                       + "Your knight on g1 can go to f3 or h3.")
        XCTAssertEqual(s.handle("e2 to e5").text, "Your pawn on e2 can't go to e5. Your pawn on e2 can go to e3 or e4.")
        XCTAssertEqual(s.handle("e7 to e5").text, "The piece on e7 is Black's pawn on e7, not yours.")
        XCTAssertEqual(s.handle("e4 to e5").text, "There is no piece on e4.")
        XCTAssertEqual(s.handle("castle").text,
                       "You can't castle that way right now: there are pieces in between, the king would cross an attacked square, or that rook has moved.")
        XCTAssertEqual(s.handle("can I castle?").tone, .info)
    }

    func testPinnedPieceIsExplained() {
        // The knight on e2 shields the king from the rook on e8.
        let s = session("4r1k1/8/8/8/8/8/4N3/4K3 w - - 0 1")
        XCTAssertEqual(s.handle("knight to c3").text, "That piece is pinned: moving it would expose your king.")
    }

    func testAskingFirstThenConfirming() {
        let s = session("4k3/7p/8/4b3/8/5N2/7P/4K3 w - - 0 1")
        let answer = s.handle("can my knight take the bishop?")
        XCTAssertEqual(answer.text, "Yes: knight on f3 takes bishop on e5. Say yes to play it.")
        XCTAssertEqual(s.snapshot.notation, [], "asking must not move anything")
        XCTAssertEqual(s.handle("yes").text, "You played knight on f3 takes bishop on e5.")
    }

    func testHintThenYesPlaysIt() {
        let s = session("6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1")
        let hint = s.handle("hint")
        XCTAssertEqual(hint.text, "Try rook from a1 to a8, which is checkmate. Say yes to play it.")
        let reply = s.handle("yes")
        XCTAssertEqual(reply.text, "You played rook from a1 to a8. Checkmate. You win.")
        XCTAssertEqual(reply.tone, .gameOver)
        XCTAssertTrue(s.isOver)
        XCTAssertEqual(s.handle("e4").tone, .error)
    }

    func testComputerMoveWarnsAboutNewThreats() {
        let s = session("4k3/8/8/3p4/8/2N5/8/4K3 b - - 0 1")
        let reply = s.play(computerMove: Move(from: Square("d5")!, to: Square("d4")!))
        XCTAssertEqual(reply.text, "Black played pawn to d4. Careful: your knight on c3 is attacked by Black's pawn on d4 and has no defender.")
        XCTAssertEqual(reply.tone, .alert)

        s.announceThreats = false
        XCTAssertEqual(s.handle("undo").text, "Took back Black's pawn to d4. Black, the computer, is thinking.")
        let quiet = s.play(computerMove: Move(from: Square("d5")!, to: Square("d4")!))
        XCTAssertEqual(quiet.text, "Black played pawn to d4.")
    }

    func testComputerCaptureMentionsRecapture() {
        let s = session("4k3/8/8/3b4/4P3/8/8/K3R3 b - - 0 1")
        let reply = s.play(computerMove: Move(from: Square("d5")!, to: Square("e4")!))
        XCTAssertEqual(reply.text, "Black played bishop on d5 takes pawn on e4. You can take back on e4.")
        XCTAssertEqual(reply.tone, .capture)
    }

    func testUndoAgainstTheComputerReturnsTheTurn() throws {
        let s = ChessSession()
        _ = s.handle("e4")
        _ = s.play(computerMove: Move(from: Square("e7")!, to: Square("e5")!))
        XCTAssertEqual(s.handle("undo").text, "Took back Black's pawn to e5 and your pawn to e4. It's your move.")
        XCTAssertEqual(s.snapshot.position, .start)
        XCTAssertEqual(s.handle("undo").tone, .error)
    }

    func testNewGameAsksFirst() {
        let s = ChessSession(opponent: .person)
        _ = s.handle("e4")
        XCTAssertEqual(s.handle("new game").tone, .question)
        XCTAssertEqual(s.handle("no").text, "Okay, the game continues.")
        XCTAssertEqual(s.snapshot.notation, ["e4"])
        _ = s.handle("new game")
        XCTAssertEqual(s.handle("yes").text, "New game. White to move.")
        XCTAssertEqual(s.snapshot.position, .start)
    }

    func testTwoPlayersShareTheDevice() {
        let s = ChessSession(opponent: .person)
        XCTAssertEqual(s.handle("f3").text, "White played pawn to f3. Black to move.")
        XCTAssertEqual(s.handle("e5").text, "Black played pawn to e5. White to move.")
        XCTAssertEqual(s.handle("where are my knights").text, "White's knights are on b1 and g1.")
        _ = s.handle("g4")
        XCTAssertEqual(s.handle("queen to h4").text, "Black played queen from d8 to h4. Checkmate. Black wins.")
        XCTAssertEqual(s.handle("last move").text, "Black's last move was queen from d8 to h4. Checkmate.")
        XCTAssertEqual(s.handle("read the moves").text,
                       "Move 1: White pawn to f3, Black pawn to e5. Move 2: White pawn to g4, Black queen to h4.")
    }

    func testPromotionDefaultsToQueenButCanBeChosen() {
        let s = session("8/4P3/7k/8/8/7p/8/4K3 w - - 0 1", opponent: .person)
        XCTAssertEqual(s.handle("e8").text, "White played pawn to e8, promoting to a queen. Black to move.")
        _ = s.handle("undo")
        XCTAssertEqual(s.handle("e8 knight").text, "White played pawn to e8, promoting to a knight. Black to move.")
    }

    func testSummaryIsShort() {
        let s = ChessSession.practice()
        XCTAssertEqual(
            s.handle("describe the position").text,
            "Move 10. It's your move. Material is even. Your king is on g1. Black's king is on g8. "
            + "In danger: your knight on a3 is attacked by Black's pawn on b4. You have 2 captures available."
        )
    }

    func testRepeatAndHelpAndUnknown() {
        let s = ChessSession()
        let first = s.handle("where is my queen")
        XCTAssertEqual(s.handle("repeat").text, first.text)
        XCTAssertEqual(s.handle("say that again").text, first.text)
        XCTAssertTrue(s.handle("what can I say?").text.contains("knight to f3"))
        XCTAssertEqual(s.handle("tell me a joke").tone, .error)
        XCTAssertTrue(s.needsInterpretation("tell me a joke"))
        XCTAssertFalse(s.needsInterpretation("where are my knights"))
    }

    func testResigning() {
        let s = ChessSession()
        XCTAssertEqual(s.handle("I resign").tone, .question)
        let reply = s.handle("yes")
        XCTAssertEqual(reply.text, "You resigned. Black wins.")
        XCTAssertEqual(reply.tone, .gameOver)
    }
}

final class ChessAITests: XCTestCase {

    func testFindsMateInOne() throws {
        let p = try XCTUnwrap(ChessPosition(fen: "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1"))
        XCTAssertEqual(ChessAI.chooseMove(in: p, difficulty: .steady, seed: 7)?.coordinates, "a1a8")
        XCTAssertEqual(ChessAI.chooseMove(in: p, difficulty: .sharp, seed: 7)?.coordinates, "a1a8")
    }

    func testTakesAFreeQueen() throws {
        let p = try XCTUnwrap(ChessPosition(fen: "4k3/8/8/3q4/8/2N5/8/4K3 w - - 0 1"))
        XCTAssertEqual(ChessAI.chooseMove(in: p, difficulty: .steady, seed: 3)?.coordinates, "c3d5")
    }

    func testEveryLevelPlaysLegalMovesQuickly() {
        var position = ChessPosition.start
        var slowest = 0.0
        var seed: UInt64 = 1
        for ply in 0..<24 {
            let difficulty = Difficulty.allCases[ply % 3]
            let started = Date()
            guard let move = ChessAI.chooseMove(in: position, difficulty: difficulty, seed: seed) else { break }
            slowest = max(slowest, Date().timeIntervalSince(started))
            XCTAssertTrue(position.legalMoves().contains(move))
            position.apply(move)
            seed += 1
        }
        // Debug builds are far slower than the shipped app; this is a ceiling, not a target.
        XCTAssertLessThan(slowest, 4.0)
        print("slowest computer move in a debug build: \(slowest) s")
    }

    func testSameSeedSameMove() {
        let a = ChessAI.chooseMove(in: .start, difficulty: .gentle, seed: 42)
        let b = ChessAI.chooseMove(in: .start, difficulty: .gentle, seed: 42)
        XCTAssertEqual(a, b)
    }
}
