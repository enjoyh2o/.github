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

final class TicTacToeTests: XCTestCase {

    private typealias Mark = TicTacToeBoard.Mark

    // MARK: Helpers

    /// Builds a board from a picture such as "XO. / .X. / ..O", read like
    /// the board itself: left to right, top to bottom, a dot for a free square.
    private func board(_ picture: String) -> TicTacToeBoard {
        var board = TicTacToeBoard()
        let cells = picture.filter { "XO.".contains($0) }
        XCTAssertEqual(cells.count, 9, "a board has nine squares")
        for (index, cell) in cells.enumerated() where cell != "." {
            board.place(cell == "X" ? .x : .o, on: index + 1)
        }
        return board
    }

    /// Two people sharing the device, with these squares already taken in turn.
    private func twoPlayers(_ squares: [Int] = []) -> TicTacToeSession {
        let session = TicTacToeSession(opponent: .person)
        for square in squares { _ = session.handle("\(square)") }
        return session
    }

    /// A game against the computer with both sides' moves scripted, so the
    /// position is known exactly. The squares alternate, starting with
    /// whoever moves first.
    private func againstComputer(_ squares: [Int] = [], humanStarts: Bool = true) -> TicTacToeSession {
        let session = TicTacToeSession(opponent: .computer, difficulty: .sharp, humanStarts: humanStarts)
        for (index, square) in squares.enumerated() {
            let humanToMove = (index % 2 == 0) == humanStarts
            _ = humanToMove ? session.handle("square \(square)") : session.play(computerMove: square)
        }
        return session
    }

    /// The player (X) holds the centre and middle right and can win on the
    /// middle left. The computer (O) holds both top corners and can win on
    /// the top middle. It is X's turn.
    ///
    ///     O . O
    ///     . X X
    ///     . . .
    private func bothThreatening() -> TicTacToeSession {
        againstComputer([5, 1, 6, 3])
    }

    /// Nine moves that fill the board without three in a row.
    private let drawnGame = [1, 2, 3, 5, 4, 6, 8, 7, 9]

    private func parse(_ text: String) -> TicTacToeRequest {
        TicTacToeRequest.parse(Phrase.words(text))
    }

    // MARK: Board

    func testSquareNamesAndNumbers() {
        XCTAssertEqual(TicTacToeBoard.squareNumbers.map { TicTacToeBoard.name(of: $0) },
                       ["top left", "top middle", "top right",
                        "middle left", "centre", "middle right",
                        "bottom left", "bottom middle", "bottom right"])
        XCTAssertEqual(TicTacToeBoard.square(row: 2, column: 3), 6)
        XCTAssertEqual(TicTacToeBoard.row(of: 6), 2)
        XCTAssertEqual(TicTacToeBoard.column(of: 6), 3)
        XCTAssertNil(TicTacToeBoard.square(row: 4, column: 1))
    }

    func testPlacingAndClearing() {
        var board = TicTacToeBoard()
        XCTAssertTrue(board.place(.x, on: 5))
        XCTAssertFalse(board.place(.o, on: 5), "the square is taken")
        XCTAssertFalse(board.place(.o, on: 10), "there is no such square")
        XCTAssertEqual(board[5], .x)
        XCTAssertEqual(board.markCount, 1)
        XCTAssertEqual(board.freeSquares, [1, 2, 3, 4, 6, 7, 8, 9])
        board.clear(5)
        XCTAssertNil(board[5])
        XCTAssertEqual(board, TicTacToeBoard())
    }

    func testEveryLineWins() {
        XCTAssertEqual(TicTacToeBoard.lines.count, 8)
        for line in TicTacToeBoard.lines {
            for mark in Mark.allCases {
                var board = TicTacToeBoard()
                for square in line { board.place(mark, on: square) }
                XCTAssertEqual(board.win, TicTacToeBoard.Win(mark: mark, lines: [line]), "\(line)")
                XCTAssertEqual(board.win?.squares, line)
                XCTAssertTrue(board.hasLine(of: mark))
                XCTAssertFalse(board.hasLine(of: mark.other))
            }
        }
    }

    func testTwoInARowIsNotAWin() {
        XCTAssertNil(board("XX. / OO. / ...").win)
        XCTAssertNil(TicTacToeBoard().win)
    }

    func testFullBoardWithNoLineIsADraw() {
        let board = board("XOX / XOO / OXX")
        XCTAssertTrue(board.isFull)
        XCTAssertNil(board.win)
    }

    func testOneMarkCanFinishTwoLines() {
        let win = board("XXX / XO. / XO.").win
        XCTAssertEqual(win?.lines.count, 2)
        XCTAssertEqual(win?.squares, [1, 2, 3, 4, 7])
    }

    func testWinningSquares() {
        let board = board("O.O / .XX / ...")
        XCTAssertEqual(board.winningSquares(for: .x), [4])
        XCTAssertEqual(board.winningSquares(for: .o), [2])
        XCTAssertEqual(self.board("X.. / .X. / O.O").winningSquares(for: .o), [8])
        XCTAssertEqual(TicTacToeBoard().winningSquares(for: .x), [])
    }

