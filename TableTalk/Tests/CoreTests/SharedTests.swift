import XCTest
@testable import TableTalkCore

final class SharedTests: XCTestCase {

    func testListJoinsLikeSpeech() {
        XCTAssertEqual(Phrase.list([]), "")
        XCTAssertEqual(Phrase.list(["a3"]), "a3")
        XCTAssertEqual(Phrase.list(["a3", "d2"]), "a3 and d2")
        XCTAssertEqual(Phrase.list(["a3", "d2", "f1"], conjunction: "or"), "a3, d2 or f1")
    }

    func testWordsStripPunctuation() {
        XCTAssertEqual(Phrase.words("What's on E-4?"), ["whats", "on", "e", "4"])
    }

    func testSquaresAreSpokenUnambiguously() {
        XCTAssertEqual(SpeechFormatter.spoken("Knight to a3."), "Knight to A 3.")
        XCTAssertEqual(SpeechFormatter.spoken("a3 and d2", naming: .nato), "Alpha 3 and Delta 2")
        XCTAssertEqual(SpeechFormatter.spoken("Pawn takes on e5", naming: .fide), "Pawn takes on Eva 5")
        XCTAssertEqual(SpeechFormatter.spoken("the a-file"), "the A file")
        // Ordinary words are left alone.
        XCTAssertEqual(SpeechFormatter.spoken("a pawn is ahead by 3"), "a pawn is ahead by 3")
    }

    func testCommonIntents() {
        XCTAssertEqual(CommonIntent.parse(Phrase.words("Undo")), .undo)
        XCTAssertEqual(CommonIntent.parse(Phrase.words("take that back")), .undo)
        XCTAssertEqual(CommonIntent.parse(Phrase.words("What can I say?")), .help)
        XCTAssertEqual(CommonIntent.parse(Phrase.words("say that again")), .repeatLast)
        XCTAssertEqual(CommonIntent.parse(Phrase.words("yes")), .yes)
        XCTAssertEqual(CommonIntent.parse(Phrase.words("play it")), .yes)
        XCTAssertEqual(CommonIntent.parse(Phrase.words("never mind")), .no)
        XCTAssertEqual(CommonIntent.parse(Phrase.words("give me a hint")), .hint)
        XCTAssertEqual(CommonIntent.parse(Phrase.words("what's going on")), .summary)
        XCTAssertNil(CommonIntent.parse(Phrase.words("knight to f3")))
    }
}
