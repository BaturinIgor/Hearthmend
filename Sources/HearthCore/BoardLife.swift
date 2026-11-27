import Foundation

/// Механики поля версии 1.2: живое поле (соседи сами выкладывают предметы), тепло очага
/// (предметы рядом дозревают) и починка (сломанные вещи чинятся предметом другой цепочки).
/// Все идет по реальному времени и считается в tickBoard(), который зовут вместе с refreshEnergy().

/// Пара соседей на поле: предмет цепочки `chain` не ниже `minTier` рядом с предметом `partner`
/// не ниже `partnerMin` раз в Balance.lifeInterval кладет рядом предмет первой ступени цепочки `chain`.
public struct LifePair: Equatable {
    public let chain: String
    public let minTier: Int
    public let partner: String
    public let partnerMin: Int
}

/// Что случилось на поле само, пока шло время: сцена показывает полет и вспышки.
public enum BoardEvent: Equatable {
    /// Пара соседей выложила предмет: из клетки from в клетку to.
    case grew(from: Int, to: Int, item: Item)
    /// Предмет у очага дозрел до следующей ступени.
    case ripened(index: Int, item: Item)
    /// Очаг погас.
    case hearthOut(index: Int)
}

extension Balance {
    /// Пары живого поля. Первые две работают с самого начала (огород, лес, камни).
    public static let lifePairs: [LifePair] = [
        LifePair(chain: "garden", minTier: 1, partner: "forest", partnerMin: 1),
        LifePair(chain: "quarry", minTier: 1, partner: "forest", partnerMin: 1),
        LifePair(chain: "apiary", minTier: 1, partner: "garden", partnerMin: 1),
        LifePair(chain: "farm", minTier: 1, partner: "garden", partnerMin: 1),
        LifePair(chain: "orchard", minTier: 1, partner: "apiary", partnerMin: 1),
        LifePair(chain: "fishing", minTier: 1, partner: "forest", partnerMin: 1),
        LifePair(chain: "crystal", minTier: 1, partner: "quarry", partnerMin: 1),
    ]
    /// Раз во сколько секунд пара выкладывает предмет.
    public static let lifeInterval: TimeInterval = 15 * 60
    /// Сколько предметов пара копит, пока игрока нет (больше за один раз не выложит).
    public static let lifeMaxBatch = 4
    /// Сколько клеток живое поле всегда оставляет пустыми, чтобы игроку было куда ходить.
    public static let lifeKeepFree = 6

    /// Очаг выдается с этого уровня.
    public static let hearthLevel = 3
    /// Чем топят очаг и сколько секунд горения дает предмет первой ступени (каждая следующая вдвое больше).
    public static let hearthFuelChain = "forest"
    public static let hearthFuelBase: TimeInterval = 15 * 60
    public static let hearthFuelMax: TimeInterval = 8 * 3600
    /// Новый очаг горит столько, чтобы игрок увидел, как он работает.
    public static let hearthStartFuel: TimeInterval = 2 * 3600
    /// Сколько тепла нужно предмету первой ступени, чтобы дозреть (каждая следующая вдвое дольше).
    public static let hearthRipenBase: TimeInterval = 15 * 60
    /// С этой ступени (0 - первая) у очага уже не дозревает: верхние ступени собираются слиянием.
    public static let hearthMaxTier = 3

    /// С какого уровня генераторы иногда дают сломанную вещь и как часто.
    public static let brokenLevel = 5
    public static let brokenChance = 0.04
    /// На сколько ступеней сломанная вещь выше обычного предмета генератора.
    public static let brokenBonus = 2
}

extension Game {
    // MARK: - Общий такт

    /// Все, что на поле идет само по времени. Возвращает события для анимации.
    @discardableResult
    public func tickBoard() -> [BoardEvent] {
        var events = tickHearth()
        events += tickLife()
        giveHearthIfNeeded()
        return events
    }

    // MARK: - Живое поле

