import Foundation

/// Правила поля слияния. Без UI: сцена и SwiftUI только вызывают эти методы и рисуют состояние.
/// Время и случайность передаются снаружи, поэтому все правила проверяются тестами.
public final class Game {
    public private(set) var state: GameState
    public let catalog: Catalog
    public let balance: Balance
    public var now: () -> Date
    private var rng: SplitMix64

    public init(state: GameState? = nil,
                catalog: Catalog = .bundled,
                balance: Balance = Balance(),
                seed: UInt64 = UInt64.random(in: 0...UInt64.max),
                now: @escaping () -> Date = Date.init) {
        self.catalog = catalog
        self.balance = balance
        self.now = now
        self.rng = SplitMix64(seed: seed)
        if let state, state.cells.count == balance.cellCount {
            self.state = state
        } else {
            self.state = Game.newState(catalog: catalog, balance: balance, now: now())
        }
        refillOrders()
    }

    // MARK: - Стартовое поле

    public static let startChains = ["garden", "forest", "quarry"]

    public static func newState(catalog: Catalog, balance: Balance, now: Date) -> GameState {
        var cells = [Piece?](repeating: nil, count: balance.cellCount)
        let cols = balance.cols
        for r in 0..<min(balance.debrisRows, balance.rows) {
            for c in 0..<cols { cells[r * cols + c] = .debris(1) }
        }
        let bottom = (balance.rows - 1) * cols
        let chains = startChains.filter { catalog.chain($0) != nil }
        let genCols = [1, 3, 5]
        for (i, chain) in chains.enumerated() where i < genCols.count && genCols[i] < cols {
            cells[bottom + genCols[i]] = .generator(GeneratorPiece(chain: chain, tier: 0))
        }
        // по паре предметов каждой цепочки, чтобы первое слияние было сразу
        let row = balance.rows - 3
        for (i, chain) in chains.enumerated() {
            let c = i * 2
            guard row > balance.debrisRows - 1, c + 1 < cols else { continue }
            cells[row * cols + c] = .item(Item(chain: chain, tier: 0))
            cells[row * cols + c + 1] = .item(Item(chain: chain, tier: 0))
        }
        var best: [String: Int] = [:]
        for chain in chains { best[chain] = 1 }
        return GameState(cells: cells,
                         energy: balance.energyMax,
                         energyUpdatedAt: now,
                         coins: balance.startCoins,
                         gems: balance.startGems,
                         stars: 0,
                         xp: 0,
                         orders: [],
                         nextOrderId: 1,
                         basket: [],
                         basketSize: balance.basketSize,
                         bestTier: best,
                         unlockedChains: chains,
                         mergesTotal: 0,
                         ordersTotal: 0)
    }

    // MARK: - Клетки

    public func piece(at index: Int) -> Piece? {
        state.cells.indices.contains(index) ? state.cells[index] : nil
    }

    public func neighbors(of index: Int) -> [Int] {
        let cols = balance.cols
        let r = index / cols, c = index % cols
        var result: [Int] = []
        if r > 0 { result.append(index - cols) }
        if r < balance.rows - 1 { result.append(index + cols) }
        if c > 0 { result.append(index - 1) }
        if c < cols - 1 { result.append(index + 1) }
        return result
    }

    /// Ближайшая пустая клетка к данной (по расстоянию между центрами).
    public func nearestEmpty(to index: Int) -> Int? {
        let cols = balance.cols
        let r0 = index / cols, c0 = index % cols
        var best: (index: Int, dist: Int)?
        for i in state.cells.indices where state.cells[i] == nil {
            let r = i / cols, c = i % cols
            let d = (r - r0) * (r - r0) + (c - c0) * (c - c0)
            if best == nil || d < best!.dist { best = (i, d) }
        }
        return best?.index
    }

    // MARK: - Энергия

    public func refreshEnergy() {
        let t = now()
        guard state.energy < balance.energyMax else { return }
        // часы перевели назад: отсчет с "будущей" даты встал бы на часы
        if state.energyUpdatedAt > t { state.energyUpdatedAt = t }
        let gained = Int(t.timeIntervalSince(state.energyUpdatedAt) / balance.energyRegen)
        guard gained > 0 else { return }
        state.energy = min(balance.energyMax, state.energy + gained)
        state.energyUpdatedAt = state.energy >= balance.energyMax
            ? t
            : state.energyUpdatedAt.addingTimeInterval(Double(gained) * balance.energyRegen)
    }

