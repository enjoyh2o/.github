import Foundation

/// What the player asked for in Tic-Tac-Toe, once their words are understood.
///
/// Understanding is kept apart from the session so that it is a pure function
/// of the words: easy to read, and easy to test against many phrasings.
enum TicTacToeRequest: Equatable, Sendable {

    /// Whose marks a question is about.
    enum Owner: Equatable, Sendable {
        case mine, theirs, everyone
        case mark(TicTacToeBoard.Mark)
    }

    /// Take a square. The number may not be on the board; the session explains if so.
    case take(square: Int)
    /// A request every game shares, such as undo or help.
    case common(CommonIntent)
    case readSquare(Int)
    case readRow(Int)
    case readColumn(Int)
    case freeSquares
    case threats
    case marks(Owner)
    case gameStatus
    case whoAmI
    case unknown

    /// Works out what was asked from words already normalised by `Phrase.words`.
    ///
    /// A move is looked for first, and only counts when every word fits one.
    /// That lets "okay, the centre" take a square, while "what is in the
    /// centre?" stays a question.
    static func parse(_ words: [String]) -> TicTacToeRequest {
        if let square = squareToTake(words) { return .take(square: square) }
        if let common = CommonIntent.parse(words) { return .common(common) }
        return question(words)
    }

    // MARK: Moves

    /// Small words that carry no meaning of their own.
    private static let politeWords: Set<String> = [
        "please", "thanks", "thank", "you", "um", "uh", "er", "erm", "hmm", "ok", "okay",
        "yes", "yeah", "no", "so", "well", "now", "then", "and", "just",
    ]

    /// Words that lead straight up to a square: "take 5", "play in 5".
    private static let directWords: Set<String> = [
        "play", "take", "put", "place", "mark", "go", "choose", "pick", "select", "try", "claim",
        "in", "into", "on", "square", "number", "cell", "box", "space", "spot", "position",
    ]

    /// The other words a request to move may contain.
    private static let fillerWords: Set<String> = [
        "i", "ill", "id", "im", "lets", "let", "me", "us", "we", "will", "would", "like", "want",
        "wanna", "gonna", "going", "think", "guess", "maybe", "how", "about", "my", "a", "an", "the",
        "it", "this", "that", "x", "o", "onto", "at", "to", "for", "of", "hand", "side", "corner",
        "board", "row", "column",
    ]

    private static let topWords: Set<String> = ["top", "upper"]
    private static let bottomWords: Set<String> = ["bottom", "lower"]
    private static let middleWords: Set<String> = ["middle", "centre", "center", "central", "mid"]
    private static let placeWords: Set<String> = topWords.union(bottomWords).union(middleWords).union(["left", "right"])

    private static let squareLabels: Set<String> = ["square", "number", "cell", "box", "space", "spot", "position"]

    /// The square a move names, or nil if the words are not simply a move.
    /// A square that is not on the board comes back as a number outside 1 to 9.
    private static func squareToTake(_ words: [String]) -> Int? {
        let w = droppingPronounOne(words)
        let isMoveWord: (String) -> Bool = { word in
            politeWords.contains(word) || directWords.contains(word) || fillerWords.contains(word)
                || placeWords.contains(word) || Phrase.looseNumber(word) != nil
        }
        guard w.allSatisfy(isMoveWord) else { return nil }

        // "Row 2 column 3". A row or a column on its own is not a square.
        if w.contains("row") || w.contains("column") {
            guard let row = mentionedRow(w), let column = mentionedColumn(w) else { return nil }
            return TicTacToeBoard.square(row: row, column: column) ?? 0
        }

        if w.contains(where: placeWords.contains) { return namedSquare(w) }

        // "Square 5", and also "square for": straight after the word
        // "square" a number is the only thing that makes sense.
        if let n = number(after: squareLabels, in: w) { return n }

        let numbers = w.compactMap { Phrase.number($0) }
        if numbers.count == 1 { return numbers[0] }
        if numbers.count > 1 { return nil }

        // A sound-alike on its own, or straight after "take", "play in" and
        // the like: "for" can only be four here. Anywhere else it is left
        // alone, because "I want to" is not a move.
        let core = w.filter { !politeWords.contains($0) }
        if let last = core.last, let n = Phrase.numberWords[last],
           core.count == 1 || directWords.contains(core[core.count - 2]) {
            return n
        }
        return nil
    }

    /// The square a name points at: "top left", "upper right", "centre",
    /// "middle left". Nil when the name is incomplete, such as "top" alone.
    private static func namedSquare(_ w: [String]) -> Int? {
        func has(_ options: Set<String>) -> Bool { w.contains(where: options.contains) }
        let top = has(topWords), bottom = has(bottomWords)
        let left = w.contains("left"), right = w.contains("right")
        let middle = has(middleWords)
        if (top && bottom) || (left && right) { return nil }

        let row = top ? 1 : (bottom ? 3 : nil)
        let column = left ? 1 : (right ? 3 : nil)
        switch (row, column) {
        case let (row?, column?):
            return TicTacToeBoard.square(row: row, column: column)
        case let (row?, nil):
            // "Top middle": the middle of the top row.
            return middle ? TicTacToeBoard.square(row: row, column: 2) : nil
        case let (nil, column?):
            // "Middle left": the middle of the left column.
            return middle ? TicTacToeBoard.square(row: 2, column: column) : nil
        case (nil, nil):
            return middle ? 5 : nil
        }
    }

