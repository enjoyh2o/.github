import SwiftUI

/// Board colour schemes. The default is chosen for contrast, not tradition:
/// every piece must stand out clearly from every square.
enum BoardTheme: String, CaseIterable, Identifiable {
    case highContrast, classic, night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .highContrast: return "High contrast"
        case .classic: return "Classic wood"
        case .night: return "Night"
        }
    }

    var lightSquare: Color {
        switch self {
        case .highContrast: return Color(red: 0.93, green: 0.94, blue: 0.96)
        case .classic: return Color(red: 0.94, green: 0.85, blue: 0.71)
        case .night: return Color(red: 0.45, green: 0.51, blue: 0.58)
        }
    }

    var darkSquare: Color {
        switch self {
        case .highContrast: return Color(red: 0.25, green: 0.42, blue: 0.66)
        case .classic: return Color(red: 0.71, green: 0.53, blue: 0.39)
        case .night: return Color(red: 0.20, green: 0.25, blue: 0.31)
        }
    }

    /// Marks the squares of the most recent move.
    var lastMove: Color { Color(red: 1.0, green: 0.84, blue: 0.0) }
    /// Marks the picked-up piece and where it may go.
    var selection: Color { Color(red: 0.0, green: 0.78, blue: 0.55) }
    /// Marks a king in check.
    var check: Color { Color(red: 0.90, green: 0.15, blue: 0.15) }
}

/// A chess piece drawn so that it is readable on any square: a solid fill
/// with a contrasting outline all the way round.
struct ChessPieceView: View {
    let piece: Piece
    let size: CGFloat
    let style: PieceStyle

    private var fill: Color { piece.color == .white ? .white : .black }
    private var outline: Color { piece.color == .white ? .black : .white }

    var body: some View {
        switch style {
        case .figures:
            let glyph = ChessPieceView.glyph(for: piece.kind)
            let font = Font.system(size: size * 0.76)
            let width = max(1, size * 0.035)
            ZStack {
                // Eight offset copies behind the glyph make an even outline.
                ForEach(0..<8, id: \.self) { step in
                    let angle = Double(step) * Double.pi / 4
                    Text(glyph)
                        .font(font)
                        .foregroundStyle(outline)
                        .offset(x: CGFloat(cos(angle)) * width, y: CGFloat(sin(angle)) * width)
                }
                Text(glyph)
                    .font(font)
                    .foregroundStyle(fill)
            }
        case .letters:
            ZStack {
                Circle().fill(fill)
                Circle().stroke(outline, lineWidth: max(2, size * 0.07))
                Text(String(piece.kind.letter))
                    .font(.system(size: size * 0.46, weight: .heavy, design: .rounded))
                    .foregroundStyle(outline)
            }
            .padding(size * 0.12)
        }
    }

    /// The solid chess figures from Unicode. The trailing selector asks for
    /// the plain text shape, so the pawn is not replaced by an emoji.
    static func glyph(for kind: PieceKind) -> String {
        let base: String
        switch kind {
        case .king: base = "\u{265A}"
        case .queen: base = "\u{265B}"
        case .rook: base = "\u{265C}"
        case .bishop: base = "\u{265D}"
        case .knight: base = "\u{265E}"
        case .pawn: base = "\u{265F}"
        }
        return base + "\u{FE0E}"
    }
}

/// The icon shown beside each kind of reply, so tone never depends on
/// colour alone.
extension Reply.Tone {
    var symbolName: String {
        switch self {
        case .info: return "text.bubble"
        case .move: return "arrow.right.circle"
        case .capture: return "xmark.circle"
        case .alert: return "exclamationmark.triangle.fill"
        case .gameOver: return "flag.checkered"
        case .question: return "questionmark.circle.fill"
        case .error: return "exclamationmark.circle"
        }
    }
}