    /// Клетки, которые сейчас выкладывают предметы, и пара, по которой они работают.
    /// Каждая пара работает в одном месте поля: десять морковок у десяти поленьев не дают десять семян.
    public var lifeProducers: [(index: Int, pair: LifePair)] {
        var result: [(index: Int, pair: LifePair)] = []
        for i in state.cells.indices {
            guard case .item(let item)? = state.cells[i] else { continue }
            for pair in Balance.lifePairs where pair.chain == item.chain && item.tier >= pair.minTier
                && !result.contains(where: { $0.pair == pair }) {
                let ok = neighbors(of: i).contains { n in
                    guard case .item(let other)? = state.cells[n] else { return false }
                    return other.chain == pair.partner && other.tier >= pair.partnerMin
                }
                if ok {
                    result.append((i, pair))
                    break
                }
            }
        }
        return result
    }

    func tickLife() -> [BoardEvent] {
        let t = now()
        guard let last = state.lifeUpdatedAt, last <= t else {
            state.lifeUpdatedAt = t
            return []
        }
        let steps = Int(t.timeIntervalSince(last) / Balance.lifeInterval)
        guard steps > 0 else { return [] }
        state.lifeUpdatedAt = last.addingTimeInterval(Double(steps) * Balance.lifeInterval)
        let producers = lifeProducers
        guard !producers.isEmpty else { return [] }
        var events: [BoardEvent] = []
        for _ in 0..<min(steps, Balance.lifeMaxBatch) {
            for (index, pair) in producers {
                let free = state.cells.filter { $0 == nil }.count
                guard free > Balance.lifeKeepFree else { return events }
                // рядом с парой, если есть место, иначе в ближайшую пустую клетку
                guard let cell = neighbors(of: index).first(where: { state.cells[$0] == nil }) ?? nearestEmpty(to: index)
                else { return events }
                let item = Item(chain: pair.chain, tier: 0)
                state.cells[cell] = .item(item)
                discover(item)
                events.append(.grew(from: index, to: cell, item: item))
            }
        }
        return events
    }

    // MARK: - Очаг

    public var hearthIndex: Int? {
        state.cells.firstIndex { if case .hearth? = $0 { return true } else { return false } }
    }

    public var hearth: Hearth? {
        guard let i = hearthIndex, case .hearth(let h)? = state.cells[i] else { return nil }
        return h
    }

    /// Сколько секунд горения дает предмет, если бросить его в очаг. nil - этим очаг не топят.
    public func fuelValue(_ item: Item) -> TimeInterval? {
        guard item.chain == Balance.hearthFuelChain else { return nil }
        return Balance.hearthFuelBase * Double(1 << min(item.tier, 10))
    }

    /// Сколько тепла нужно предмету, чтобы дозреть. nil - у очага не дозревает.
    public func ripenTime(_ item: Item) -> TimeInterval? {
        guard item.tier < Balance.hearthMaxTier, catalog.next(item) != nil else { return nil }
        return Balance.hearthRipenBase * Double(1 << item.tier)
    }

    /// Клетки, которые греет очаг.
    public var warmCells: [Int] {
        guard let i = hearthIndex, hearth?.isLit == true else { return [] }
        return neighbors(of: i)
    }

    /// Доля дозревания предмета в клетке (0...1) или nil, если клетка не греется.
    public func ripeness(at index: Int) -> Double? {
        guard warmCells.contains(index), case .item(let item)? = state.cells[index], let need = ripenTime(item) else { return nil }
        guard let w = state.warmth[index], w.item == item else { return 0 }
        return min(1, w.seconds / need)
    }