    // MARK: Understanding

    func testMovePhrasings() {
        let phrasings: [(String, Int)] = [
            ("top left", 1),
            ("Top left.", 1),
            ("upper right", 3),
            ("centre", 5),
            ("center", 5),
            ("the middle", 5),
            ("bottom middle", 8),
            ("top centre", 2),
            ("middle left", 4),
            ("left middle", 4),
            ("lower left corner", 7),
            ("5", 5),
            ("five", 5),
            ("square 7", 7),
            ("number nine", 9),
            ("row 2 column 3", 6),
            ("second row, first column", 4),
            ("column 1, row 3", 7),
            ("I'll take the centre please", 5),
            ("um, put my X in the top right", 3),
            ("the middle one", 5),
            ("okay, bottom right", 9),
            ("no, the top middle", 2),
            ("how about the centre", 5),
            ("one", 1),
        ]
        for (text, square) in phrasings {
            XCTAssertEqual(parse(text), .take(square: square), text)
        }
    }

    func testSoundAlikesAreNumbersOnlyWhereNothingElseFits() {
        XCTAssertEqual(parse("for"), .take(square: 4))
        XCTAssertEqual(parse("to"), .take(square: 2))
        XCTAssertEqual(parse("ate"), .take(square: 8))
        XCTAssertEqual(parse("take for"), .take(square: 4))
        XCTAssertEqual(parse("square for"), .take(square: 4))
        XCTAssertEqual(parse("I want to take 6"), .take(square: 6))
        XCTAssertEqual(parse("I want to"), .unknown)
    }

    func testHalfANameIsNotAMove() {
        XCTAssertEqual(parse("top"), .unknown)
        XCTAssertEqual(parse("left"), .unknown)
        XCTAssertEqual(parse("bottom"), .unknown)
        XCTAssertEqual(parse("the corner"), .unknown)
    }

    func testQuestionPhrasings() {
        XCTAssertEqual(parse("what's in the centre"), .readSquare(5))
        XCTAssertEqual(parse("is the top left free?"), .readSquare(1))
        XCTAssertEqual(parse("who has 5"), .readSquare(5))
        XCTAssertEqual(parse("what is on square nine"), .readSquare(9))
        XCTAssertEqual(parse("what's in row 2 column 3"), .readSquare(6))
        XCTAssertEqual(parse("read the top row"), .readRow(1))
        XCTAssertEqual(parse("read row 2"), .readRow(2))
        XCTAssertEqual(parse("bottom row"), .readRow(3))
        XCTAssertEqual(parse("what's in the left column"), .readColumn(1))
        XCTAssertEqual(parse("read column 3"), .readColumn(3))
        XCTAssertEqual(parse("what's on the right"), .readColumn(3))
        XCTAssertEqual(parse("what's free"), .freeSquares)
        XCTAssertEqual(parse("What's free?"), .freeSquares)
        XCTAssertEqual(parse("which squares are open"), .freeSquares)
        XCTAssertEqual(parse("what's left"), .freeSquares)
        XCTAssertEqual(parse("where can I go"), .freeSquares)
        XCTAssertEqual(parse("where are my marks"), .marks(.mine))
        XCTAssertEqual(parse("what do I have"), .marks(.mine))
        XCTAssertEqual(parse("where are theirs"), .marks(.theirs))
        XCTAssertEqual(parse("where are the computer's marks"), .marks(.theirs))
        XCTAssertEqual(parse("where are the O's"), .marks(.mark(.o)))
        XCTAssertEqual(parse("where is everything"), .marks(.everyone))
        XCTAssertEqual(parse("can anyone win"), .threats)
        XCTAssertEqual(parse("Can anyone win?"), .threats)
        XCTAssertEqual(parse("any threats"), .threats)
        XCTAssertEqual(parse("do I need to block"), .threats)
        XCTAssertEqual(parse("am I going to lose"), .threats)
        XCTAssertEqual(parse("where did the computer go"), .common(.lastMove))
        XCTAssertEqual(parse("how many moves have been played"), .common(.history))
        XCTAssertEqual(parse("am I X or O"), .whoAmI)
        XCTAssertEqual(parse("which one am I"), .whoAmI)
        XCTAssertEqual(parse("who won"), .gameStatus)
        XCTAssertEqual(parse("is it a draw"), .gameStatus)
        XCTAssertEqual(parse("undo"), .common(.undo))
        XCTAssertEqual(parse("last move"), .common(.lastMove))
        XCTAssertEqual(parse("read the board"), .common(.readBoard))
        XCTAssertEqual(parse("sing me a song"), .unknown)
    }

    // MARK: Moves

    func testOpeningSaysWhoYouAre() {
        let session = TicTacToeSession()
        XCTAssertEqual(session.title, "Tic-Tac-Toe")
        let opening = session.opening()
        XCTAssertEqual(opening.tone, .info)
        XCTAssertTrue(opening.text.contains("You are X and go first"), opening.text)
        XCTAssertTrue(opening.text.contains("Gentle"), opening.text)

        let second = TicTacToeSession(opponent: .computer, difficulty: .sharp, humanStarts: false)
        XCTAssertTrue(second.opening().text.contains("The computer is X and goes first. You are O."))

        let shared = TicTacToeSession(opponent: .person)
        XCTAssertTrue(shared.opening().text.contains("two players"))
    }

