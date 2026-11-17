import Foundation

/// How board squares are said aloud.
enum SquareNaming: String, CaseIterable, Sendable, Identifiable {
    /// "E 4" — plain letter names.
    case letters
    /// "Echo 4" — the radio alphabet, hard to mishear.
    case nato
    /// "Eva 4" — the names FIDE suggests for games with blind players
    /// (Anna, Bella, Cesar, David, Eva, Felix, Gustav, Hector).
    case fide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .letters: return "Letters (E 4)"
        case .nato: return "Radio alphabet (Echo 4)"
        case .fide: return "Blind chess names (Eva 4)"
        }
    }

    func name(forFile file: Int) -> String {
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H"]
        let nato = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel"]
        let fide = ["Anna", "Bella", "Cesar", "David", "Eva", "Felix", "Gustav", "Hector"]
        guard (0..<8).contains(file) else { return "" }
        switch self {
        case .letters: return letters[file]
        case .nato: return nato[file]
        case .fide: return fide[file]
        }
    }
}

/// Turns text written for the eye into text a speech synthesizer says well.
///
/// The classic trap is the square "a3": a synthesizer reads it as the article,
/// "uh three". Writing it "A 3" (or "Alpha 3") makes it unmistakable.
enum SpeechFormatter {

    static func spoken(_ text: String, naming: SquareNaming = .letters) -> String {
        var out = ""
        var word = ""

        func flush() {
            guard !word.isEmpty else { return }
            out += transform(word, naming: naming)
            word = ""
        }

        for ch in text {
            if ch.isLetter || ch.isNumber || ch == "-" {
                word.append(ch)
            } else {
                flush()
                out.append(ch)
            }
        }
        flush()
        return out
    }

    private static func transform(_ word: String, naming: SquareNaming) -> String {
        let chars = Array(word)
        // A square such as "e4".
        if chars.count == 2, let file = fileIndex(chars[0]), let rank = chars[1].wholeNumberValue,
           (1...8).contains(rank) {
            return "\(naming.name(forFile: file)) \(rank)"
        }
        // A file such as "e-file".
        if chars.count == 6, word.hasSuffix("-file"), let file = fileIndex(chars[0]) {
            return "\(naming.name(forFile: file)) file"
        }
        return word
    }

    private static func fileIndex(_ ch: Character) -> Int? {
        guard let ascii = ch.asciiValue, ascii >= 97, ascii <= 104 else { return nil }
        return Int(ascii) - 97
    }
}
