import Foundation

/// The computer opponent: a small, classic alpha-beta search.
///
/// It is deliberately modest. The goal is a pleasant partner for a relaxed
/// game, not a tournament engine — and everything runs on the device.
enum ChessAI {

    struct Settings: Sendable {
        /// How many half-moves ahead to look.
        var maxDepth: Int
        /// Random wobble added to each move's score, in hundredths of a pawn.
        /// More wobble means more human-looking mistakes.
        var noise: Int
        /// Give up deepening after this long and play the best move so far.
        var timeLimit: TimeInterval
        var nodeLimit: Int

        static func `for`(_ difficulty: Difficulty) -> Settings {
            switch difficulty {
            case .gentle: return Settings(maxDepth: 1, noise: 180, timeLimit: 1.0, nodeLimit: 20_000)
            case .steady: return Settings(maxDepth: 2, noise: 25, timeLimit: 1.5, nodeLimit: 60_000)
            case .sharp: return Settings(maxDepth: 5, noise: 8, timeLimit: 1.2, nodeLimit: 150_000)
            }
        }

        /// Used for hints: no wobble, quick, sensible.
        static let hint = Settings(maxDepth: 2, noise: 0, timeLimit: 0.6, nodeLimit: 30_000)
    }

    static func chooseMove(
        in position: ChessPosition,
        difficulty: Difficulty,
        seed: UInt64 = UInt64.random(in: 0...UInt64.max)
    ) -> Move? {
        chooseMove(in: position, settings: .for(difficulty), seed: seed)
    }

    static func chooseMove(in position: ChessPosition, settings: Settings, seed: UInt64 = 1) -> Move? {
        var moves = position.legalMoves()
        guard !moves.isEmpty else { return nil }
        if moves.count == 1 { return moves[0] }

        var search = Search(settings: settings)
        var random = SplitMix64(seed: seed)
        // Moves scoring within `margin` of the best get exact scores, so the
        // wobble below can pick between genuinely close choices.
        let margin = settings.noise * 2 + 1
        var scored: [(move: Move, score: Int)] = []

        search.order(&moves, in: position)
        for depth in 1...max(1, settings.maxDepth) {
            search.canStop = depth > 1
            var best = -Search.infinity
            var round: [(move: Move, score: Int)] = []
            for move in moves {
                let child = position.applying(move)
                let floor = best == -Search.infinity ? -Search.infinity : best - margin
                let score = -search.negamax(child, depth: depth - 1, alpha: -Search.infinity, beta: -floor, ply: 1)
                if search.stopped { break }
                round.append((move, score))
                best = max(best, score)
            }
            // A round that ran out of time is incomplete, so it is thrown away.
            if search.stopped { break }
            scored = round.sorted { $0.score > $1.score }
            moves = scored.map(\.move)
            // A forced mate needs no deeper look.
            if best > Search.mate - 100 { break }
        }

        guard let top = scored.first else { return moves.first }
        if settings.noise == 0 { return top.move }
        var choice = top.move
        var bestWobbled = Int.min
        for entry in scored where entry.score >= top.score - margin {
            let wobble = Int(random.next() % UInt64(settings.noise * 2 + 1)) - settings.noise
            if entry.score + wobble > bestWobbled {
                bestWobbled = entry.score + wobble
                choice = entry.move
            }
        }
        return choice
    }

    // MARK: Evaluation

    /// Scores a position in hundredths of a pawn from the point of view of
    /// the side to move. Positive means the mover is better off.
    static func evaluate(_ position: ChessPosition) -> Int {
        var score = 0
        var heavyMaterial = 0
        var queens = 0
        var kings: [(index: Int, color: PieceColor)] = []

        for i in 0..<64 {
            guard let piece = position.board[i] else { continue }
            // Tables are written from White's side with rank 8 on top.
            let tableIndex = piece.color == .white ? (7 - (i >> 3)) * 8 + (i & 7) : i
            var value: Int
            switch piece.kind {
            case .pawn: value = 100 + Tables.pawn[tableIndex]
            case .knight: value = 320 + Tables.knight[tableIndex]; heavyMaterial += 320
            case .bishop: value = 330 + Tables.bishop[tableIndex]; heavyMaterial += 330
            case .rook: value = 500 + Tables.rook[tableIndex]; heavyMaterial += 500
            case .queen: value = 900 + Tables.queen[tableIndex]; heavyMaterial += 900; queens += 1
            case .king:
                kings.append((tableIndex, piece.color))
                value = 0
            }
            if piece.color == .black { value = -value }
            score += value
        }

        // With little material left the king should come out and help.
        let endgame = queens == 0 || heavyMaterial <= 2600
        let kingTable = endgame ? Tables.kingEndgame : Tables.kingMiddlegame
        for king in kings {
            score += king.color == .white ? kingTable[king.index] : -kingTable[king.index]
        }
        return position.sideToMove == .white ? score : -score
    }