    func testMoveRepliesUseTheSquaresName() {
        let session = againstComputer()
        XCTAssertEqual(session.handle("5"), Reply("You took the centre.", tone: .move, boardChanged: true))
        XCTAssertEqual(session.play(computerMove: 1),
                       Reply("The computer took the top left.", tone: .move, boardChanged: true))
        XCTAssertEqual(session.handle("row 3 column 3").text, "You took the bottom right.")
        XCTAssertEqual(session.snapshot.moveCount, 3)
    }

    func testMoveRepliesBetweenTwoPeopleNameTheSides() {
        let session = twoPlayers()
        XCTAssertEqual(session.handle("the middle").text, "X took the centre. O's turn.")
        XCTAssertEqual(session.handle("upper left").text, "O took the top left. X's turn.")
    }

    func testWinningMovesSayWhereTheLineIs() {
        let across = twoPlayers([1, 4, 2, 5]).handle("top right")
        XCTAssertEqual(across.tone, .gameOver)
        XCTAssertTrue(across.boardChanged)
        XCTAssertEqual(across.text, "X took the top right. Three in a row across the top row. "
                       + "X wins! Say new game to play again.")

        let down = twoPlayers([1, 2, 4, 3]).handle("bottom left")
        XCTAssertTrue(down.text.contains("Three in a row down the left column."), down.text)

        let diagonal = twoPlayers([1, 2, 5, 3]).handle("9")
        XCTAssertTrue(diagonal.text.contains("on the diagonal from the top left to the bottom right"), diagonal.text)

        let other = twoPlayers([3, 1, 5, 2]).handle("7")
        XCTAssertTrue(other.text.contains("on the diagonal from the top right to the bottom left"), other.text)

        let session = twoPlayers([1, 4, 2, 5, 3])
        XCTAssertTrue(session.isOver)
        XCTAssertEqual(session.snapshot.winner, .x)
        XCTAssertEqual(session.snapshot.winningSquares, [1, 2, 3])
        XCTAssertFalse(session.snapshot.isDraw)
    }

    func testComputerWinIsAnnounced() {
        let session = againstComputer([1, 5, 2, 4, 9])
        let reply = session.play(computerMove: 6)
        XCTAssertEqual(reply.tone, .gameOver)
        XCTAssertEqual(reply.text, "The computer took the middle right. Three in a row across the middle row. "
                       + "The computer wins. Say new game to play again.")
        XCTAssertEqual(session.handle("whose turn is it").text,
                       "The game is over. The computer won with three in a row across the middle row. "
                       + "Say new game to play again.")
    }

    func testFullBoardIsADraw() {
        let session = twoPlayers(Array(drawnGame.dropLast()))
        XCTAssertFalse(session.isOver)
        let reply = session.handle("bottom right")
        XCTAssertEqual(reply.tone, .gameOver)
        XCTAssertEqual(reply.text, "X took the bottom right. The board is full, so the game is a draw. "
                       + "Say new game to play again.")
        XCTAssertTrue(session.snapshot.isDraw)
        XCTAssertNil(session.snapshot.winner)
        XCTAssertEqual(session.handle("who won").text,
                       "The game is over. It was a draw: the board is full. Say new game to play again.")
    }

    func testIllegalMovesExplainWhatIsPossible() {
        let session = againstComputer([5, 1])

        let mine = session.handle("centre")
        XCTAssertEqual(mine.tone, .error)
        XCTAssertEqual(mine.text, "The centre is taken: you already have it. 7 squares are free: top middle, "
                       + "top right, middle left, middle right, bottom left, bottom middle and bottom right.")

        let theirs = session.handle("top left")
        XCTAssertEqual(theirs.tone, .error)
        XCTAssertTrue(theirs.text.hasPrefix("The top left is taken: the computer has it."), theirs.text)

        let missing = session.handle("square 12")
        XCTAssertEqual(missing.tone, .error)
        XCTAssertTrue(missing.text.hasPrefix("There is no square 12. Squares are numbered 1 to 9"), missing.text)

        let offBoard = session.handle("row 4 column 1")
        XCTAssertEqual(offBoard.tone, .error)
        XCTAssertTrue(offBoard.text.hasPrefix("That square is not on the board."), offBoard.text)

        let vague = session.handle("top")
        XCTAssertEqual(vague.tone, .error)
        XCTAssertTrue(vague.text.contains("Say a square such as top left or centre"), vague.text)

        XCTAssertEqual(session.handle("").tone, .error)
        XCTAssertEqual(session.snapshot.moveCount, 2, "none of these may change the board")

        XCTAssertTrue(twoPlayers([5]).handle("5").text.hasPrefix("The centre is taken: X has it."))
    }

