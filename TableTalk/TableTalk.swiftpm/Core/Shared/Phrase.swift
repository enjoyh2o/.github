import Foundation

/// Small helpers for building sentences and for reading loose, spoken input.
enum Phrase {

    // MARK: Building sentences

    /// Joins items the way a person would say them: "a", "a and b", "a, b and c".
    static func list(_ items: [String], conjunction: String = "and") -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) \(conjunction) \(items[1])"
        default:
            let head = items.dropLast().joined(separator: ", ")
            return "\(head) \(conjunction) \(items[items.count - 1])"
        }
    }

    /// "1 pawn", "2 pawns".
    static func count(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        n == 1 ? "1 \(singular)" : "\(n) \(plural ?? singular + "s")"
    }

    /// Upper-cases the first letter and leaves the rest alone.
    static func capitalized(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }

    // MARK: Reading input

    /// Lower-cases, drops apostrophes, turns every other symbol into a space
    /// and splits into words. "What's on E-4?" becomes ["whats", "on", "e", "4"].
    static func words(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in text.lowercased() {
            if ch == "'" || ch == "\u{2019}" { continue }
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if !current.isEmpty {
                out.append(current)
                current = ""
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// Number words a speech recogniser is likely to hand us, including the
    /// homophones it confuses them with ("to", "for", "ate").
    static let numberWords: [String: Int] = [
        "zero": 0,
        "one": 1, "won": 1,
        "two": 2, "to": 2, "too": 2,
        "three": 3, "tree": 3,
        "four": 4, "for": 4, "fore": 4,
        "five": 5,
        "six": 6,
        "seven": 7,
        "eight": 8, "ate": 8,
        "nine": 9,
        "ten": 10,
    ]

    /// Number words that are never anything but a number.
    static let safeNumberWords: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
    ]

    static let ordinalWords: [String: Int] = [
        "first": 1, "1st": 1,
        "second": 2, "2nd": 2,
        "third": 3, "3rd": 3,
        "fourth": 4, "4th": 4,
        "fifth": 5, "5th": 5,
        "sixth": 6, "6th": 6,
        "seventh": 7, "7th": 7,
        "eighth": 8, "8th": 8,
        "ninth": 9, "9th": 9,
    ]

    /// A whole number from a digit string, an unambiguous number word or an ordinal.
    static func number(_ word: String) -> Int? {
        if let n = Int(word) { return n }
        if let n = safeNumberWords[word] { return n }
        return ordinalWords[word]
    }

    /// Like `number(_:)` but also accepts the homophones ("to", "for", "ate").
    /// Only use this where a number is the only thing that makes sense.
    static func looseNumber(_ word: String) -> Int? {
        number(word) ?? numberWords[word]
    }
}

/// Requests that mean the same thing in every game.
enum CommonIntent: Equatable, Sendable {
    case yes, no
    case help, repeatLast, hint, undo, newGame
    case lastMove, history, turn, readBoard, summary

    /// Recognises a common request from already-normalised words, or nil.
    static func parse(_ w: [String]) -> CommonIntent? {
        guard !w.isEmpty else { return nil }
        let text = w.joined(separator: " ")
        func has(_ s: String) -> Bool { w.contains(s) }
        func says(_ phrase: String) -> Bool { (" " + text + " ").contains(" " + phrase + " ") }

        // Short answers.
        if w.count <= 3 {
            let yes: Set<String> = ["yes", "yeah", "yep", "yup", "sure", "ok", "okay", "confirm", "correct", "please"]
            let no: Set<String> = ["no", "nope", "nah", "cancel", "stop", "nevermind"]
            if says("play it") || says("do it") || says("go ahead") || says("yes please") { return .yes }
            if says("never mind") || says("no thanks") { return .no }
            if w.count <= 2, let first = w.first {
                if yes.contains(first) { return .yes }
                if no.contains(first) { return .no }
            }
        }

        if says("new game") || says("start over") || says("start again") || says("restart")
            || says("play again") || says("another game") || has("reset") { return .newGame }
        if has("undo") || says("take back") || says("take that back") || says("take it back")
            || has("takeback") || says("go back") { return .undo }
        if has("repeat") || says("say that again") || says("say it again") || says("come again")
            || text == "again" || text == "pardon" || text == "sorry" || text == "what" { return .repeatLast }
        if has("hint") || has("suggest") || has("suggestion") || says("best move") || says("good move")
            || says("what should i play") || says("what should i do") || says("what do i do")
            || says("what would you play") || says("help me") { return .hint }
        if has("help") || says("what can i say") || says("what can i ask") || has("commands")
            || has("instructions") || says("how do i play") || says("how does this work") { return .help }
        if says("last move") || says("what happened") || says("what did") || says("previous move")
            || says("what was played") || says("what was that") { return .lastMove }
        if has("history") || says("moves so far") || says("move list") || says("read the moves")
            || says("all the moves") || says("list of moves") { return .history }
        if says("whose turn") || says("whos turn") || says("who is to move") || says("whose move")
            || says("is it my turn") || says("my turn") || says("who goes") { return .turn }
        if says("read the board") || says("read board") || says("whole board") || says("entire board")
            || says("read everything") || says("describe the board") || says("read out the board") { return .readBoard }
        if has("summary") || has("summarize") || has("summarise") || has("overview") || has("situation")
            || has("recap") || says("describe the position") || says("describe position")
            || says("whats going on") || says("what is going on") || says("where are we")
            || says("catch me up") || says("where do things stand") || text == "describe" { return .summary }
        return nil
    }
}
