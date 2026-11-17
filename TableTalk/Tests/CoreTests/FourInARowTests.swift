import XCTest
@testable import TableTalkCore

/// SplitMix64: a tiny seedable generator, so every "random" game in these
/// tests plays out the same way on every run.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class FourInARowTests: XCTestCase {

    private typealias Board = FourInARowBoard
    private typealias Cell = FourInARowBoard.Cell

    // MARK: Helpers

    /// Builds a board from drops such as "r4 y4 r3": Red in column 4,
    /// Yellow in column 4, Red in column 3.
    private func board(_ drops: String) -> FourInARowBoard {
        var board = FourInARowBoard()
        for drop in drops.split(separator: " ") {
            let side: Board.Side = drop.hasPrefix("r") ? .red : .yellow
            let landed = board.drop(side, inColumn: Int(drop.dropFirst()) ?? 0)
            XCTAssertNotNil(landed, "could not drop \(drop)")
        }
        return board
    }

    /// Two people sharing the device, with these columns already played in turn.
    private func twoPlayers(_ columns: [Int] = []) -> FourInARowSession {
        let session = FourInARowSession(opponent: .person)
        for column in columns { _ = session.handle("\(column)") }
        return session
    }

    /// A game against the computer with both sides' moves scripted, so the
    /// position is known exactly. The columns alternate, starting with
    /// whoever moves first.
    private func againstComputer(_ columns: [Int] = [], humanStarts: Bool = true) -> FourInARowSession {
        let session = FourInARowSession(opponent: .computer, difficulty: .sharp, humanStarts: humanStarts)
        for (index, column) in columns.enumerated() {
            let humanToMove = (index % 2 == 0) == humanStarts
            _ = humanToMove ? session.handle("column \(column)") : session.play(computerMove: column)
        }
        return session
    }

    /// Red has columns 1, 2 and 3 on the bottom row and can win in column 4.
    /// Yellow (the computer) has three stacked in column 7 and can win there.
    /// It is Red's turn.
    private func bothThreatening() -> FourInARowSession {
        againstComputer([1, 7, 2, 7, 3, 7])
    }

    /// 42 moves that fill the board without anyone making four in a row.
    private let drawnGame = [1, 1, 1, 1, 1, 3, 3, 3, 3, 3, 3, 1, 2, 2, 2, 2, 2, 4, 4, 4, 4, 4, 4, 2,
                             5, 5, 5, 5, 5, 7, 7, 7, 7, 7, 7, 5, 6, 6, 6, 6, 6, 6]

    private func parse(_ text: String) -> FourInARowRequest {
        FourInARowRequest.parse(Phrase.words(text))
    }

    // MARK: Board

    func testPiecesStackFromTheBottom() {
        var board = FourInARowBoard()
        XCTAssertEqual(board.drop(.red, inColumn: 4), Cell(column: 4, row: 1))
        XCTAssertEqual(board.drop(.yellow, inColumn: 4), Cell(column: 4, row: 2))
        XCTAssertEqual(board[column: 4, row: 1], .red)
        XCTAssertEqual(board[column: 4, row: 2], .yellow)
        XCTAssertNil(board[column: 4, row: 3])
        XCTAssertEqual(board.height(ofColumn: 4), 2)
        XCTAssertEqual(board.pieceCount, 2)
        XCTAssertEqual(board.removeTopPiece(fromColumn: 4), .yellow)
        XCTAssertEqual(board.height(ofColumn: 4), 1)
    }

    func testFullAndMissingColumnsRefuseADrop() {
        var board = board("r2 y2 r2 y2 r2 y2")
        XCTAssertTrue(board.isFull(column: 2))
        XCTAssertNil(board.drop(.red, inColumn: 2))
        XCTAssertNil(board.drop(.red, inColumn: 0))
        XCTAssertNil(board.drop(.red, inColumn: 8))
        XCTAssertEqual(board.pieceCount, 6)
        XCTAssertEqual(board.fullColumns, [2])
        XCTAssertEqual(board.openColumns, [1, 3, 4, 5, 6, 7])
    }

    func testWinAcross() {
        let win = board("r2 r3 r4 y1 r5").win
        XCTAssertEqual(win?.side, .red)
        XCTAssertEqual(win?.cells, (2...5).map { Cell(column: $0, row: 1) })
    }

    func testWinStraightUp() {
        let win = board("r1 y6 y6 y6 y6").win
        XCTAssertEqual(win?.side, .yellow)
        XCTAssertEqual(win?.cells, (1...4).map { Cell(column: 6, row: $0) })
    }

    func testWinOnRisingDiagonal() {
        let win = board("r1 y2 r2 y3 y3 r3 y4 y4 y4 r4").win
        XCTAssertEqual(win?.side, .red)
        XCTAssertEqual(win?.cells, (1...4).map { Cell(column: $0, row: $0) })
    }

    func testWinOnFallingDiagonal() {
        let win = board("y7 r6 y6 r5 r5 y5 r4 r4 r4 y4").win
        XCTAssertEqual(win?.side, .yellow)
        XCTAssertEqual(win?.cells, [Cell(column: 4, row: 4), Cell(column: 5, row: 3),
                                    Cell(column: 6, row: 2), Cell(column: 7, row: 1)])
    }

    func testLongerLineIsReportedWhole() {
        let win = board("r1 r2 r4 r5 r3").win
        XCTAssertEqual(win?.lines.count, 1)
        XCTAssertEqual(win?.cells.count, 5)
    }

    func testOnePieceCanFinishTwoLines() {
        // Red holds columns 1 to 3 of the bottom row and a diagonal running
        // up from column 5. Column 4 joins both.
        let before = "r1 r2 r3 y5 r5 y6 y6 r6 y7 y7 y7 r7"
        XCTAssertNil(board(before).win)
        let win = board(before + " r4").win
        XCTAssertEqual(win?.side, .red)
        XCTAssertEqual(win?.lines.count, 2)
        // Seven cells, not eight: the shared one is only listed once.
        XCTAssertEqual(win?.cells.count, 7)
        XCTAssertEqual(Set(win?.cells ?? []).count, 7)
    }

    func testThreeInARowIsNotAWin() {
        XCTAssertNil(board("r1 r2 r3 y4 r5 r6 r7").win)
    }

    func testFullBoardWithNoLineIsADraw() {
        var board = FourInARowBoard()
        for (index, column) in drawnGame.enumerated() {
            board.drop(index % 2 == 0 ? .red : .yellow, inColumn: column)
        }
        XCTAssertTrue(board.isFull)
        XCTAssertNil(board.win)
        XCTAssertEqual(board.openColumns, [])
    }

    func testWinningColumns() {
        let board = board("r1 r2 r3 y7 y7 y7")
        XCTAssertEqual(board.winningColumns(for: .red), [4])
        XCTAssertEqual(board.winningColumns(for: .yellow), [7])
        // A gap in the middle counts too, and so do both ends of an open three.
        XCTAssertEqual(self.board("r1 r2 r4").winningColumns(for: .red), [3])
        XCTAssertEqual(self.board("r3 r4 r5").winningColumns(for: .red), [2, 6])
    }

    // MARK: Understanding

    func testMovePhrasings() {
        let phrasings: [(String, Int)] = [
            ("column 4", 4),
            ("Column four.", 4),
            ("drop in 4", 4),
            ("play four", 4),
            ("4", 4),
            ("seven", 7),
            ("the middle", 4),
            ("centre column", 4),
            ("leftmost", 1),
            ("rightmost column", 7),
            ("far right", 7),
            ("the left hand side", 1),
            ("the last column", 7),
            ("third column", 3),
            ("the middle one", 4),
            ("um, drop it in column three please", 3),
            ("I'd like to play 5", 5),
            ("okay, six", 6),
            ("no, 2", 2),
            ("drop one in column 2", 2),
            ("put a piece in number 6", 6),
            ("how about the middle", 4),
        ]
        for (text, column) in phrasings {
            XCTAssertEqual(parse(text), .drop(column: column), text)
        }
    }

    func testSoundAlikesAreNumbersOnlyWhereNothingElseFits() {
        XCTAssertEqual(parse("for"), .drop(column: 4))
        XCTAssertEqual(parse("to"), .drop(column: 2))
        XCTAssertEqual(parse("play for"), .drop(column: 4))
        XCTAssertEqual(parse("column for"), .drop(column: 4))
        XCTAssertEqual(parse("drop in to please"), .drop(column: 2))
        XCTAssertEqual(parse("I want to play for"), .drop(column: 4))
        // Here "to" is just a word.
        XCTAssertEqual(parse("I want to play 6"), .drop(column: 6))
        XCTAssertEqual(parse("I want to"), .unknown)
        XCTAssertEqual(parse("me too"), .unknown)
        XCTAssertEqual(parse("read row to"), .readRow(2))
    }

    func testQuestionsThatMentionAColumnAreNotMoves() {
        XCTAssertEqual(parse("read column 3"), .readColumn(3))
        XCTAssertEqual(parse("what's in column three?"), .readColumn(3))
        XCTAssertEqual(parse("is column 4 full"), .readColumn(4))
        XCTAssertEqual(parse("how high is the middle column"), .readColumn(4))
        XCTAssertEqual(parse("read row 2"), .readRow(2))
        XCTAssertEqual(parse("read the bottom row"), .readRow(1))
        XCTAssertEqual(parse("what's in column 3 row 2"), .readCell(column: 3, row: 2))
        XCTAssertEqual(parse("row 2, column 3"), .readCell(column: 3, row: 2))
        XCTAssertEqual(parse("third column second row"), .readCell(column: 3, row: 2))
        XCTAssertEqual(parse("what did the computer play in column 4"), .common(.lastMove))
        XCTAssertEqual(parse("can I win in column 4"), .threats)
    }

    func testQuestionPhrasings() {
        XCTAssertEqual(parse("how full are the columns"), .heights)
        XCTAssertEqual(parse("column heights"), .heights)
        XCTAssertEqual(parse("how many in each column"), .heights)
        XCTAssertEqual(parse("which columns are full"), .openColumns)
        XCTAssertEqual(parse("which columns are open?"), .openColumns)
        XCTAssertEqual(parse("where can I play"), .openColumns)
        XCTAssertEqual(parse("where are my pieces"), .pieces(.mine))
        XCTAssertEqual(parse("where are mine"), .pieces(.mine))
        XCTAssertEqual(parse("where are theirs"), .pieces(.theirs))
        XCTAssertEqual(parse("where are the computer's pieces"), .pieces(.theirs))
        XCTAssertEqual(parse("where are my opponent's pieces"), .pieces(.theirs))
        XCTAssertEqual(parse("where are the yellow pieces"), .pieces(.side(.yellow)))
        XCTAssertEqual(parse("where is everything"), .pieces(.everyone))
        XCTAssertEqual(parse("can anyone win"), .threats)
        XCTAssertEqual(parse("Can anyone win?"), .threats)
        XCTAssertEqual(parse("any threats"), .threats)
        XCTAssertEqual(parse("am I in danger"), .threats)
        XCTAssertEqual(parse("do I need to block"), .threats)
        XCTAssertEqual(parse("who won"), .gameStatus)
        XCTAssertEqual(parse("is the game over"), .gameStatus)
        XCTAssertEqual(parse("what colour am I"), .whoAmI)
        XCTAssertEqual(parse("undo"), .common(.undo))
        XCTAssertEqual(parse("last move"), .common(.lastMove))
        XCTAssertEqual(parse("read the board"), .common(.readBoard))
        XCTAssertEqual(parse("yes"), .common(.yes))
        XCTAssertEqual(parse("sing me a song"), .unknown)
    }

    // MARK: Moves

    func testOpeningSaysWhoYouAre() {
        let session = FourInARowSession()
        XCTAssertEqual(session.title, "Four in a Row")
        let opening = session.opening()
        XCTAssertEqual(opening.tone, .info)
        XCTAssertTrue(opening.text.contains("You are Red and go first"), opening.text)
        XCTAssertTrue(opening.text.contains("Gentle"), opening.text)

        let second = FourInARowSession(opponent: .computer, difficulty: .sharp, humanStarts: false)
        XCTAssertTrue(second.opening().text.contains("The computer is Red and goes first. You are Yellow."))

        let shared = FourInARowSession(opponent: .person)
        XCTAssertTrue(shared.opening().text.contains("two players"))
    }

    func testMoveRepliesAgainstTheComputer() {
        let session = againstComputer()
        let mine = session.handle("Drop in column four")
        XCTAssertEqual(mine, Reply("You dropped in column 4. It landed on row 1.", tone: .move, boardChanged: true))
        let theirs = session.play(computerMove: 4)
        XCTAssertEqual(theirs, Reply("The computer dropped in column 4. It landed on row 2.", tone: .move, boardChanged: true))
        XCTAssertEqual(session.snapshot.moveCount, 2)
    }

    func testMoveRepliesBetweenTwoPeopleNameTheSides() {
        let session = twoPlayers()
        XCTAssertEqual(session.handle("the middle").text, "Red dropped in column 4. It landed on row 1. Yellow's turn.")
        XCTAssertEqual(session.handle("leftmost").text, "Yellow dropped in column 1. It landed on row 1. Red's turn.")
    }

    func testWinningMoveEndsTheGame() {
        let session = twoPlayers([1, 1, 2, 2, 3, 3])
        let reply = session.handle("4")
        XCTAssertEqual(reply.tone, .gameOver)
        XCTAssertTrue(reply.boardChanged)
        XCTAssertEqual(reply.text, "Red dropped in column 4. It landed on row 1. "
                       + "Four in a row across row 1, columns 1 to 4. Red wins! Say new game to play again.")
        XCTAssertTrue(session.isOver)
        XCTAssertEqual(session.snapshot.winner, .red)
        XCTAssertEqual(session.snapshot.winningCells, (1...4).map { Cell(column: $0, row: 1) })
        XCTAssertFalse(session.snapshot.isDraw)
    }

    func testComputerWinIsAnnounced() {
        // The player ignores the stack in column 7.
        let session = againstComputer([1, 7, 2, 7, 3, 7, 1])
        let reply = session.play(computerMove: 7)
        XCTAssertEqual(reply.tone, .gameOver)
        XCTAssertTrue(reply.text.contains("Four in a row up column 7, rows 1 to 4. The computer wins."), reply.text)
        XCTAssertEqual(session.handle("whose turn is it").text,
                       "The game is over. The computer won with four in a row up column 7, rows 1 to 4. "
                       + "Say new game to play again.")
    }

    func testFullBoardIsADraw() {
        let session = twoPlayers(Array(drawnGame.dropLast()))
        XCTAssertFalse(session.isOver)
        let reply = session.handle("column 6")
        XCTAssertEqual(reply.tone, .gameOver)
        XCTAssertTrue(reply.text.contains("draw"), reply.text)
        XCTAssertTrue(session.isOver)
        XCTAssertTrue(session.snapshot.isDraw)
        XCTAssertNil(session.snapshot.winner)
        XCTAssertEqual(session.snapshot.winningCells, [])
    }

    func testIllegalMovesExplainWhatIsPossible() {
        let session = twoPlayers([4, 4, 4, 4, 4, 4])

        let full = session.handle("column 4")
        XCTAssertEqual(full, Reply("Column 4 is full. Open columns: 1, 2, 3, 5, 6 and 7.", tone: .error))

        let missing = session.handle("column 9")
        XCTAssertEqual(missing, Reply("There is no column 9. Columns are numbered 1 to 7 from the left.", tone: .error))
        XCTAssertEqual(session.handle("0").tone, .error)

        let nonsense = session.handle("purple monkey dishwasher")
        XCTAssertEqual(nonsense.tone, .error)
        XCTAssertTrue(nonsense.text.contains("Say a column from 1 to 7, or say help."), nonsense.text)

        let silence = session.handle("  ...  ")
        XCTAssertEqual(silence.tone, .error)

        XCTAssertEqual(session.snapshot.moveCount, 6, "none of these may change the board")
    }

    func testNoMovesAfterTheGameIsOver() {
        let session = twoPlayers([1, 1, 2, 2, 3, 3, 4])
        let reply = session.handle("column 5")
        XCTAssertEqual(reply.tone, .error)
        XCTAssertFalse(reply.boardChanged)
        XCTAssertTrue(reply.text.contains("The game is over."), reply.text)
        XCTAssertTrue(reply.text.contains("Say new game to play again."), reply.text)
        XCTAssertEqual(session.snapshot.moveCount, 7)
    }

    func testWhileTheComputerThinksQuestionsWorkButMovesWait() {
        let session = againstComputer([4])
        let move = session.handle("column 3")
        XCTAssertEqual(move.tone, .error)
        XCTAssertTrue(move.text.contains("computer's turn"), move.text)
        XCTAssertEqual(session.snapshot.moveCount, 1)

        XCTAssertEqual(session.handle("undo").tone, .error)
        XCTAssertEqual(session.handle("hint").tone, .error)
        XCTAssertEqual(session.snapshot.moveCount, 1)

        XCTAssertEqual(session.handle("read column 4").text, "Column 4 has 1 piece. From the bottom: you.")
        XCTAssertEqual(session.handle("whose turn is it").text, "It is the computer's turn. You are Red.")
    }

    // MARK: Questions

    func testReadTheBoard() {
        XCTAssertEqual(againstComputer().handle("read the board").text, "The board is empty.")
        XCTAssertEqual(bothThreatening().handle("Read the board").text,
                       "From the bottom up. Column 1: you. Column 2: you. Column 3: you. "
                       + "Columns 4 to 6: empty. Column 7: computer, computer, computer.")
        XCTAssertEqual(twoPlayers([4, 4, 5]).handle("read the whole board").text,
                       "From the bottom up. Columns 1 to 3: empty. Column 4: Red, Yellow. "
                       + "Column 5: Red. Columns 6 and 7: empty.")
    }

    func testReadAColumn() {
        let session = bothThreatening()
        XCTAssertEqual(session.handle("read column 7").text,
                       "Column 7 has 3 pieces. From the bottom: computer, computer, computer.")
        XCTAssertEqual(session.handle("what's in column four").text, "Column 4 is empty.")
        XCTAssertEqual(session.handle("read column 8").tone, .error)

        let full = twoPlayers([4, 4, 4, 4, 4, 4])
        XCTAssertEqual(full.handle("read column 4").text,
                       "Column 4 is full. From the bottom: Red, Yellow, Red, Yellow, Red, Yellow.")
    }

    func testReadARow() {
        let session = bothThreatening()
        XCTAssertEqual(session.handle("read row 1").text,
                       "Row 1: you in columns 1, 2 and 3; the computer in column 7. The other columns are empty.")
        XCTAssertEqual(session.handle("read row two").text,
                       "Row 2: the computer in column 7. The other columns are empty.")
        XCTAssertEqual(session.handle("read the top row").text, "Row 6 is empty.")
        XCTAssertEqual(session.handle("read row 7").tone, .error)
    }

    func testWhatIsOnASpace() {
        let session = bothThreatening()
        XCTAssertEqual(session.handle("what's in column 7 row 2").text, "Column 7, row 2 is the computer's.")
        XCTAssertEqual(session.handle("what is in column 1, row 1?").text, "Column 1, row 1 is yours.")
        XCTAssertEqual(session.handle("column 4 row 1").text,
                       "Column 4, row 1 is empty. It is where the next piece in column 4 will land.")
        XCTAssertEqual(session.handle("what's in column 7 row 6").text,
                       "Column 7, row 6 is empty. The next piece in column 7 will land on row 4.")
        XCTAssertEqual(session.handle("what's in column 3 row 9").tone, .error)
        XCTAssertEqual(twoPlayers([2]).handle("what's in column 2 row 1").text, "Column 2, row 1 is Red.")
        XCTAssertEqual(session.snapshot.moveCount, 6, "asking must not move")
    }

    func testColumnHeights() {
        XCTAssertEqual(againstComputer().handle("how full are the columns").text, "Every column is empty.")
        XCTAssertEqual(bothThreatening().handle("How full are the columns?").text,
                       "Column 1 has 1, column 2 has 1, column 3 has 1 and column 7 has 3. The other columns are empty.")
        XCTAssertEqual(twoPlayers([4, 4, 4, 4, 4, 4, 5]).handle("column heights").text,
                       "Column 4 is full and column 5 has 1. The other columns are empty.")
    }

    func testWhereThePiecesAre() {
        let session = bothThreatening()
        XCTAssertEqual(session.handle("where are my pieces").text,
                       "You have 3 pieces: column 1, row 1; column 2, row 1; column 3, row 1.")
        XCTAssertEqual(session.handle("where are theirs?").text,
                       "The computer has 3 pieces: column 7, rows 1, 2 and 3.")
        XCTAssertEqual(session.handle("where are the yellow pieces").text,
                       "The computer has 3 pieces: column 7, rows 1, 2 and 3.")
        XCTAssertEqual(againstComputer().handle("where are my pieces").text, "You have no pieces on the board yet.")
    }

    func testMyPiecesMeansTheSideToMoveBetweenTwoPeople() {
        let session = twoPlayers([4, 5, 4])
        // Yellow is to move.
        XCTAssertEqual(session.handle("where are my pieces").text, "Yellow has 1 piece: column 5, row 1.")
        XCTAssertEqual(session.handle("where are theirs").text, "Red has 2 pieces: column 4, rows 1 and 2.")
        XCTAssertEqual(session.handle("where are red's pieces").text, "Red has 2 pieces: column 4, rows 1 and 2.")
    }

    func testCanAnyoneWin() {
        XCTAssertEqual(againstComputer([4, 4]).handle("can anyone win").text, "Nobody can win on the next move.")
        XCTAssertEqual(bothThreatening().handle("Can anyone win?").text,
                       "You can win in column 4. The computer can also win in column 7, but you move first.")
        // Only the player threatens.
        XCTAssertEqual(againstComputer([1, 7, 2, 7, 3, 6]).handle("threats").text, "You can win in column 4.")
        // Only the computer threatens.
        XCTAssertEqual(againstComputer([1, 7, 2, 7, 5, 7]).handle("can anyone win").text,
                       "The computer can win in column 7, so block it.")
        // An open three: two ways to win.
        XCTAssertEqual(againstComputer([3, 3, 4, 4, 5, 5]).handle("any threats").text,
                       "You can win in column 2 or 6.")
        // Between two people the sides are named.
        XCTAssertEqual(twoPlayers([1, 7, 2, 7, 5, 7]).handle("can anyone win").text,
                       "Yellow can win in column 7, so Red must block it.")
    }

    func testFullAndOpenColumns() {
        XCTAssertEqual(bothThreatening().handle("which columns are full").text, "No column is full. All 7 are open.")
        XCTAssertEqual(twoPlayers([4, 4, 4, 4, 4, 4]).handle("which columns are open").text,
                       "Column 4 is full. Open columns: 1, 2, 3, 5, 6 and 7.")
    }

    func testLastMoveAndHistory() {
        let fresh = againstComputer()
        XCTAssertEqual(fresh.handle("last move").text, "No moves have been played yet.")
        XCTAssertEqual(fresh.handle("history").text, "No moves have been played yet.")

        let session = bothThreatening()
        XCTAssertEqual(session.handle("what was the last move").text,
                       "The computer dropped in column 7, landing on row 3. "
                       + "Before that, you dropped in column 3, landing on row 1.")
        XCTAssertEqual(session.handle("history").text,
                       "6 moves so far, by column: you 1, computer 7, you 2, computer 7, you 3, computer 7.")
        XCTAssertEqual(twoPlayers([4, 5]).handle("moves so far").text,
                       "2 moves so far, by column: Red 4, Yellow 5.")
    }

    func testSummaryAndTurn() {
        let session = bothThreatening()
        XCTAssertEqual(session.handle("summary").text,
                       "It is your turn, move 7. Heights for columns 1 to 7: 1, 1, 1, 0, 0, 0, 3. "
                       + "You can win in column 4. The computer can also win in column 7, but you move first.")
        XCTAssertEqual(session.handle("whose turn is it").text, "It is your turn. You are Red.")
        XCTAssertEqual(session.handle("what colour am I").text, "You are Red. The computer is Yellow.")
        XCTAssertEqual(againstComputer().handle("summary").text, "It is your turn, move 1. The board is empty.")
        XCTAssertEqual(twoPlayers([4]).handle("whose turn").text, "It is Yellow's turn.")
        XCTAssertEqual(twoPlayers([4]).handle("what's going on").text,
                       "It is Yellow's turn, move 2. Heights for columns 1 to 7: 0, 0, 0, 1, 0, 0, 0. "
                       + "Nobody can win on the next move.")
    }

    func testHelpAndRepeat() {
        let session = againstComputer()
        let help = session.handle("help")
        XCTAssertEqual(help.tone, .info)
        XCTAssertTrue(help.text.contains("Say a column from 1 to 7"), help.text)

        let move = session.handle("4")
        let again = session.handle("say that again")
        XCTAssertEqual(again.text, move.text)
        XCTAssertEqual(again.tone, move.tone)
        XCTAssertFalse(again.boardChanged, "repeating must not look like a second move")
        XCTAssertEqual(session.snapshot.moveCount, 1)
    }

    // MARK: Warnings

    func testComputerThreatIsAnnounced() {
        let session = againstComputer([1, 7, 2, 7, 5])
        let reply = session.play(computerMove: 7)
        XCTAssertEqual(reply.tone, .alert)
        XCTAssertEqual(reply.text, "The computer dropped in column 7. It landed on row 3. "
                       + "Careful: the computer can win in column 7.")
    }

    func testThreatAnnouncementCanBeTurnedOff() {
        let session = againstComputer([1, 7, 2, 7, 5])
        session.announceThreats = false
        let reply = session.play(computerMove: 7)
        XCTAssertEqual(reply.tone, .move)
        XCTAssertEqual(reply.text, "The computer dropped in column 7. It landed on row 3.")
    }

    // MARK: Undo

    func testUndoAgainstTheComputerTakesBackBothMoves() {
        let session = againstComputer([4, 3])
        let reply = session.handle("undo")
        XCTAssertEqual(reply, Reply("Took back the computer's piece from column 3 and your piece from column 4. "
                                    + "It is your turn again.", boardChanged: true))
        XCTAssertEqual(session.snapshot.moveCount, 0)
        XCTAssertEqual(session.snapshot.board, FourInARowBoard())
        XCTAssertNil(session.computerMoveJob(), "it is the player's turn again")

        let nothing = session.handle("undo")
        XCTAssertEqual(nothing.tone, .error)
        XCTAssertFalse(nothing.boardChanged)
    }

    func testUndoAfterThePlayerWinsTakesBackOnlyThatMove() {
        let session = againstComputer([1, 7, 2, 7, 3, 7, 4])
        XCTAssertTrue(session.isOver)
        let reply = session.handle("take that back")
        XCTAssertEqual(reply.text, "Took back your piece from column 4. It is your turn again.")
        XCTAssertFalse(session.isOver)
        XCTAssertEqual(session.snapshot.moveCount, 6)
        XCTAssertEqual(session.snapshot.turn, .red)
    }

    func testUndoBeforeThePlayerHasMoved() {
        let session = againstComputer([4], humanStarts: false)
        let reply = session.handle("undo")
        XCTAssertEqual(reply.tone, .error)
        XCTAssertTrue(reply.text.contains("you have not moved yet"), reply.text)
        XCTAssertEqual(session.snapshot.moveCount, 1)
    }

    func testUndoBetweenTwoPeopleTakesBackOneMove() {
        let session = twoPlayers([4, 5])
        let reply = session.handle("undo")
        XCTAssertEqual(reply, Reply("Took back Yellow's piece from column 5. It is Yellow's turn again.", boardChanged: true))
        XCTAssertEqual(session.snapshot.moveCount, 1)
        XCTAssertEqual(session.snapshot.turn, .yellow)
        XCTAssertEqual(session.handle("undo").text, "Took back Red's piece from column 4. It is Red's turn again.")
        XCTAssertEqual(session.handle("undo").tone, .error)
    }

    // MARK: New game

    func testNewGameOnAnUntouchedBoardNeedsNoConfirmation() {
        let session = againstComputer()
        let reply = session.handle("new game")
        XCTAssertEqual(reply, Reply("New game. You are Red and go first.", boardChanged: true))
    }

    func testNewGameAsksFirstAndYesStartsIt() {
        let session = againstComputer([4, 4])
        let question = session.handle("new game")
        XCTAssertEqual(question, Reply("Start a new game? Say yes or no.", tone: .question))
        XCTAssertEqual(session.snapshot.moveCount, 2, "nothing happens until the answer")
        XCTAssertEqual(session.suggestions, ["Yes", "No", "Repeat"])

        let started = session.handle("yes")
        XCTAssertTrue(started.boardChanged)
        XCTAssertTrue(started.text.hasPrefix("New game."), started.text)
        XCTAssertEqual(session.snapshot.moveCount, 0)
        XCTAssertEqual(session.snapshot.board, FourInARowBoard())
    }

    func testNewGameCanBeDeclined() {
        let session = againstComputer([4, 4])
        _ = session.handle("start over")
        let reply = session.handle("no")
        XCTAssertEqual(reply.tone, .info)
        XCTAssertFalse(reply.boardChanged)
        XCTAssertTrue(reply.text.contains("carries on"), reply.text)
        XCTAssertEqual(session.snapshot.moveCount, 2)
    }

    func testAnUnrelatedRequestCancelsTheNewGameQuestion() {
        let session = againstComputer([4, 4])
        _ = session.handle("new game")
        XCTAssertEqual(session.handle("read column 4").text, "Column 4 has 2 pieces. From the bottom: you, computer.")

        // The question is gone, so a late "yes" must not wipe the board.
        let late = session.handle("yes")
        XCTAssertEqual(late.tone, .error)
        XCTAssertEqual(session.snapshot.moveCount, 2)
    }

    func testAMoveCancelsTheNewGameQuestionAndIsPlayed() {
        let session = againstComputer([4, 4])
        _ = session.handle("new game")
        let move = session.handle("column 5")
        XCTAssertEqual(move.tone, .move)
        XCTAssertEqual(session.snapshot.moveCount, 3)
    }

    func testRepeatKeepsTheQuestionOpen() {
        let session = againstComputer([4, 4])
        let question = session.handle("new game")
        let again = session.handle("repeat")
        XCTAssertEqual(again.text, question.text)
        XCTAssertEqual(again.tone, .question)
        XCTAssertTrue(session.handle("yes").boardChanged)
        XCTAssertEqual(session.snapshot.moveCount, 0)
    }

    func testNewGameAfterTheGameIsOverStartsAtOnce() {
        let session = twoPlayers([1, 1, 2, 2, 3, 3, 4])
        let reply = session.handle("play again")
        XCTAssertEqual(reply, Reply("New game. Red goes first.", boardChanged: true))
        XCTAssertFalse(session.isOver)
    }

    // MARK: Hint

    func testHintNamesAWinAndYesPlaysIt() {
        let session = bothThreatening()
        let hint = session.handle("hint")
        XCTAssertEqual(hint, Reply("Column 4 wins the game. Say yes to play it."))
        XCTAssertEqual(session.snapshot.moveCount, 6, "a hint does not move")

        let played = session.handle("yes")
        XCTAssertEqual(played.tone, .gameOver)
        XCTAssertTrue(played.text.hasPrefix("You dropped in column 4."), played.text)
        XCTAssertEqual(session.snapshot.winner, .red)
    }

    func testHintNamesABlock() {
        let session = againstComputer([1, 7, 2, 7, 5, 7])
        XCTAssertEqual(session.handle("what should I do").text,
                       "Column 7 stops the computer making four in a row. Say yes to play it.")
        let played = session.handle("play it")
        XCTAssertEqual(played.text, "You dropped in column 7. It landed on row 4.")
    }

    func testHintOnAQuietBoardSuggestsAColumnAndYesPlaysIt() {
        let session = againstComputer()
        let hint = session.handle("give me a hint")
        XCTAssertEqual(hint.text, "Try column 4. Say yes to play it.")
        let played = session.handle("yes please")
        XCTAssertEqual(played.text, "You dropped in column 4. It landed on row 1.")
        XCTAssertEqual(session.snapshot.lastMove, Cell(column: 4, row: 1))
    }

    func testHintCanBeDeclinedOrIgnored() {
        let session = againstComputer()
        _ = session.handle("hint")
        XCTAssertEqual(session.handle("no").tone, .info)
        XCTAssertEqual(session.snapshot.moveCount, 0)

        _ = session.handle("hint")
        XCTAssertEqual(session.handle("column 1").text, "You dropped in column 1. It landed on row 1.")
        XCTAssertEqual(session.snapshot.moveCount, 1)
    }

    func testYesWithNothingToConfirm() {
        let reply = againstComputer().handle("yes")
        XCTAssertEqual(reply.tone, .error)
        XCTAssertTrue(reply.text.contains("Say a column from 1 to 7"), reply.text)
    }

    // MARK: The computer's turn

    func testComputerMoveJobOnlyExistsOnTheComputersTurn() {
        let session = FourInARowSession(opponent: .computer, difficulty: .steady)
        XCTAssertNil(session.computerMoveJob(), "the player moves first")

        _ = session.handle("4")
        guard let job = session.computerMoveJob() else { return XCTFail("the computer should be thinking") }
        guard let column = job() else { return XCTFail("the job found no move") }
        XCTAssertTrue((1...7).contains(column))

        let reply = session.play(computerMove: column)
        XCTAssertTrue(reply.boardChanged)
        XCTAssertTrue(reply.text.hasPrefix("The computer dropped in column \(column)."), reply.text)
        XCTAssertEqual(session.snapshot.moveCount, 2)
        XCTAssertNil(session.computerMoveJob(), "back to the player")
    }

    func testComputerMovesFirstWhenThePlayerIsYellow() {
        let session = FourInARowSession(opponent: .computer, difficulty: .gentle, humanStarts: false)
        XCTAssertEqual(session.snapshot.you, .yellow)
        XCTAssertNotNil(session.computerMoveJob())
        XCTAssertEqual(session.handle("4").tone, .error, "the player has to wait")
    }

    func testNoComputerMoveJobBetweenTwoPeopleOrAfterTheGame() {
        let shared = twoPlayers([4])
        XCTAssertNil(shared.computerMoveJob())
        XCTAssertNil(shared.snapshot.you)

        let lost = againstComputer([1, 7, 2, 7, 3, 7, 1, 7])
        XCTAssertTrue(lost.isOver)
        XCTAssertNil(lost.computerMoveJob())
    }

    func testALateComputerMoveIsNotPlayed() {
        let session = againstComputer([4, 4])
        let reply = session.play(computerMove: 3)
        XCTAssertEqual(reply.tone, .error)
        XCTAssertFalse(reply.boardChanged)
        XCTAssertEqual(session.snapshot.moveCount, 2)
    }

    // MARK: Snapshot and suggestions

    func testSnapshotDescribesTheBoard() {
        let snapshot = bothThreatening().snapshot
        XCTAssertEqual(snapshot.board[column: 1, row: 1], .red)
        XCTAssertEqual(snapshot.board[column: 7, row: 3], .yellow)
        XCTAssertNil(snapshot.board[column: 4, row: 1])
        XCTAssertEqual(snapshot.turn, .red)
        XCTAssertEqual(snapshot.you, .red)
        XCTAssertEqual(snapshot.lastMove, Cell(column: 7, row: 3))
        XCTAssertEqual(snapshot.moveCount, 6)
        XCTAssertNil(snapshot.winner)
        XCTAssertFalse(snapshot.isOver)

        XCTAssertEqual(snapshot.label(for: Cell(column: 1, row: 1)), "Column 1, row 1, your piece")
        XCTAssertEqual(snapshot.label(for: Cell(column: 7, row: 3)), "Column 7, row 3, the computer's piece, last move")
        XCTAssertEqual(snapshot.label(for: Cell(column: 4, row: 1)), "Column 4, row 1, empty")

        let won = twoPlayers([1, 1, 2, 2, 3, 3, 4]).snapshot
        XCTAssertEqual(won.label(for: Cell(column: 4, row: 1)), "Column 4, row 1, Red, winning line, last move")
        XCTAssertEqual(won.label(for: Cell(column: 1, row: 2)), "Column 1, row 2, Yellow")
    }

    func testEverySuggestionIsUnderstood() {
        let moments: [FourInARowSession] = [
            againstComputer(),                          // nothing played
            againstComputer([4]),                       // the computer's turn
            againstComputer([4, 4]),                    // mid-game
            againstComputer([4], humanStarts: false),   // the computer opened
            twoPlayers([4, 5, 4]),
            twoPlayers([1, 1, 2, 2, 3, 3, 4]),          // game over
        ]
        for session in moments {
            let suggestions = session.suggestions
            XCTAssertTrue((3...5).contains(suggestions.count), "\(suggestions)")
            for suggestion in suggestions {
                // A fresh copy each time, so one suggestion cannot affect the next.
                let copy = session.snapshot.you == nil
                    ? twoPlayers(historyColumns(of: session))
                    : againstComputer(historyColumns(of: session), humanStarts: session.humanStarts)
                XCTAssertNotEqual(copy.handle(suggestion).tone, .error, suggestion)
            }
        }
        let asking = againstComputer([4, 4])
        _ = asking.handle("new game")
        XCTAssertEqual(asking.suggestions, ["Yes", "No", "Repeat"])
    }

    /// Recovers the columns played from the spoken history, e.g. "you 4, computer 4".
    private func historyColumns(of session: FourInARowSession) -> [Int] {
        let text = session.handle("history").text
        guard let list = text.split(separator: ":").last, text.contains("so far") else { return [] }
        return Phrase.words(String(list)).compactMap { Int($0) }
    }

    // MARK: Computer play

    func testSharpAndSteadyTakeAnImmediateWin() {
        // Yellow can finish column 7; Red also threatens column 4.
        let board = board("r1 y7 r2 y7 r3 y7")
        for difficulty in [Difficulty.steady, .sharp] {
            for seed in 0..<5 {
                var rng = SeededGenerator(seed: UInt64(seed))
                XCTAssertEqual(FourInARowAI.chooseColumn(on: board, for: .yellow, difficulty: difficulty, using: &rng), 7)
            }
        }
    }

    func testSharpAndSteadyBlockAnImmediateLoss() {
        // Red threatens column 4 and Yellow has nothing better.
        let board = board("r1 y7 r2 y6 r3")
        for difficulty in [Difficulty.steady, .sharp] {
            for seed in 0..<5 {
                var rng = SeededGenerator(seed: UInt64(seed))
                XCTAssertEqual(FourInARowAI.chooseColumn(on: board, for: .yellow, difficulty: difficulty, using: &rng), 4)
            }
        }
    }

    func testSharpAndSteadySeeTheOpenThreeComing() {
        // Red has two side by side on the bottom row with room on both
        // sides. Unless Yellow plays next to them now, Red makes an open
        // three and cannot be stopped.
        let board = board("r4 y4 r3")
        for difficulty in [Difficulty.steady, .sharp] {
            for seed in 0..<5 {
                var rng = SeededGenerator(seed: UInt64(seed))
                let column = FourInARowAI.chooseColumn(on: board, for: .yellow, difficulty: difficulty, using: &rng)
                XCTAssertTrue(column == 2 || column == 5, "\(difficulty) played \(String(describing: column))")
            }
        }
    }

    func testSharpFindsAForcedWin() {
        // Red to move: column 5 makes an open three, a win two moves later.
        let board = board("r3 y3 r4 y4")
        XCTAssertEqual(FourInARowAI.strongestColumns(on: board, for: .red, maxDepth: .max,
                                                     nodeBudget: FourInARowAI.sharpNodeBudget).sorted(), [2, 5])
    }

    func testGentleUsuallyTakesAWinButNotAlways() {
        let board = board("r1 y7 r2 y7 r3 y7")
        var wins = 0
        for seed in 0..<200 {
            var rng = SeededGenerator(seed: UInt64(seed))
            if FourInARowAI.chooseColumn(on: board, for: .yellow, difficulty: .gentle, using: &rng) == 7 { wins += 1 }
        }
        XCTAssertGreaterThan(wins, 150)
        XCTAssertLessThan(wins, 200, "gentle should slip now and then")
    }

    func testSameSeedGivesTheSameMove() {
        let board = board("r4 y3 r5 y4")
        for difficulty in Difficulty.allCases {
            var first = SeededGenerator(seed: 42)
            var second = SeededGenerator(seed: 42)
            XCTAssertEqual(FourInARowAI.chooseColumn(on: board, for: .red, difficulty: difficulty, using: &first),
                           FourInARowAI.chooseColumn(on: board, for: .red, difficulty: difficulty, using: &second))
        }
    }

    func testNoMoveOnAFullBoard() {
        var board = FourInARowBoard()
        for (index, column) in drawnGame.enumerated() {
            board.drop(index % 2 == 0 ? .red : .yellow, inColumn: column)
        }
        var rng = SeededGenerator(seed: 1)
        XCTAssertNil(FourInARowAI.chooseColumn(on: board, for: .red, difficulty: .sharp, using: &rng))
        XCTAssertNil(FourInARowAI.bestColumn(on: board, for: .red))
    }

    /// Plays one whole game between two levels and returns the final board
    /// and the longest time any single move took.
    private func playOut(red: Difficulty, yellow: Difficulty, seed: UInt64) -> (board: FourInARowBoard, slowest: TimeInterval) {
        var rng = SeededGenerator(seed: seed)
        var board = FourInARowBoard()
        var side = Board.Side.red
        var slowest: TimeInterval = 0
        while board.win == nil, !board.isFull {
            let started = Date()
            let column = FourInARowAI.chooseColumn(on: board, for: side, difficulty: side == .red ? red : yellow, using: &rng)
            slowest = max(slowest, Date().timeIntervalSince(started))
            guard let column, board.drop(side, inColumn: column) != nil else {
                XCTFail("illegal move \(String(describing: column))")
                break
            }
            side = side.other
        }
        return (board, slowest)
    }

    func testSharpAgainstSharpFinishesAndEveryMoveIsQuick() {
        let game = playOut(red: .sharp, yellow: .sharp, seed: 7)
        XCTAssertTrue(game.board.win != nil || game.board.isFull)
        XCTAssertGreaterThanOrEqual(game.board.pieceCount, 7)
        print("Four in a Row, sharp against sharp: \(game.board.pieceCount) moves, slowest \(game.slowest) s")
        XCTAssertLessThan(game.slowest, 1.0, "the sharp level must stay quick in a debug build")
    }

    func testEveryPairingOfLevelsFinishes() {
        for red in Difficulty.allCases {
            for yellow in Difficulty.allCases where !(red == .sharp && yellow == .sharp) {
                let game = playOut(red: red, yellow: yellow, seed: 3)
                XCTAssertTrue(game.board.win != nil || game.board.isFull, "\(red) against \(yellow)")
            }
        }
    }

    func testSharpBeatsGentle() {
        var sharpWins = 0
        for seed in 0..<4 {
            let sharpIsRed = seed % 2 == 0
            let game = playOut(red: sharpIsRed ? .sharp : .gentle, yellow: sharpIsRed ? .gentle : .sharp, seed: UInt64(seed))
            if game.board.win?.side == (sharpIsRed ? .red : .yellow) { sharpWins += 1 }
        }
        XCTAssertEqual(sharpWins, 4)
    }

    func testHintIsQuick() {
        let board = board("r4 y4 r3 y5 r5 y3")
        let started = Date()
        XCTAssertNotNil(FourInARowAI.bestColumn(on: board, for: .red))
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
    }
}