    func testNoMovesAfterTheGameIsOver() {
        let session = twoPlayers([1, 4, 2, 5, 3])
        let reply = session.handle("bottom right")
        XCTAssertEqual(reply.tone, .error)
        XCTAssertFalse(reply.boardChanged)
        XCTAssertTrue(reply.text.contains("The game is over."), reply.text)
        XCTAssertTrue(reply.text.contains("Say new game to play again."), reply.text)
        XCTAssertEqual(session.snapshot.moveCount, 5)
    }

    func testWhileTheComputerThinksQuestionsWorkButMovesWait() {
        let session = againstComputer([5])
        let move = session.handle("top left")
        XCTAssertEqual(move.tone, .error)
        XCTAssertTrue(move.text.contains("computer's turn"), move.text)
        XCTAssertEqual(session.handle("undo").tone, .error)
        XCTAssertEqual(session.handle("hint").tone, .error)
        XCTAssertEqual(session.snapshot.moveCount, 1)

        XCTAssertEqual(session.handle("what's in the centre").text, "The centre is yours.")
        XCTAssertEqual(session.handle("whose turn is it").text, "It is the computer's turn. You are X.")
    }

    // MARK: Questions

    func testReadTheBoard() {
        XCTAssertEqual(againstComputer().handle("read the board").text, "The board is empty.")
        XCTAssertEqual(bothThreatening().handle("Read the board").text,
                       "Top row: O, empty, O. Middle row: empty, X, X. Bottom row: empty, empty, empty.")
    }

    func testReadARowOrColumn() {
        let session = bothThreatening()
        XCTAssertEqual(session.handle("read the top row").text, "Top row: O, empty, O.")
        XCTAssertEqual(session.handle("read row 2").text, "Middle row: empty, X, X.")
        XCTAssertEqual(session.handle("what's in the left column").text, "Left column, top to bottom: O, empty, empty.")
        XCTAssertEqual(session.handle("read column 3").text, "Right column, top to bottom: O, X, empty.")
        XCTAssertEqual(session.handle("read row 5").tone, .error)
    }

    func testWhatIsOnASquare() {
        let session = bothThreatening()
        XCTAssertEqual(session.handle("what's in the centre").text, "The centre is yours.")
        XCTAssertEqual(session.handle("who has the top left?").text, "The top left is the computer's.")
        XCTAssertEqual(session.handle("is the bottom left free").text, "The bottom left is free.")
        XCTAssertEqual(session.handle("what's on square 6").text, "The middle right is yours.")
        XCTAssertEqual(session.handle("what's on square 11").tone, .error)
        XCTAssertEqual(twoPlayers([5]).handle("what's in the middle").text, "The centre has an X.")
        XCTAssertEqual(session.snapshot.moveCount, 4, "asking must not move")
    }

    func testWhatIsFree() {
        XCTAssertEqual(againstComputer().handle("what's free").text, "All 9 squares are free.")
        XCTAssertEqual(bothThreatening().handle("What's free?").text,
                       "5 squares are free: top middle, middle left, bottom left, bottom middle and bottom right.")
        XCTAssertEqual(twoPlayers(Array(drawnGame.dropLast())).handle("which squares are open").text,
                       "Only the bottom right is free.")
    }

    func testWhereTheMarksAre() {
        let session = bothThreatening()
        XCTAssertEqual(session.handle("where are my marks").text, "You have the centre and the middle right.")
        XCTAssertEqual(session.handle("where are theirs").text, "The computer has the top left and the top right.")
        XCTAssertEqual(session.handle("where are the O's").text, "The computer has the top left and the top right.")
        XCTAssertEqual(againstComputer().handle("where are my marks").text, "You have no squares yet.")
    }

    func testMyMarksMeansTheSideToMoveBetweenTwoPeople() {
        let session = twoPlayers([5, 1, 9])
        // O is to move.
        XCTAssertEqual(session.handle("where are my marks").text, "O has the top left.")
        XCTAssertEqual(session.handle("where are theirs").text, "X has the centre and the bottom right.")
        XCTAssertEqual(session.handle("where are the X's").text, "X has the centre and the bottom right.")
    }

    func testCanAnyoneWin() {
        XCTAssertEqual(againstComputer([5, 1]).handle("can anyone win").text, "Nobody can win on the next move.")
        XCTAssertEqual(bothThreatening().handle("Can anyone win?").text,
                       "You can win by taking the middle left. "
                       + "The computer can also win by taking the top middle, but you move first.")
        // Only the computer threatens.
        XCTAssertEqual(againstComputer([5, 1, 9, 3]).handle("any threats").text,
                       "The computer can win by taking the top middle, so block it.")
        // Only the player threatens.
        XCTAssertEqual(againstComputer([5, 2, 4, 9]).handle("can I win").text,
                       "You can win by taking the middle right.")
        // A fork: two ways to win, asked while the computer is thinking.
        XCTAssertEqual(againstComputer([1, 2, 5, 9, 4]).handle("threats").text,
                       "You can win by taking the middle right or the bottom left, and only one can be blocked.")
        // Between two people the marks are named.
        XCTAssertEqual(twoPlayers([5, 1, 9, 3]).handle("can anyone win").text,
                       "O can win by taking the top middle, so X must block it.")
    }

