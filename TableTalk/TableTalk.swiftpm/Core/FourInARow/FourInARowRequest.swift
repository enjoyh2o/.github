import Foundation

/// What the player asked for in Four in a Row, once their words are understood.
///
/// Understanding is kept apart from the session so that it is a pure function
/// of the words: easy to read, and easy to test against many phrasings.
enum FourInARowRequest: Equatable, Sendable {

    /// Whose pieces a question is about.
    enum Owner: Equatable, Sendable {
        case mine, theirs, everyone
        case side(FourInARowBoard.Side)
    }

    /// Drop a piece. The column may not exist; the session explains if so.
    case drop(column: Int)
    /// A request every game shares, such as undo or help.
    case common(CommonIntent)
    case readColumn(Int)
    case readRow(Int)
    case readCell(column: Int, row: Int)
    case heights
    case openColumns
    case threats
    case pieces(Owner)
    case gameStatus
    case whoAmI
    case unknown

    /// Works out what was asked from words already normalised by `Phrase.words`.
    ///
    /// A move is looked for first, and only counts when every word fits one.
    /// That lets "okay, four" play a piece, while "what did the computer play
    /// in column four?" stays a question.
    static func parse(_ words: [String]) -> FourInARowRequest {
        if let column = columnToDropIn(words) { return .drop(column: column) }
        if let common = CommonIntent.parse(words) { return .common(common) }
        return question(words)
    }

    // MARK: Moves

    /// Small words that carry no meaning of their own.
    private static let politeWords: Set<String> = [
        "please", "thanks", "thank", "you", "um", "uh", "er", "erm", "hmm", "ok", "okay",
        "yes", "yeah", "no", "so", "well", "now", "then", "and", "just",
    ]

    /// Words that lead straight up to a column: "play 4", "drop in 4".
    private static let directWords: Set<String> = [
        "play", "drop", "put", "place", "go", "choose", "pick", "take", "select", "try", "use",
        "in", "into", "column", "col", "number", "slot",
    ]

    /// The other words a request to move may contain.
    private static let fillerWords: Set<String> = [
        "i", "ill", "id", "im", "lets", "let", "me", "us", "we", "will", "would", "like", "want",
        "wanna", "gonna", "going", "think", "guess", "maybe", "how", "about", "my", "a", "an", "the",
        "it", "this", "that", "piece", "disc", "disk", "checker", "counter", "chip", "token",
        "on", "onto", "at", "to", "for", "down", "of",
    ]

    private static let middleWords: Set<String> = ["middle", "centre", "center"]

    /// Words that turn "left" or "right" into a column: "far left", "right hand side".
    private static let edgeWords: Set<String> = ["far", "most", "hand", "side", "edge", "end", "column", "col"]

    private static let placeWords: Set<String> = middleWords.union(edgeWords)
        .union(["left", "right", "leftmost", "rightmost", "last"])

    /// The column a move names, or nil if the words are not simply a move.
    private static func columnToDropIn(_ words: [String]) -> Int? {
        let w = droppingPronounOne(words)
        let isMoveWord: (String) -> Bool = { word in
            politeWords.contains(word) || directWords.contains(word) || fillerWords.contains(word)
                || placeWords.contains(word) || Phrase.looseNumber(word) != nil
        }
        guard w.allSatisfy(isMoveWord) else { return nil }

        // "Column 4", and also "column for": straight after the word
        // "column" a number is the only thing that makes sense.
        if let n = number(after: ["column", "col", "number", "slot"], in: w) { return n }

        let numbers = w.compactMap { Phrase.number($0) }
        if numbers.count == 1 { return numbers[0] }
        if numbers.count > 1 { return nil }

        if w.contains(where: middleWords.contains) { return 4 }
        let isEdge = w.contains(where: edgeWords.contains)
        if w.contains("leftmost") || (w.contains("left") && isEdge) { return 1 }
        if w.contains("rightmost") || (w.contains("right") && isEdge) { return FourInARowBoard.columnCount }
        if follows("last", "column", in: w) { return FourInARowBoard.columnCount }

        // A sound-alike on its own, or straight after "play", "drop in" and
        // the like: "for" can only be four here. Anywhere else it is left
        // alone, because "I want to" is not a move.
        let core = w.filter { !politeWords.contains($0) }
        if let last = core.last, let n = Phrase.numberWords[last],
           core.count == 1 || directWords.contains(core[core.count - 2]) {
            return n
        }
        return nil
    }

