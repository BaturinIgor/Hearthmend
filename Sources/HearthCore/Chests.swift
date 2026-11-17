import Foundation

/// Ящики на поле. Четыре вида и четыре размера: два одинаковых ящика сливаются в следующий,
/// и в нем чуть больше, чем в двух по отдельности, поэтому копить выгодно. Открывается двойным тапом.
public enum ChestKind: String, Codable, CaseIterable {
    case items, coins, energy, gems
}

public struct Chest: Codable, Hashable {
    public let kind: ChestKind
    public let level: Int

    public init(kind: ChestKind, level: Int) {
        self.kind = kind
        self.level = level
    }
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
    public static let chestLevels = 4
    public static let chestCoins = [20, 45, 100, 220]
    public static let chestEnergy = [5, 11, 24, 52]
    public static let chestGems = [2, 5, 11, 24]
    public static let chestItems = [2, 3, 4, 5]
    public static let chestItemTiers: [ClosedRange<Int>] = [0...1, 1...1, 1...2, 2...3]
    /// Ящик может выпасть при слиянии в предмет этой ступени и выше (3-я на экране).
    public static let chestMinTier = 2
    public static let chestChance = 0.02
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

    /// Что лежит в ящике (для подсказки): монеты, энергия, кристаллы или число предметов.
    public static func chestAmount(_ chest: Chest) -> Int {
        let l = min(max(chest.level, 0), Balance.chestLevels - 1)
        switch chest.kind {
        case .items: return Balance.chestItems[l]
        case .coins: return Balance.chestCoins[l]
        case .energy: return Balance.chestEnergy[l]
        case .gems: return Balance.chestGems[l]
        }
    }

    public func openChest(at index: Int) -> ChestResult {
        guard case .chest(let chest) = piece(at: index) else { return .notChest }
        let l = min(max(chest.level, 0), Balance.chestLevels - 1)
        var reward = ChestReward()
        switch chest.kind {
        case .coins:
            reward.coins = Balance.chestCoins[l]
            state.coins += reward.coins
            state.cells[index] = nil
        case .energy:
            reward.energy = Balance.chestEnergy[l]
            state.energy += reward.energy
            state.cells[index] = nil
        case .gems:
            reward.gems = Balance.chestGems[l]
            state.gems += reward.gems
            state.cells[index] = nil
        case .items:
            let count = Balance.chestItems[l]
            // клетка самого ящика тоже освободится
            let free = state.cells.filter { $0 == nil }.count + 1
            guard free >= count else { return .needSpace(count - free) }
            state.cells[index] = nil
            let chains = state.unlockedChains.filter { catalog.chain($0) != nil }
            lastDiscovery = nil
            for _ in 0..<count {
                guard let chain = chains.randomElement(using: &rng), let cell = nearestEmpty(to: index) else { break }
                let tier = min(Int.random(in: Balance.chestItemTiers[l], using: &rng), catalog.maxTier(of: chain))
                let item = Item(chain: chain, tier: tier)
                state.cells[cell] = .item(item)
                discover(item)
                reward.items.append(ChestSpill(cell: cell, item: item))
            }
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