    func testLastMoveAndHistory() {
        let fresh = againstComputer()
        XCTAssertEqual(fresh.handle("last move").text, "No moves have been played yet.")
        XCTAssertEqual(fresh.handle("history").text, "No moves have been played yet.")

        let session = bothThreatening()
        XCTAssertEqual(session.handle("what was the last move").text,
                       "The computer took the top right. Before that, you took the middle right.")
        XCTAssertEqual(session.handle("history").text,
                       "4 moves so far: you centre, computer top left, you middle right, computer top right.")
        XCTAssertEqual(twoPlayers([5, 1]).handle("moves so far").text, "2 moves so far: X centre, O top left.")
    }

    func testSummaryAndTurn() {
        let session = bothThreatening()
        XCTAssertEqual(session.handle("summary").text,
                       "It is your turn, move 5. You have the centre and the middle right. "
                       + "The computer has the top left and the top right. "
                       + "You can win by taking the middle left. "
                       + "The computer can also win by taking the top middle, but you move first.")
        XCTAssertEqual(session.handle("whose turn is it").text, "It is your turn. You are X.")
        XCTAssertEqual(session.handle("am I X or O").text, "You are X. The computer is O.")
        XCTAssertEqual(againstComputer().handle("summary").text, "It is your turn, move 1. The board is empty.")
        XCTAssertEqual(twoPlayers([5]).handle("whose turn").text, "It is O's turn.")
        XCTAssertEqual(twoPlayers([5]).handle("what's going on").text,
                       "It is O's turn, move 2. O has no squares yet. X has the centre. "
                       + "Nobody can win on the next move.")
    }

    func testHelpAndRepeat() {
        let session = againstComputer()
        let help = session.handle("help")
        XCTAssertEqual(help.tone, .info)
        XCTAssertTrue(help.text.contains("top left"), help.text)

        let move = session.handle("centre")
        let again = session.handle("say that again")
        XCTAssertEqual(again.text, move.text)
        XCTAssertEqual(again.tone, move.tone)
        XCTAssertFalse(again.boardChanged, "repeating must not look like a second move")
        XCTAssertEqual(session.snapshot.moveCount, 1)
    }

    // MARK: Warnings

    func testComputerThreatIsAnnounced() {
        let session = againstComputer([5, 1, 6])
        let reply = session.play(computerMove: 3)
        XCTAssertEqual(reply.tone, .alert)
        XCTAssertEqual(reply.text, "The computer took the top right. "
                       + "Careful: the computer can win by taking the top middle.")
    }

    func testThreatAnnouncementCanBeTurnedOff() {
        let session = againstComputer([5, 1, 6])
        session.announceThreats = false
        let reply = session.play(computerMove: 3)
        XCTAssertEqual(reply.tone, .move)
        XCTAssertEqual(reply.text, "The computer took the top right.")
    }

    // MARK: Undo

    func testUndoAgainstTheComputerTakesBackBothMoves() {
        let session = againstComputer([5, 1])
        let reply = session.handle("undo")
        XCTAssertEqual(reply, Reply("Took back the computer's mark from the top left and your mark from the centre. "
                                    + "It is your turn again.", boardChanged: true))
        XCTAssertEqual(session.snapshot.board, TicTacToeBoard())
        XCTAssertEqual(session.snapshot.moveCount, 0)
        XCTAssertNil(session.computerMoveJob(), "it is the player's turn again")

        let nothing = session.handle("undo")
        XCTAssertEqual(nothing.tone, .error)
        XCTAssertFalse(nothing.boardChanged)
    }

    func testUndoAfterThePlayerWinsTakesBackOnlyThatMove() {
        let session = againstComputer([5, 1, 6, 3, 4])
        XCTAssertTrue(session.isOver)
        let reply = session.handle("take that back")
        XCTAssertEqual(reply.text, "Took back your mark from the middle left. It is your turn again.")
        XCTAssertFalse(session.isOver)
        XCTAssertEqual(session.snapshot.moveCount, 4)
        XCTAssertEqual(session.snapshot.turn, .x)
    }

    func testUndoBeforeThePlayerHasMoved() {
        let session = againstComputer([5], humanStarts: false)
        let reply = session.handle("undo")
        XCTAssertEqual(reply.tone, .error)
        XCTAssertTrue(reply.text.contains("you have not moved yet"), reply.text)
        XCTAssertEqual(session.snapshot.moveCount, 1)
    }

    func testUndoBetweenTwoPeopleTakesBackOneMove() {
        let session = twoPlayers([5, 1])
        let reply = session.handle("undo")
        XCTAssertEqual(reply, Reply("Took back O's mark from the top left. It is O's turn again.", boardChanged: true))
        XCTAssertEqual(session.snapshot.moveCount, 1)
        XCTAssertEqual(session.snapshot.turn, .o)
        XCTAssertEqual(session.handle("undo").text, "Took back X's mark from the centre. It is X's turn again.")
        XCTAssertEqual(session.handle("undo").tone, .error)
    }

    // MARK: New game

    func testNewGameOnAnUntouchedBoardNeedsNoConfirmation() {
        let reply = againstComputer().handle("new game")
        XCTAssertEqual(reply, Reply("New game. You are X and go first.", boardChanged: true))
    }