    /// Removes "one" where it stands for a square rather than the number:
    /// "the middle one", "the top left one", "which one".
    private static func droppingPronounOne(_ words: [String]) -> [String] {
        let pointers: Set<String> = ["which", "what", "any", "that", "this", "no", "every", "each"]
        var out: [String] = []
        for word in words {
            if word == "one", let previous = out.last,
               placeWords.contains(previous) || pointers.contains(previous) || Phrase.ordinalWords[previous] != nil {
                continue
            }
            out.append(word)
        }
        return out
    }

    // MARK: Questions

    private static func question(_ words: [String]) -> TicTacToeRequest {
        let w = droppingPronounOne(words)
        func has(_ options: String...) -> Bool { options.contains(where: w.contains) }
        let text = " " + w.joined(separator: " ") + " "
        func says(_ phrase: String) -> Bool { text.contains(" " + phrase + " ") }

        if has("won", "winner", "over", "finished", "ended", "lost", "draw", "drawn", "tie", "tied") {
            return .gameStatus
        }

        let aboutWinning = has("win", "wins", "winning", "lose", "losing", "threat", "threats", "threaten",
                               "threatens", "threatening", "danger", "block", "blocking") || says("in a row")

        // "Read the top row", "what is in column 3".
        let row = mentionedRow(w)
        let column = mentionedColumn(w)
        if let row, let column {
            return .readSquare(TicTacToeBoard.square(row: row, column: column) ?? 0)
        }
        if !aboutWinning {
            if let row { return .readRow(row) }
            if let column { return .readColumn(column) }
            // "What is in the centre", "who has 5", "is the top left free".
            if let square = mentionedSquare(w) { return .readSquare(square) }
        }
        if aboutWinning { return .threats }

        // "What is on the left": a side of the board rather than one square.
        if says("the left") { return .readColumn(1) }
        if says("the right") { return .readColumn(3) }
        if says("the top") { return .readRow(1) }
        if says("the bottom") { return .readRow(3) }

        // "What's left?" asks what is free, but "left" alone is half a square name.
        if has("free", "open", "empty", "available", "unused", "blank", "legal", "allowed")
            || (has("left") && w.count > 1)
            || says("can i play") || says("can i go") || says("can i take") || says("where can i") {
            return .freeSquares
        }
        if says("who am i") || says("what am i") || says("which am i") || says("which side")
            || (says("am i") && has("x", "o", "playing", "noughts", "crosses")) || has("symbol", "letter") {
            return .whoAmI
        }
        if says("where did") { return .common(.lastMove) }
        if has("moves") && has("many") { return .common(.history) }
        if has("where", "marks", "mark", "squares", "pieces", "mine", "theirs", "have", "has", "got",
               "x", "xs", "o", "os", "crosses", "noughts", "naughts", "circles") {
            return .marks(owner(w))
        }
        return .unknown
    }

    private static func owner(_ w: [String]) -> Owner {
        func has(_ options: String...) -> Bool { options.contains(where: w.contains) }
        if has("x", "xs", "exes", "cross", "crosses") { return .mark(.x) }
        if has("o", "os", "nought", "noughts", "naughts", "circle", "circles") { return .mark(.o) }
        // "Their" is checked before "my" so that "my opponent's marks" works.
        if has("their", "theirs", "them", "they", "his", "her", "hers", "its", "computer", "computers",
               "opponent", "opponents", "your", "yours", "other") { return .theirs }
        if has("my", "mine", "i", "me", "our", "ours") { return .mine }
        return .everyone
    }

    /// The square a question is about, by name or by number.
    private static func mentionedSquare(_ w: [String]) -> Int? {
        if let named = namedSquare(w) { return named }
        if let n = number(after: squareLabels, in: w) { return n }
        // Only plain numbers here. In a question, "to" and "for" are
        // ordinary words.
        let numbers = w.compactMap { Phrase.number($0) }
        return numbers.count == 1 ? numbers[0] : nil
    }

    /// The row a phrase is about: "row 2", "second row", "the top row".
    /// Rows are numbered from the top.
    private static func mentionedRow(_ w: [String]) -> Int? {
        if let n = ordinal(before: ["row"], in: w) ?? number(after: ["row"], in: w) { return n }
        guard let i = w.firstIndex(of: "row"), i > 0 else { return nil }
        if topWords.contains(w[i - 1]) { return 1 }
        if middleWords.contains(w[i - 1]) { return 2 }
        if bottomWords.contains(w[i - 1]) { return 3 }
        return nil
    }

    /// The column a phrase is about: "column 3", "third column", "the left column".
    private static func mentionedColumn(_ w: [String]) -> Int? {
        if let n = ordinal(before: ["column"], in: w) ?? number(after: ["column"], in: w) { return n }
        guard let i = w.firstIndex(of: "column"), i > 0 else { return nil }
        if w[i - 1] == "left" { return 1 }
        if middleWords.contains(w[i - 1]) { return 2 }
        if w[i - 1] == "right" { return 3 }
        return nil
    }

    // MARK: Helpers

    /// The number said straight after a label, as in "square 5". The
    /// sound-alikes count here ("square for") because nothing else fits.
    private static func number(after labels: Set<String>, in w: [String]) -> Int? {
        guard let i = w.firstIndex(where: labels.contains), i + 1 < w.count else { return nil }
        return Phrase.looseNumber(w[i + 1])
    }

    /// The ordinal said straight before a label, as in "third column".
    private static func ordinal(before labels: Set<String>, in w: [String]) -> Int? {
        guard let i = w.firstIndex(where: labels.contains), i > 0 else { return nil }
        return Phrase.ordinalWords[w[i - 1]]
    }
}
