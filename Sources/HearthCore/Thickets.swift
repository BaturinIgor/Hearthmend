import Foundation

/// Заросли: новая игра начинается с открытого квадрата внизу поля, остальное под листвой.
/// Предмет в зарослях виден, только если рядом есть открытая клетка. Положи на него такой же,
/// они сольются, и клетка расчистится. За каждый полностью расчищенный ряд дается ящик.
extension Game {
    /// Раскладка зарослей для новой игры: чем дальше от открытого квадрата, тем выше ступень.
    /// Одинаковая у всех игроков, чтобы поле было продуманным, а не случайным.
    static func thicketCells(balance: Balance, chains: [String], catalog: Catalog) -> [Piece?] {
        let cols = balance.cols, rows = balance.rows
        let k = min(balance.thicketOpen, cols, rows)
        var cells = [Piece?](repeating: nil, count: balance.cellCount)
        guard k > 0, !chains.isEmpty else { return cells }
        let top = rows - k, left = (cols - k) / 2, right = left + k - 1
        var rng = SplitMix64(seed: 2026)
        for r in 0..<rows {
            for c in 0..<cols {
                let dr = max(0, top - r)
                let dc = max(0, left - c, c - right)
                guard dr + dc > 0 else { continue }
                let d = max(dr, dc) + min(dr, dc) / 2
                var tier = d <= 1 ? 0 : d <= 3 ? 1 : d <= 5 ? 2 : 3
                if tier > 0, Double.random(in: 0..<1, using: &rng) < 0.25 { tier -= 1 }
                let chain = chains[Int.random(in: 0..<chains.count, using: &rng)]
                cells[r * cols + c] = .thicket(Item(chain: chain, tier: min(tier, catalog.maxTier(of: chain) - 1)))
            }
        }
        return cells
    }

    /// Видно ли, что лежит в клетке. Открытые клетки видны всегда, заросли - если рядом есть открытая.
    public func isRevealed(_ index: Int) -> Bool {
        guard case .thicket? = piece(at: index) else { return true }
        return neighbors(of: index).contains { i in
            if case .thicket? = state.cells[i] { return false }
            return true
        }
    }

    public var thicketsLeft: Int {
        state.cells.filter { if case .thicket? = $0 { return true } else { return false } }.count
    }

    /// Предметы, которые сейчас можно положить на заросли (видимые).
    public var revealedThickets: [(index: Int, item: Item)] {
        state.cells.indices.compactMap { i in
            guard case .thicket(let item)? = state.cells[i], isRevealed(i) else { return nil }
            return (i, item)
        }
    }

    /// Ряды, которые уже расчищены, но ящик за них еще не выдан: выдает ящики.
    func rewardThicketRows() {
        let cols = balance.cols
        for row in state.thicketRows {
            let left = (0..<cols).contains { c in
                if case .thicket? = state.cells[row * cols + c] { return true }
                return false
            }
            guard !left else { continue }
            state.thicketRows.removeAll { $0 == row }
            // верхние ряды дальше всего от начала, там ящик больше
            let level = row < balance.rows / 3 ? 2 : row < balance.rows * 2 / 3 ? 1 : 0
            state.pendingChests.append(Chest(kind: randomChestKind(Balance.rowChestWeights), level: level))
        }
    }
}