    func testNewGameAsksFirstAndYesStartsIt() {
        let session = againstComputer([5, 1])
        let question = session.handle("new game")
        XCTAssertEqual(question, Reply("Start a new game? Say yes or no.", tone: .question))
        XCTAssertEqual(session.snapshot.moveCount, 2, "nothing happens until the answer")
        XCTAssertEqual(session.suggestions, ["Yes", "No", "Repeat"])

        let started = session.handle("yes")
        XCTAssertTrue(started.boardChanged)
        XCTAssertTrue(started.text.hasPrefix("New game."), started.text)
        XCTAssertEqual(session.snapshot.board, TicTacToeBoard())
        XCTAssertEqual(session.snapshot.moveCount, 0)
    }

    func testNewGameCanBeDeclined() {
        let session = againstComputer([5, 1])
        _ = session.handle("start over")
        let reply = session.handle("no")
        XCTAssertEqual(reply.tone, .info)
        XCTAssertFalse(reply.boardChanged)
        XCTAssertTrue(reply.text.contains("carries on"), reply.text)
        XCTAssertEqual(session.snapshot.moveCount, 2)
    }

    func testAnUnrelatedRequestCancelsTheNewGameQuestion() {
        let session = againstComputer([5, 1])
        _ = session.handle("new game")
        XCTAssertEqual(session.handle("what's in the centre").text, "The centre is yours.")

        // The question is gone, so a late "yes" must not wipe the board.
        let late = session.handle("yes")
        XCTAssertEqual(late.tone, .error)
        XCTAssertEqual(session.snapshot.moveCount, 2)
    }

    func testAMoveCancelsTheNewGameQuestionAndIsPlayed() {
        let session = againstComputer([5, 1])
        _ = session.handle("new game")
        XCTAssertEqual(session.handle("bottom right").text, "You took the bottom right.")
        XCTAssertEqual(session.snapshot.moveCount, 3)
    }

    func testRepeatKeepsTheQuestionOpen() {
        let session = againstComputer([5, 1])
        let question = session.handle("new game")
        let again = session.handle("repeat")
        XCTAssertEqual(again.text, question.text)
        XCTAssertEqual(again.tone, .question)
        XCTAssertTrue(session.handle("yes").boardChanged)
        XCTAssertEqual(session.snapshot.moveCount, 0)
    }

    func testNewGameAfterTheGameIsOverStartsAtOnce() {
        let session = twoPlayers([1, 4, 2, 5, 3])
        XCTAssertEqual(session.handle("play again"), Reply("New game. X goes first.", boardChanged: true))
        XCTAssertFalse(session.isOver)
    }

    // MARK: Hint

    func testHintNamesAWinAndYesPlaysIt() {
        let session = bothThreatening()
        XCTAssertEqual(session.handle("hint"), Reply("Take the middle left to win. Say yes to play it."))
        XCTAssertEqual(session.snapshot.moveCount, 4, "a hint does not move")

        let played = session.handle("yes")
        XCTAssertEqual(played.tone, .gameOver)
        XCTAssertEqual(played.text, "You took the middle left. Three in a row across the middle row. "
                       + "You win! Say new game to play again.")
        XCTAssertEqual(session.snapshot.winner, .x)
    }

    func testHintNamesABlock() {
        let session = againstComputer([5, 1, 9, 3])
        XCTAssertEqual(session.handle("what should I do").text,
                       "Take the top middle to block the computer. Say yes to play it.")
        XCTAssertEqual(session.handle("play it").text, "You took the top middle.")
    }

    func testHintOnAnEmptyBoardSuggestsTheCentreAndYesPlaysIt() {
        let session = againstComputer()
        XCTAssertEqual(session.handle("give me a hint").text, "Try the centre. Say yes to play it.")
        XCTAssertEqual(session.handle("yes please").text, "You took the centre.")
        XCTAssertEqual(session.snapshot.lastMove, 5)
    }

    func testHintCanBeDeclinedOrIgnored() {
        let session = againstComputer()
        _ = session.handle("hint")
        XCTAssertEqual(session.handle("no").tone, .info)
        XCTAssertEqual(session.snapshot.moveCount, 0)

        _ = session.handle("hint")
        XCTAssertEqual(session.handle("top left").text, "You took the top left.")
        XCTAssertEqual(session.snapshot.moveCount, 1)
    }

    func testYesWithNothingToConfirm() {
        let reply = againstComputer().handle("yes")
        XCTAssertEqual(reply.tone, .error)
        XCTAssertTrue(reply.text.contains("Say a square"), reply.text)
    }

    // MARK: The computer's turn

    func testComputerMoveJobOnlyExistsOnTheComputersTurn() {
        let session = TicTacToeSession(opponent: .computer, difficulty: .sharp)
        XCTAssertNil(session.computerMoveJob(), "the player moves first")

        _ = session.handle("top left")
        guard let job = session.computerMoveJob() else { return XCTFail("the computer should be thinking") }
        // The only reply to a corner that does not lose is the centre.
        XCTAssertEqual(job(), 5)

        let reply = session.play(computerMove: 5)
        XCTAssertEqual(reply, Reply("The computer took the centre.", tone: .move, boardChanged: true))
        XCTAssertNil(session.computerMoveJob(), "back to the player")
    }