    // MARK: Search

    struct Search {
        static let infinity = 1_000_000
        static let mate = 100_000

        let settings: Settings
        let deadline: TimeInterval
        var nodes = 0
        var stopped = false
        /// The first round always finishes so there is always a move to play.
        var canStop = false

        init(settings: Settings) {
            self.settings = settings
            self.deadline = Date().timeIntervalSinceReferenceDate + settings.timeLimit
        }

        private mutating func tick() {
            nodes += 1
            guard canStop, nodes & 255 == 0 else { return }
            if nodes >= settings.nodeLimit || Date().timeIntervalSinceReferenceDate > deadline {
                stopped = true
            }
        }

        mutating func negamax(_ position: ChessPosition, depth: Int, alpha: Int, beta: Int, ply: Int) -> Int {
            if depth <= 0 { return quiesce(position, alpha: alpha, beta: beta, depth: 0) }
            tick()
            if stopped { return 0 }

            var alpha = alpha
            var best = -Search.infinity
            var foundLegalMove = false
            var moves = position.pseudoLegalMoves()
            order(&moves, in: position)

            for move in moves {
                guard let next = position.applyingIfLegal(move) else { continue }
                foundLegalMove = true
                let score = -negamax(next, depth: depth - 1, alpha: -beta, beta: -alpha, ply: ply + 1)
                if stopped { return 0 }
                if score > best { best = score }
                if score > alpha { alpha = score }
                if alpha >= beta { break }
            }
            if !foundLegalMove {
                // Prefer the quickest mate, and the slowest defeat.
                return position.isCheck ? -Search.mate + ply : 0
            }
            return best
        }

        /// Keeps trading captures until the position is quiet, so the search
        /// never stops in the middle of an exchange and misjudges it.
        private mutating func quiesce(_ position: ChessPosition, alpha: Int, beta: Int, depth: Int) -> Int {
            tick()
            let standPat = ChessAI.evaluate(position)
            if standPat >= beta || depth >= 4 { return standPat }
            var alpha = max(alpha, standPat)
            var best = standPat

            var captures = position.pseudoLegalMoves().filter { position.captureSquare(of: $0) != nil }
            order(&captures, in: position)
            for move in captures {
                guard let next = position.applyingIfLegal(move) else { continue }
                let score = -quiesce(next, alpha: -beta, beta: -alpha, depth: depth + 1)
                if score > best { best = score }
                if score > alpha { alpha = score }
                if alpha >= beta { break }
            }
            return best
        }

        /// Tries the most promising moves first — winning captures and
        /// promotions — which lets alpha-beta skip far more of the tree.
        func order(_ moves: inout [Move], in position: ChessPosition) {
            guard moves.count > 1 else { return }
            let keyed = moves.map { move -> (Move, Int) in
                var key = 0
                if let victim = position.board[move.to.index], let attacker = position.board[move.from.index] {
                    key = 10_000 + victim.kind.tradeValue * 10 - attacker.kind.tradeValue
                } else if position.isEnPassant(move) {
                    key = 10_009
                }
                if move.promotion == .queen { key += 9_000 }
                return (move, key)
            }
            moves = keyed.sorted { $0.1 > $1.1 }.map(\.0)
        }
    }