    func tickHearth() -> [BoardEvent] {
        let t = now()
        guard let index = hearthIndex, case .hearth(var h)? = state.cells[index] else {
            state.hearthUpdatedAt = t
            return []
        }
        let last = state.hearthUpdatedAt ?? t
        state.hearthUpdatedAt = t
        let warm = Set(neighbors(of: index))
        // тепло остается только у предметов, которые все еще лежат у очага
        state.warmth = state.warmth.filter { warm.contains($0.key) && state.cells[$0.key]?.item == $0.value.item }
        guard last < t, h.isLit else { return [] }
        let burn = min(t.timeIntervalSince(last), h.fuel)
        h.fuel = max(0, h.fuel - burn)
        state.cells[index] = .hearth(h)
        var events: [BoardEvent] = []
        for n in warm.sorted() {
            guard case .item(let item)? = state.cells[n], let need = ripenTime(item) else { continue }
            var w = state.warmth[n] ?? Warmth(item: item, seconds: 0)
            w.seconds += burn
            if w.seconds >= need, let next = catalog.next(item) {
                state.cells[n] = .item(next)
                state.bestTier[next.chain] = max(state.bestTier[next.chain] ?? 0, next.tier)
                discover(next)
                state.warmth[n] = nil
                events.append(.ripened(index: n, item: next))
            } else {
                state.warmth[n] = w
            }
        }
        if !h.isLit { events.append(.hearthOut(index: index)) }
        return events
    }

    /// Очаг появляется на поле с уровня Balance.hearthLevel, когда есть свободная клетка (ближе к центру).
    func giveHearthIfNeeded() {
        guard !state.hearthGiven, state.level >= Balance.hearthLevel, tutorial == .done else { return }
        let center = (balance.rows / 2) * balance.cols + balance.cols / 2
        guard let cell = nearestEmpty(to: center) else { return }
        state.cells[cell] = .hearth(Hearth(fuel: Balance.hearthStartFuel))
        state.hearthUpdatedAt = now()
        state.hearthGiven = true
    }

    /// Бросить предмет в очаг. Возвращает новый очаг или nil, если этим не топят или очаг полон.
    func fuelHearth(item: Item, from: Int, to: Int) -> Hearth? {
        guard case .hearth(let before)? = state.cells[to], fuelValue(item) != nil,
              before.fuel < Balance.hearthFuelMax, let value = fuelValue(item) else { return nil }
        // сначала догоряет то, что было: время до броска считается по старому топливу
        _ = tickHearth()
        guard case .hearth(var h)? = state.cells[to] else { return nil }
        h.fuel = min(Balance.hearthFuelMax, h.fuel + value)
        state.cells[to] = .hearth(h)
        state.cells[from] = nil
        state.hearthUpdatedAt = now()
        return h
    }

    // MARK: - Починка

    /// Какой цепочкой чинится сломанная вещь: деревянное и садовое чинят камнем и металлом, остальное деревом.
    public func mendChain(for chain: String) -> String {
        switch chain {
        case "forest", "fishing", "orchard": return "quarry"
        default: return "forest"
        }
    }

    /// Самый простой предмет, которым можно починить вещь: нужная цепочка, ступень не ниже (ступень вещи - 2).
    public func mendTool(for broken: Item) -> Item {
        Item(chain: mendChain(for: broken.chain), tier: max(0, broken.tier - 2))
    }

    public func canMend(_ broken: Item, with tool: Item) -> Bool {
        let need = mendTool(for: broken)
        return tool.chain == need.chain && tool.tier >= need.tier
    }

    /// Иногда вместо обычного предмета генератор дает сломанную вещь повыше.
    func maybeBroken(_ item: Item) -> Piece {
        guard state.level >= Balance.brokenLevel, tutorial == .done,
              Double.random(in: 0..<1, using: &rng) < Balance.brokenChance else { return .item(item) }
        let top = min(catalog.orderTop(of: item.chain), catalog.maxTier(of: item.chain))
        let tier = min(item.tier + Balance.brokenBonus, top)
        guard tier > item.tier else { return .item(item) }
        return .broken(Item(chain: item.chain, tier: tier))
    }

    func mend(tool: Item, from: Int, to: Int) -> Item? {
        guard case .broken(let broken)? = state.cells[to], canMend(broken, with: tool) else { return nil }
        state.cells[to] = .item(broken)
        state.cells[from] = nil
        state.bestTier[broken.chain] = max(state.bestTier[broken.chain] ?? 0, broken.tier)
        discover(broken)
        return broken
    }
}