    func testComputerMovesFirstWhenThePlayerIsO() {
        let session = TicTacToeSession(opponent: .computer, difficulty: .gentle, humanStarts: false)
        XCTAssertEqual(session.snapshot.you, .o)
        guard let job = session.computerMoveJob(), let square = job() else {
            return XCTFail("the computer should open the game")
        }
        XCTAssertEqual(session.handle("centre").tone, .error, "the player has to wait")
        XCTAssertTrue(session.play(computerMove: square).boardChanged)
        XCTAssertEqual(session.snapshot.board[square], .x)
        XCTAssertEqual(session.snapshot.turn, .o)
    }

    func testNoComputerMoveJobBetweenTwoPeopleOrAfterTheGame() {
        let shared = twoPlayers([5])
        XCTAssertNil(shared.computerMoveJob())
        XCTAssertNil(shared.snapshot.you)

        let lost = againstComputer([1, 5, 2, 4, 9, 6])
        XCTAssertTrue(lost.isOver)
        XCTAssertNil(lost.computerMoveJob())
    }

    func testALateComputerMoveIsNotPlayed() {
        let session = againstComputer([5, 1])
        let reply = session.play(computerMove: 9)
        XCTAssertEqual(reply.tone, .error)
        XCTAssertFalse(reply.boardChanged)
        XCTAssertEqual(session.snapshot.moveCount, 2)
    }

    // MARK: Snapshot and suggestions

    func testSnapshotDescribesTheBoard() {
        let snapshot = bothThreatening().snapshot
        XCTAssertEqual(snapshot.board.marks, [.o, nil, .o, nil, .x, .x, nil, nil, nil])
        XCTAssertEqual(snapshot.turn, .x)
        XCTAssertEqual(snapshot.you, .x)
        XCTAssertEqual(snapshot.lastMove, 3)
        XCTAssertEqual(snapshot.moveCount, 4)
        XCTAssertNil(snapshot.winner)
        XCTAssertEqual(snapshot.winningSquares, [])
        XCTAssertFalse(snapshot.isOver)

        XCTAssertEqual(snapshot.label(for: 5), "Centre, your X")
        XCTAssertEqual(snapshot.label(for: 3), "Top right, the computer's O, last move")
        XCTAssertEqual(snapshot.label(for: 7), "Bottom left, empty")

        let won = twoPlayers([1, 4, 2, 5, 3]).snapshot
        XCTAssertEqual(won.label(for: 3), "Top right, X, winning line, last move")
        XCTAssertEqual(won.label(for: 4), "Middle left, O")
    }

    func testEverySuggestionIsUnderstood() {
        let moments: [(squares: [Int], shared: Bool, humanStarts: Bool)] = [
            ([], false, true),                  // nothing played
            ([5], false, true),                 // the computer's turn
            ([5, 1], false, true),              // mid-game
            ([5], false, false),                // the computer opened
            ([5, 1, 9], true, true),
            ([1, 4, 2, 5, 3], true, true),      // game over
        ]
        for moment in moments {
            func make() -> TicTacToeSession {
                moment.shared ? twoPlayers(moment.squares)
                              : againstComputer(moment.squares, humanStarts: moment.humanStarts)
            }
            let suggestions = make().suggestions
            XCTAssertTrue((3...5).contains(suggestions.count), "\(suggestions)")
            for suggestion in suggestions {
                // A fresh session each time, so one suggestion cannot affect the next.
                XCTAssertNotEqual(make().handle(suggestion).tone, .error, suggestion)
            }
        }
    }

    // MARK: Computer play

    func testSharpAndSteadyTakeAnImmediateWin() {
        let board = board("XX. / OO. / ...")
        for difficulty in [Difficulty.steady, .sharp] {
            for seed in 0..<5 {
                var rng = SeededGenerator(seed: UInt64(seed))
                XCTAssertEqual(TicTacToeAI.chooseSquare(on: board, for: .x, difficulty: difficulty, using: &rng), 3)
                XCTAssertEqual(TicTacToeAI.chooseSquare(on: board, for: .o, difficulty: difficulty, using: &rng), 6)
            }
        }
    }

    func testSharpAndSteadyBlockAnImmediateLoss() {
        let board = board("XX. / .O. / ...")
        for difficulty in [Difficulty.steady, .sharp] {
            for seed in 0..<5 {
                var rng = SeededGenerator(seed: UInt64(seed))
                XCTAssertEqual(TicTacToeAI.chooseSquare(on: board, for: .o, difficulty: difficulty, using: &rng), 3)
            }
        }
    }

    func testGentleAlwaysTakesAWinButOftenMissesABlock() {
        let winning = board("XX. / OO. / ...")
        let losing = board("XX. / .O. / ...")
        var blocks = 0
        for seed in 0..<100 {
            var rng = SeededGenerator(seed: UInt64(seed))
            XCTAssertEqual(TicTacToeAI.chooseSquare(on: winning, for: .o, difficulty: .gentle, using: &rng), 6)
            if TicTacToeAI.chooseSquare(on: losing, for: .o, difficulty: .gentle, using: &rng) == 3 { blocks += 1 }
        }
        XCTAssertGreaterThan(blocks, 30)
        XCTAssertLessThan(blocks, 90, "gentle should leave the player real chances")
    }