    /// A tiny seedable random generator, so tests can replay a game exactly.
    struct SplitMix64 {
        private var state: UInt64
        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// Piece-square tables: small bonuses for standing on good squares.
    /// These are the well-known "Simplified Evaluation Function" values
    /// published by Tomasz Michniewski on the Chess Programming Wiki.
    enum Tables {
        static let pawn: [Int] = [
              0,   0,   0,   0,   0,   0,   0,   0,
             50,  50,  50,  50,  50,  50,  50,  50,
             10,  10,  20,  30,  30,  20,  10,  10,
              5,   5,  10,  25,  25,  10,   5,   5,
              0,   0,   0,  20,  20,   0,   0,   0,
              5,  -5, -10,   0,   0, -10,  -5,   5,
              5,  10,  10, -20, -20,  10,  10,   5,
              0,   0,   0,   0,   0,   0,   0,   0,
        ]
        static let knight: [Int] = [
            -50, -40, -30, -30, -30, -30, -40, -50,
            -40, -20,   0,   0,   0,   0, -20, -40,
            -30,   0,  10,  15,  15,  10,   0, -30,
            -30,   5,  15,  20,  20,  15,   5, -30,
            -30,   0,  15,  20,  20,  15,   0, -30,
            -30,   5,  10,  15,  15,  10,   5, -30,
            -40, -20,   0,   5,   5,   0, -20, -40,
            -50, -40, -30, -30, -30, -30, -40, -50,
        ]
        static let bishop: [Int] = [
            -20, -10, -10, -10, -10, -10, -10, -20,
            -10,   0,   0,   0,   0,   0,   0, -10,
            -10,   0,   5,  10,  10,   5,   0, -10,
            -10,   5,   5,  10,  10,   5,   5, -10,
            -10,   0,  10,  10,  10,  10,   0, -10,
            -10,  10,  10,  10,  10,  10,  10, -10,
            -10,   5,   0,   0,   0,   0,   5, -10,
            -20, -10, -10, -10, -10, -10, -10, -20,
        ]
        static let rook: [Int] = [
              0,   0,   0,   0,   0,   0,   0,   0,
              5,  10,  10,  10,  10,  10,  10,   5,
             -5,   0,   0,   0,   0,   0,   0,  -5,
             -5,   0,   0,   0,   0,   0,   0,  -5,
             -5,   0,   0,   0,   0,   0,   0,  -5,
             -5,   0,   0,   0,   0,   0,   0,  -5,
             -5,   0,   0,   0,   0,   0,   0,  -5,
              0,   0,   0,   5,   5,   0,   0,   0,
        ]
        static let queen: [Int] = [
            -20, -10, -10,  -5,  -5, -10, -10, -20,
            -10,   0,   0,   0,   0,   0,   0, -10,
            -10,   0,   5,   5,   5,   5,   0, -10,
             -5,   0,   5,   5,   5,   5,   0,  -5,
              0,   0,   5,   5,   5,   5,   0,  -5,
            -10,   5,   5,   5,   5,   5,   0, -10,
            -10,   0,   5,   0,   0,   0,   0, -10,
            -20, -10, -10,  -5,  -5, -10, -10, -20,
        ]
        static let kingMiddlegame: [Int] = [
            -30, -40, -40, -50, -50, -40, -40, -30,
            -30, -40, -40, -50, -50, -40, -40, -30,
            -30, -40, -40, -50, -50, -40, -40, -30,
            -30, -40, -40, -50, -50, -40, -40, -30,
            -20, -30, -30, -40, -40, -30, -30, -20,
            -10, -20, -20, -20, -20, -20, -20, -10,
             20,  20,   0,   0,   0,   0,  20,  20,
             20,  30,  10,   0,   0,  10,  30,  20,
        ]
        static let kingEndgame: [Int] = [
            -50, -40, -30, -20, -20, -30, -40, -50,
            -30, -20, -10,   0,   0, -10, -20, -30,
            -30, -10,  20,  30,  30,  20, -10, -30,
            -30, -10,  30,  40,  40,  30, -10, -30,
            -30, -10,  30,  40,  40,  30, -10, -30,
            -30, -10,  20,  30,  30,  20, -10, -30,
            -30, -30,   0,   0,   0,   0, -30, -30,
            -50, -30, -30, -30, -30, -30, -30, -50,
        ]
    }
}