    /// Removes "one" where it stands for a piece or a column rather than the
    /// number: "the middle one", "the third one", "drop one in column 4".
    private static func droppingPronounOne(_ words: [String]) -> [String] {
        let dropVerbs: Set<String> = ["drop", "put", "place", "play"]
        var out: [String] = []
        for (index, word) in words.enumerated() {
            if word == "one", let previous = out.last {
                let afterPlace = placeWords.contains(previous) || Phrase.ordinalWords[previous] != nil
                let afterVerb = dropVerbs.contains(previous) && index < words.count - 1
                if afterPlace || afterVerb { continue }
            }
            out.append(word)
        }
        return out
    }

    // MARK: Questions

    private static func question(_ w: [String]) -> FourInARowRequest {
        func has(_ options: String...) -> Bool { options.contains(where: w.contains) }
        let text = " " + w.joined(separator: " ") + " "
        func says(_ phrase: String) -> Bool { text.contains(" " + phrase + " ") }

        if has("won", "winner", "over", "finished", "ended", "lost", "draw", "drawn", "tie", "tied") {
            return .gameStatus
        }

        let column = mentionedColumn(w)
        let row = mentionedRow(w)
        let aboutWinning = has("win", "wins", "winning", "threat", "threats", "threaten", "threatens",
                               "threatening", "danger", "block", "blocking") || says("in a row")

        if let column, let row { return .readCell(column: column, row: row) }
        if let row { return .readRow(row) }
        if let column, !aboutWinning { return .readColumn(column) }
        if aboutWinning { return .threats }

        if has("heights", "height", "tall", "high")
            || (has("how") && has("full", "filled"))
            || (has("how") && has("many") && has("column", "columns", "each")) {
            return .heights
        }
        if has("open", "full", "available", "free", "playable", "legal", "allowed")
            || says("can i play") || says("can i go") || says("can i drop") || says("where can i") {
            return .openColumns
        }
        if has("colour", "color") || says("who am i") || says("which side")
            || (says("am i") && has("red", "yellow")) {
            return .whoAmI
        }
        if has("where", "pieces", "piece", "discs", "checkers", "counters", "chips", "tokens", "mine", "theirs") {
            return .pieces(owner(w))
        }
        return .unknown
    }

    private static func owner(_ w: [String]) -> Owner {
        func has(_ options: String...) -> Bool { options.contains(where: w.contains) }
        if has("red", "reds") { return .side(.red) }
        if has("yellow", "yellows") { return .side(.yellow) }
        // "Their" is checked before "my" so that "my opponent's pieces" works.
        if has("their", "theirs", "them", "they", "his", "her", "hers", "its", "computer", "computers",
               "opponent", "opponents", "your", "yours", "other") { return .theirs }
        if has("my", "mine", "i", "me", "our", "ours") { return .mine }
        return .everyone
    }

    /// The column a question is about: "column 3", "third column", "the middle column".
    private static func mentionedColumn(_ w: [String]) -> Int? {
        if let n = ordinal(before: ["column", "col"], in: w) ?? number(after: ["column", "col"], in: w) { return n }
        guard w.contains("column") else { return nil }
        if w.contains(where: middleWords.contains) { return 4 }
        if w.contains("leftmost") || w.contains("left") { return 1 }
        if w.contains("rightmost") || w.contains("right") || w.contains("last") { return FourInARowBoard.columnCount }
        return nil
    }

    /// The row a question is about: "row 2", "second row", "the bottom row".
    private static func mentionedRow(_ w: [String]) -> Int? {
        if let n = ordinal(before: ["row"], in: w) ?? number(after: ["row"], in: w) { return n }
        guard w.contains("row") else { return nil }
        if w.contains("bottom") || w.contains("lowest") { return 1 }
        if w.contains("top") || w.contains("highest") { return FourInARowBoard.rowCount }
        return nil
    }

    // MARK: Helpers

    /// The number said straight after a label, as in "column 4". The
    /// sound-alikes count here ("column for") because nothing else fits.
    private static func number(after labels: Set<String>, in w: [String]) -> Int? {
        guard let i = w.firstIndex(where: labels.contains), i + 1 < w.count else { return nil }
        return Phrase.looseNumber(w[i + 1])
    }

    /// The ordinal said straight before a label, as in "third column".
    private static func ordinal(before labels: Set<String>, in w: [String]) -> Int? {
        guard let i = w.firstIndex(where: labels.contains), i > 0 else { return nil }
        return Phrase.ordinalWords[w[i - 1]]
    }

    private static func follows(_ first: String, _ second: String, in w: [String]) -> Bool {
        guard let i = w.firstIndex(of: first), i + 1 < w.count else { return false }
        return w[i + 1] == second
    }
}
