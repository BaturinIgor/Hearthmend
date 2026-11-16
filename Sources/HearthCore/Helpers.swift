import Foundation

/// Удобства на поле: ускорение генераторов, отмена продажи, подсказка слияния, подсветка предметов заказа.
extension Game {
    // MARK: - Ускорение x2

    /// Ускорение открывается с уровня boostLevel. Включенное, оно тратит 2 энергии за предмет на ступень выше:
    /// ценность та же (2^ступень), просто меньше тапов и места на поле.
    public var boostUnlocked: Bool { state.level >= balance.boostLevel }

    public var boostActive: Bool { boostUnlocked && state.boostOn }

    public func setBoost(_ on: Bool) {
        state.boostOn = on && boostUnlocked
    }

    // MARK: - Отмена продажи

    public var canUndoSale: Bool {
        guard let sale = lastSale else { return false }
        return state.cells.indices.contains(sale.index) && state.cells[sale.index] == nil && state.coins >= sale.coins
    }

    /// Возвращает проданный предмет на место и забирает монеты. Возвращает клетку или nil.
    @discardableResult
    public func undoSale() -> Int? {
        guard canUndoSale, let sale = lastSale else { return nil }
        state.cells[sale.index] = .item(sale.item)
        state.coins -= sale.coins
        lastSale = nil
        return sale.index
    }

    // MARK: - Подсказки

    /// Пара одинаковых предметов, которые можно слить (младшая ступень первой), или nil.
    public func mergeHint() -> (Int, Int)? {
        var seen: [Item: Int] = [:]
        var best: (Int, Int, Int)?
        for (i, cell) in state.cells.enumerated() {
            guard case .item(let item)? = cell, catalog.next(item) != nil else { continue }
            if let j = seen[item] {
                if best == nil || item.tier < best!.2 { best = (j, i, item.tier) }
            } else {
                seen[item] = i
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    /// Клетки с предметами, которые нужны заказу (по одной на каждую потребность).
    public func cells(for order: Order) -> [Int] {
        var used = Set<Int>()
        var out: [Int] = []
        for need in order.needs {
            if let i = state.cells.indices.first(where: { !used.contains($0) && state.cells[$0]?.item == need }) {
                used.insert(i)
                out.append(i)
            }
        }
        return out
    }

    /// Предмет на поле нужен какому-нибудь заказу (интерфейс рисует галочку).
    public func isWanted(_ item: Item) -> Bool {
        state.orders.contains { $0.needs.contains(item) }
    }
}