    /// Секунд до следующей единицы энергии или nil, если энергия полная.
    public var nextEnergyIn: TimeInterval? {
        guard state.energy < balance.energyMax else { return nil }
        return max(0, state.energyUpdatedAt.addingTimeInterval(balance.energyRegen).timeIntervalSince(now()))
    }

    public func spendEnergy(_ amount: Int) -> Bool {
        refreshEnergy()
        guard state.energy >= amount else { return false }
        if state.energy >= balance.energyMax { state.energyUpdatedAt = now() }
        state.energy -= amount
        return true
    }

    /// Энергия из наград и покупок может превышать максимум.
    public func addEnergy(_ amount: Int) {
        state.energy += amount
    }

    // MARK: - Генераторы

    public enum SpawnResult: Equatable {
        case spawned(index: Int, item: Item)
        case noEnergy
        case boardFull
        case notGenerator
    }

    public func spawn(from index: Int) -> SpawnResult {
        guard case .generator(let gen) = piece(at: index) else { return .notGenerator }
        guard let cell = nearestEmpty(to: index) else { return .boardFull }
        guard spendEnergy(1) else { return .noEnergy }
        var tier = 0
        if Double.random(in: 0..<1, using: &rng) < Double(gen.tier) * balance.generatorUpgradeChance { tier = 1 }
        if Double.random(in: 0..<1, using: &rng) < 0.1 { tier += 1 }
        tier = min(tier, catalog.maxTier(of: gen.chain))
        let item = Item(chain: gen.chain, tier: tier)
        state.cells[cell] = .item(item)
        return .spawned(index: cell, item: item)
    }

    // MARK: - Перемещение и слияние

    public enum MoveResult: Equatable {
        case moved
        case swapped
        /// cleared - клетки, где снялся слой завала, bubble - клетка нового пузыря.
        case merged(item: Item, cleared: [Int], bubble: Int?)
        case mergedGenerator(GeneratorPiece)
        case invalid
    }

    public func move(from: Int, to: Int) -> MoveResult {
        guard from != to,
              state.cells.indices.contains(from), state.cells.indices.contains(to),
              let a = state.cells[from], a.isMovable else { return .invalid }
        let b = state.cells[to]
        if let b, !b.isMovable { return .invalid }

        switch (a, b) {
        case (.item(let x), .item(let y)?) where x == y:
            guard let next = catalog.next(x) else { return swap(from, to) }
            state.cells[to] = .item(next)
            state.cells[from] = nil
            state.mergesTotal += 1
            state.bestTier[next.chain] = max(state.bestTier[next.chain] ?? 0, next.tier)
            let cleared = clearDebris(around: to)
            let bubble = maybeBubble(next, near: to)
            return .merged(item: next, cleared: cleared, bubble: bubble)
        case (.generator(let x), .generator(let y)?) where x == y:
            let tiers = catalog.chain(x.chain)?.generatorTiers ?? 1
            guard x.tier + 1 < tiers else { return swap(from, to) }
            let next = GeneratorPiece(chain: x.chain, tier: x.tier + 1)
            state.cells[to] = .generator(next)
            state.cells[from] = nil
            return .mergedGenerator(next)
        case (_, nil):
            state.cells[to] = a
            state.cells[from] = nil
            return .moved
        default:
            return swap(from, to)
        }
    }

    private func swap(_ a: Int, _ b: Int) -> MoveResult {
        state.cells.swapAt(a, b)
        return .swapped
    }

    private func clearDebris(around index: Int) -> [Int] {
        var cleared: [Int] = []
        for n in neighbors(of: index) {
            if case .debris(let layers) = state.cells[n] {
                state.cells[n] = layers > 1 ? .debris(layers - 1) : nil
                cleared.append(n)
            }
        }
        return cleared
    }

    private func maybeBubble(_ item: Item, near index: Int) -> Int? {
        guard item.tier >= balance.bubbleMinTier,
              Double.random(in: 0..<1, using: &rng) < balance.bubbleChance,
              let cell = nearestEmpty(to: index) else { return nil }
        state.cells[cell] = .bubble(item, expiresAt: now().addingTimeInterval(balance.bubbleLifetime))
        return cell
    }

    // MARK: - Пузыри

    /// Убирает пузыри с истекшим сроком. Возвращает клетки, где они были.
    @discardableResult
    public func expireBubbles() -> [Int] {
        let t = now()
        var removed: [Int] = []
        for i in state.cells.indices {
            if case .bubble(_, let expiresAt) = state.cells[i], expiresAt <= t {
                state.cells[i] = nil
                removed.append(i)
            }
        }
        return removed
    }

