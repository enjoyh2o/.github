import XCTest
@testable import TableTalkCore

/// Counts every position reachable in `depth` half-moves. Comparing these
/// counts with published values is the standard way to prove a chess move
/// generator follows every rule (castling, en passant, promotion, pins...).
private func perft(_ position: ChessPosition, _ depth: Int) -> Int {
    if depth == 0 { return 1 }
    let moves = position.legalMoves()
    if depth == 1 { return moves.count }
    return moves.reduce(0) { $0 + perft(position.applying($1), depth - 1) }
}

final class ChessRulesTests: XCTestCase {

    func testPerftFromTheStartingPosition() {
        XCTAssertEqual(perft(.start, 1), 20)
        XCTAssertEqual(perft(.start, 2), 400)
        XCTAssertEqual(perft(.start, 3), 8_902)
    }

    func testPerftKiwipete() throws {
        // A position rich in castling, pins, en passant and promotions.
        let p = try XCTUnwrap(ChessPosition(fen: "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"))
        XCTAssertEqual(perft(p, 1), 48)
        XCTAssertEqual(perft(p, 2), 2_039)
        XCTAssertEqual(perft(p, 3), 97_862)
    }

    func testPerftEndgameWithEnPassantPins() throws {
        let p = try XCTUnwrap(ChessPosition(fen: "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1"))
        XCTAssertEqual(perft(p, 1), 14)
        XCTAssertEqual(perft(p, 2), 191)
        XCTAssertEqual(perft(p, 3), 2_812)
        XCTAssertEqual(perft(p, 4), 43_238)
    }

    func testPerftPromotionsAndChecks() throws {
        let p = try XCTUnwrap(ChessPosition(fen: "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1"))
        XCTAssertEqual(perft(p, 1), 6)
        XCTAssertEqual(perft(p, 2), 264)
        XCTAssertEqual(perft(p, 3), 9_467)
    }

    func testPerftPositionFive() throws {
        let p = try XCTUnwrap(ChessPosition(fen: "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8"))
        XCTAssertEqual(perft(p, 1), 44)
        XCTAssertEqual(perft(p, 2), 1_486)
        XCTAssertEqual(perft(p, 3), 62_379)
    }

    func testFenRoundTrips() throws {
        let fens = [
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
            "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 b - - 3 40",
            "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2",
        ]
        for fen in fens {
            XCTAssertEqual(try XCTUnwrap(ChessPosition(fen: fen)).fen, fen)
        }
        XCTAssertNil(ChessPosition(fen: "not a position"))
        XCTAssertNil(ChessPosition(fen: "8/8/8/8/8/8/8 w - - 0 1"))
    }

    func testSquareNames() {
        XCTAssertEqual(Square("a1")?.index, 0)
        XCTAssertEqual(Square("h8")?.index, 63)
        XCTAssertEqual(Square("e4")?.name, "e4")
        XCTAssertNil(Square("i9"))
        XCTAssertNil(Square("e"))
    }

    func testNotationAndCheckmate() {
        // Fool's mate.
        var game = ChessGame()
        for text in ["f2f3", "e7e5", "g2g4", "d8h4"] {
            let move = game.position.legalMoves().first { $0.coordinates == text }!
            game.play(move)
        }
        XCTAssertEqual(game.history.map(\.notation), ["f3", "e5", "g4", "Qh4#"])
        XCTAssertEqual(game.outcome, .checkmate(winner: .black))
        XCTAssertTrue(game.history.last!.isCheckmate)
    }

    func testNotationDisambiguatesAndMarksSpecialMoves() throws {
        // Two knights can reach d2; castling and en passant are available.
        let p = try XCTUnwrap(ChessPosition(fen: "r3k2r/8/8/3pP3/8/1N3N2/8/R3K2R w KQkq d6 0 1"))
        let legal = p.legalMoves()
        func notation(_ coordinates: String) -> String {
            let move = legal.first { $0.coordinates == coordinates }!
            return ChessNotation.write(move, in: p, legal: legal)
        }
        XCTAssertEqual(notation("b3d2"), "Nbd2")
        XCTAssertEqual(notation("f3d2"), "Nfd2")
        XCTAssertEqual(notation("e1g1"), "O-O")
        XCTAssertEqual(notation("e1c1"), "O-O-O")
        XCTAssertEqual(notation("e5d6"), "exd6")

        var game = ChessGame(position: p)
        let played = game.play(legal.first { $0.coordinates == "e5d6" }!)
        XCTAssertTrue(played.isEnPassant)
        XCTAssertEqual(played.captured, Piece(color: .black, kind: .pawn))
        XCTAssertNil(game.position[Square("d5")!])
    }

    func testUndoRestoresEverything() {
        var game = ChessGame()
        let before = game.position
        game.play(game.position.legalMoves().first { $0.coordinates == "e2e4" }!)
        XCTAssertNotEqual(game.position, before)
        XCTAssertEqual(game.undo()?.notation, "e4")
        XCTAssertEqual(game.position, before)
        XCTAssertNil(game.undo())
    }

    func testStalemateAndInsufficientMaterial() throws {
        let stalemate = try XCTUnwrap(ChessPosition(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"))
        XCTAssertEqual(ChessGame(position: stalemate).outcome, .draw(.stalemate))
        let bare = try XCTUnwrap(ChessPosition(fen: "7k/8/6K1/8/8/8/8/5B2 w - - 0 1"))
        XCTAssertEqual(ChessGame(position: bare).outcome, .draw(.insufficientMaterial))
    }

    func testThreefoldRepetition() {
        var game = ChessGame()
        let shuffle = ["g1f3", "g8f6", "f3g1", "f6g8"]
        for _ in 0..<2 {
            for text in shuffle {
                XCTAssertNil(game.outcome)
                game.play(game.position.legalMoves().first { $0.coordinates == text }!)
            }
        }
        XCTAssertEqual(game.outcome, .draw(.repetition))
    }

    func testAttackersAreListedCheapestFirst() throws {
        let p = try XCTUnwrap(ChessPosition(fen: "4k3/8/8/3q4/4P3/2N5/8/3RK3 w - - 0 1"))
        let attackers = p.attackers(of: Square("d5")!, by: .white).map(\.name)
        XCTAssertEqual(attackers, ["e4", "c3", "d1"])
        XCTAssertTrue(p.isAttacked(Square("d1")!, by: .black))
        XCTAssertFalse(p.isAttacked(Square("a1")!, by: .black))
    }
}