    func testPerfectPlayKnowsTheOpeningTheory() {
        // Every first move draws with best play.
        XCTAssertEqual(TicTacToeAI.perfectSquares(on: TicTacToeBoard(), for: .x), Array(1...9))
        // Against a corner, only the centre holds the draw.
        XCTAssertEqual(TicTacToeAI.perfectSquares(on: board("X.. / ... / ..."), for: .o), [5])
        // Against the centre, only a corner does.
        XCTAssertEqual(TicTacToeAI.perfectSquares(on: board("... / .X. / ..."), for: .o), [1, 3, 7, 9])
        // A fork wins: here the bottom left makes two threats at once.
        XCTAssertEqual(TicTacToeAI.perfectSquares(on: board("X.. / .O. / ..X"), for: .o).sorted(), [2, 4, 6, 8])
    }

    func testSteadyFallsForAForkThatSharpAvoids() {
        // X holds opposite corners and O the centre. O must answer on an
        // edge; a corner lets X make two threats at once.
        let board = board("X.. / .O. / ..X")
        for seed in 0..<10 {
            var rng = SeededGenerator(seed: UInt64(seed))
            let sharp = TicTacToeAI.chooseSquare(on: board, for: .o, difficulty: .sharp, using: &rng)
            XCTAssertTrue([2, 4, 6, 8].contains(sharp ?? 0), "sharp played \(String(describing: sharp))")
            let steady = TicTacToeAI.chooseSquare(on: board, for: .o, difficulty: .steady, using: &rng)
            XCTAssertTrue([3, 7].contains(steady ?? 0), "steady played \(String(describing: steady))")
        }
    }

    func testSameSeedGivesTheSameMove() {
        for difficulty in Difficulty.allCases {
            var first = SeededGenerator(seed: 42)
            var second = SeededGenerator(seed: 42)
            XCTAssertEqual(TicTacToeAI.chooseSquare(on: TicTacToeBoard(), for: .x, difficulty: difficulty, using: &first),
                           TicTacToeAI.chooseSquare(on: TicTacToeBoard(), for: .x, difficulty: difficulty, using: &second))
        }
    }

    func testNoMoveOnAFullBoard() {
        let board = board("XOX / XOO / OXX")
        var rng = SeededGenerator(seed: 1)
        XCTAssertNil(TicTacToeAI.chooseSquare(on: board, for: .x, difficulty: .sharp, using: &rng))
        XCTAssertNil(TicTacToeAI.bestSquare(on: board, for: .x))
    }

    /// Plays one whole game between two levels and returns the final board.
    private func playOut(x: Difficulty, o: Difficulty, seed: UInt64) -> TicTacToeBoard {
        var rng = SeededGenerator(seed: seed)
        var board = TicTacToeBoard()
        var mark = Mark.x
        while board.win == nil, !board.isFull {
            let square = TicTacToeAI.chooseSquare(on: board, for: mark, difficulty: mark == .x ? x : o, using: &rng)
            guard let square, board.place(mark, on: square) else {
                XCTFail("illegal move \(String(describing: square))")
                break
            }
            mark = mark.other
        }
        return board
    }

    func testSharpAgainstSharpIsAlwaysADraw() {
        for seed in 0..<10 {
            let board = playOut(x: .sharp, o: .sharp, seed: UInt64(seed))
            XCTAssertTrue(board.isFull, "seed \(seed)")
            XCTAssertNil(board.win, "seed \(seed)")
        }
    }

    func testSharpNeverLoses() {
        for seed in 0..<12 {
            for weaker in [Difficulty.gentle, .steady] {
                XCTAssertNotEqual(playOut(x: .sharp, o: weaker, seed: UInt64(seed)).win?.mark, .o, "seed \(seed)")
                XCTAssertNotEqual(playOut(x: weaker, o: .sharp, seed: UInt64(seed)).win?.mark, .x, "seed \(seed)")
            }
        }
    }

    func testGentleCanBeBeaten() {
        var losses = 0
        for seed in 0..<20 where playOut(x: .sharp, o: .gentle, seed: UInt64(seed)).win?.mark == .x {
            losses += 1
        }
        XCTAssertGreaterThan(losses, 5)
    }

    func testSharpOpeningMoveIsQuick() {
        var rng = SeededGenerator(seed: 5)
        let started = Date()
        let square = TicTacToeAI.chooseSquare(on: TicTacToeBoard(), for: .x, difficulty: .sharp, using: &rng)
        let elapsed = Date().timeIntervalSince(started)
        print("Tic-Tac-Toe, sharp opening move: \(elapsed) s")
        // Perfect play opens in the centre or a corner.
        XCTAssertTrue([1, 3, 5, 7, 9].contains(square ?? 0))
        XCTAssertLessThan(elapsed, 0.5, "the sharp level must stay quick in a debug build")
    }
}