    /// Открывает пузырь за кристаллы: предмет остается на поле.
    public func popBubble(at index: Int) -> Bool {
        guard case .bubble(let item, _) = piece(at: index), state.gems >= balance.bubblePopCost else { return false }
        state.gems -= balance.bubblePopCost
        state.cells[index] = .item(item)
        return true
    }

    // MARK: - Продажа и корзина

    public func sellPrice(_ item: Item) -> Int { item.value }

    /// Продает предмет с поля. Возвращает полученные монеты (0, если продавать нечего).
    public func sell(at index: Int) -> Int {
        guard let item = piece(at: index)?.item else { return 0 }
        state.cells[index] = nil
        let price = sellPrice(item)
        state.coins += price
        return price
    }

    public func store(at index: Int) -> Bool {
        guard let item = piece(at: index)?.item, state.basket.count < state.basketSize else { return false }
        state.basket.append(item)
        state.cells[index] = nil
        return true
    }

    /// Достает предмет из корзины в ближайшую к центру свободную клетку. Возвращает клетку.
    public func retrieve(basketIndex: Int) -> Int? {
        guard state.basket.indices.contains(basketIndex) else { return nil }
        let center = (balance.rows / 2) * balance.cols + balance.cols / 2
        guard let cell = nearestEmpty(to: center) else { return nil }
        state.cells[cell] = .item(state.basket.remove(at: basketIndex))
        return cell
    }

    // MARK: - Заказы

    public func canDeliver(_ order: Order) -> Bool {
        var pool = state.cells.compactMap { $0?.item }
        for need in order.needs {
            guard let i = pool.firstIndex(of: need) else { return false }
            pool.remove(at: i)
        }
        return true
    }

    /// Предметы на поле, которые нужны текущим заказам: сцена их подсвечивает.
    public var neededItems: Set<Item> {
        Set(state.orders.flatMap(\.needs))
    }

    /// Отдает заказ: забирает предметы с поля, начисляет награду и выдает новый заказ.
    public func deliver(orderId: Int) -> Order? {
        guard let index = state.orders.firstIndex(where: { $0.id == orderId }) else { return nil }
        let order = state.orders[index]
        guard canDeliver(order) else { return nil }
        for need in order.needs {
            if let i = state.cells.firstIndex(where: { $0?.item == need }) { state.cells[i] = nil }
        }
        state.orders.remove(at: index)
        state.coins += order.coins
        state.stars += order.stars
        state.xp += order.xp
        state.ordersTotal += 1
        refillOrders()
        return order
    }

    public func refillOrders() {
        let chains = state.unlockedChains.filter { catalog.chain($0) != nil }
        guard !chains.isEmpty else { return }
        while state.orders.count < balance.orderSlots {
            state.orders.append(makeOrder(chains: chains))
        }
    }

    private func makeOrder(chains: [String]) -> Order {
        let shuffled = chains.shuffled(using: &rng)
        var needs = [randomNeed(chain: shuffled[0])]
        if shuffled.count > 1, Double.random(in: 0..<1, using: &rng) < 0.4 {
            needs.append(randomNeed(chain: shuffled[1], easier: true))
        }
        let value = needs.reduce(0) { $0 + $1.value }
        let order = Order(id: state.nextOrderId,
                          needs: needs,
                          coins: value * 3,
                          stars: max(1, value / 8),
                          xp: value)
        state.nextOrderId += 1
        return order
    }

    /// Ступень в заказе на одну выше лучшей собранной, но не выше последней ступени цепочки.
    private func randomNeed(chain: String, easier: Bool = false) -> Item {
        let maxTier = catalog.maxTier(of: chain)
        var top = min(maxTier, max(2, (state.bestTier[chain] ?? 1) + 1))
        if easier { top = max(1, top - 1) }
        let low = min(1, top)
        return Item(chain: chain, tier: Int.random(in: low...top, using: &rng))
    }
}

// MARK: - Для тестов и отладочного меню

extension Game {
    func testSet(_ index: Int, _ piece: Piece?) { state.cells[index] = piece }
    func testSetEnergy(_ value: Int) { state.energy = value; state.energyUpdatedAt = now() }
    func testSetGems(_ value: Int) { state.gems = value }
    func testSetOrders(_ orders: [Order]) {
        state.orders = orders
        refillOrders()
    }
}
