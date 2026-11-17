import Foundation

/// Ящики и ресурсы на поле: ящик с предметами, монеты, энергия и кристаллы. Два одинаковых сливаются
/// в следующий уровень, и там чуть больше, чем в двух по отдельности, поэтому копить выгодно.
/// Первый тап выбирает, второй забирает: ресурс целиком, а из ящика по одному предмету.
public enum ChestKind: String, Codable, CaseIterable {
    case items, coins, energy, gems
}

public struct Chest: Codable, Hashable {
    public let kind: ChestKind
    public let level: Int
    /// Сколько предметов осталось в начатом ящике. nil - ящик целый.
    public var left: Int?

    public init(kind: ChestKind, level: Int, left: Int? = nil) {
        self.kind = kind
        self.level = level
        self.left = left
    }

    public var maxLevel: Int { Balance.chestAmounts(kind).count - 1 }
    /// Сколько всего внутри: предметов, монет, энергии или кристаллов.
    public var amount: Int {
        let amounts = Balance.chestAmounts(kind)
        return amounts[min(max(level, 0), amounts.count - 1)]
    }
    /// Сколько предметов еще можно достать (для ресурсов - вся сумма).
    public var remaining: Int { left ?? amount }
    /// Начатый ящик уже не сливается.
    public var canMerge: Bool { left == nil && level < maxLevel }
}

/// Предмет, выпавший из ящика, и клетка, куда он лег.
public struct ChestSpill: Equatable {
    public let cell: Int
    public let item: Item
}

public struct ChestReward: Equatable {
    public var coins = 0
    public var energy = 0
    public var gems = 0
    public var items: [ChestSpill] = []
}

extension Balance {
    /// Каждый уровень примерно в 2,2 раза больше предыдущего: слить выгоднее, чем забрать по одному.
    public static let chestItems = [3, 5, 6, 8]
    public static let chestItemTiers: [ClosedRange<Int>] = [0...1, 1...1, 1...2, 2...3]
    public static let chestEnergy = [2, 5, 11, 24, 52, 110]
    public static let chestGems = [1, 3, 7, 15, 33, 72, 160, 350]
    public static let chestCoins = [10, 22, 48, 105, 230, 500, 1_100, 2_400, 5_200, 11_500]

    public static func chestAmounts(_ kind: ChestKind) -> [Int] {
        switch kind {
        case .items: return chestItems
        case .coins: return chestCoins
        case .energy: return chestEnergy
        case .gems: return chestGems
        }
    }

    /// Ящик или ресурс может выпасть при слиянии в предмет этой ступени и выше (3-я на экране).
    public static let chestMinTier = 2
    public static let chestChance = 0.03
    /// Какой ящик выпадает при слиянии: предметы чаще всего, кристаллы реже всего.
    public static let chestWeights: [(ChestKind, Double)] = [(.items, 50), (.coins, 25), (.energy, 20), (.gems, 5)]
    /// Ящик за расчищенный ряд зарослей: щедрее на ресурсы.
    public static let rowChestWeights: [(ChestKind, Double)] = [(.items, 35), (.coins, 30), (.energy, 25), (.gems, 10)]
}

extension Game {
    public enum ChestResult: Equatable {
        case opened(ChestReward)
        /// Для ящика с предметами не хватает стольких свободных клеток.
        case needSpace(Int)
        case notChest
    }

    /// Забирает ресурс целиком или достает из ящика один предмет в ближайшую свободную клетку.
    /// Последний предмет ложится на место ящика.
    public func openChest(at index: Int) -> ChestResult {
        guard case .chest(let chest) = piece(at: index) else { return .notChest }
        var reward = ChestReward()
        switch chest.kind {
        case .coins:
            reward.coins = chest.amount
            state.coins += reward.coins
            state.cells[index] = nil
        case .energy:
            reward.energy = chest.amount
            state.energy += reward.energy
            state.cells[index] = nil
        case .gems:
            reward.gems = chest.amount
            state.gems += reward.gems
            state.cells[index] = nil
        case .items:
            let left = chest.remaining
            let last = left <= 1
            guard let cell = last ? index : nearestEmpty(to: index) else { return .needSpace(1) }
            let chains = state.unlockedChains.filter { catalog.chain($0) != nil }
            guard let chain = chains.randomElement(using: &rng) else { return .notChest }
            let tiers = Balance.chestItemTiers[min(max(chest.level, 0), Balance.chestItemTiers.count - 1)]
            let item = Item(chain: chain, tier: min(Int.random(in: tiers, using: &rng), catalog.maxTier(of: chain)))
            state.cells[cell] = .item(item)
            if !last { state.cells[index] = .chest(Chest(kind: .items, level: chest.level, left: left - 1)) }
            lastDiscovery = nil
            discover(item)
            reward.items.append(ChestSpill(cell: cell, item: item))
            guard last else { return .opened(reward) }
        }
        state.chestsOpened += 1
        placePendingGenerators()
        return .opened(reward)
    }

    func randomChestKind(_ weights: [(ChestKind, Double)]) -> ChestKind {
        let total = weights.reduce(0) { $0 + $1.1 }
        var roll = Double.random(in: 0..<total, using: &rng)
        for (kind, w) in weights {
            if roll < w { return kind }
            roll -= w
        }
        return weights.last?.0 ?? .coins
    }

    /// Изредка слияние роняет маленький ящик в ближайшую свободную клетку.
    func maybeChest(_ item: Item, near index: Int) {
        guard item.tier >= Balance.chestMinTier,
              Double.random(in: 0..<1, using: &rng) < Balance.chestChance,
              let cell = nearestEmpty(to: index) else { return }
        state.cells[cell] = .chest(Chest(kind: randomChestKind(Balance.chestWeights), level: 0))
        lastChests.append(cell)
    }

    /// Ставит ящики, которым не хватило места, в свободные клетки.
    func placePendingChests() {
        let center = (balance.rows / 2) * balance.cols + balance.cols / 2
        while let chest = state.pendingChests.first, let cell = nearestEmpty(to: center) {
            state.cells[cell] = .chest(chest)
            state.pendingChests.removeFirst()
            lastChests.append(cell)
        }
    }
}
