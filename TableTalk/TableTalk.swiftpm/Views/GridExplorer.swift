import SwiftUI

/// Lets a finger explore a grid of equal cells.
///
/// Each new cell the finger enters is reported, so the board can say what
/// is there. Only a quick touch that stays on one cell counts as a tap; a
/// slow or sliding touch just explores. That way feeling around a board
/// can never make a move by accident.
///
/// VoiceOver users do not go through this: VoiceOver handles touch itself
/// and reads the cells' own accessibility labels.
struct GridExplorer: ViewModifier {
    let columns: Int
    let rows: Int
    let cell: CGSize
    /// The finger entered the cell at (column, row), counted from the top left.
    let entered: (Int, Int) -> Void
    /// A quick touch began and ended on the cell at (column, row).
    let tapped: (Int, Int) -> Void

    @State private var visited: [Int] = []
    @State private var began = Date()

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard cell.width > 0, cell.height > 0,
                              value.location.x >= 0, value.location.y >= 0 else { return }
                        let column = Int(value.location.x / cell.width)
                        let row = Int(value.location.y / cell.height)
                        guard column < columns, row < rows else { return }
                        let index = row * columns + column
                        guard index != visited.last else { return }
                        if visited.isEmpty { began = Date() }
                        visited.append(index)
                        entered(column, row)
                    }
                    .onEnded { _ in
                        let wasTap = visited.count == 1 && Date().timeIntervalSince(began) < 0.6
                        let first = visited.first
                        visited.removeAll()
                        if wasTap, let first { tapped(first % columns, first / columns) }
                    }
            )
    }
}

extension View {
    func explorable(
        columns: Int,
        rows: Int,
        cell: CGSize,
        entered: @escaping (Int, Int) -> Void,
        tapped: @escaping (Int, Int) -> Void
    ) -> some View {
        modifier(GridExplorer(columns: columns, rows: rows, cell: cell, entered: entered, tapped: tapped))
    }
}
