import Foundation

/// Предмет на поле: цепочка и ступень (0 - самая нижняя).
public struct Item: Codable, Hashable {
    public let chain: String
    public let tier: Int

    public init(chain: String, tier: Int) {
        self.chain = chain
        self.tier = tier
    }

    /// Ценность для заказов и продажи: каждая ступень вдвое дороже.
    public var value: Int { 1 << tier }
}

public struct GeneratorPiece: Codable, Hashable {
    public let chain: String
    public let tier: Int

    public init(chain: String, tier: Int) {
        self.chain = chain
        self.tier = tier
    }
}

/// Что лежит в клетке поля. Пустая клетка - nil.
public enum Piece: Codable, Hashable {
    case item(Item)
    case generator(GeneratorPiece)
    /// Завал: снимается слиянием в соседней клетке, число - сколько слоев осталось.
    case debris(Int)
    /// Пузырь с предметом: можно открыть за кристаллы, иначе лопается в срок.
    case bubble(Item, expiresAt: Date)

    public var item: Item? {
        if case .item(let i) = self { return i }
        return nil
    }

    public var isMovable: Bool {
        switch self {
        case .item, .generator: return true
        case .debris, .bubble: return false
        }
    }
}

public struct Order: Codable, Hashable, Identifiable {
    public let id: Int
    public let needs: [Item]
    public let coins: Int
    public let stars: Int
    public let xp: Int

    public init(id: Int, needs: [Item], coins: Int, stars: Int, xp: Int) {
        self.id = id
        self.needs = needs
        self.coins = coins
        self.stars = stars
        self.xp = xp
    }
}

/// Числа баланса. Потом переедут в RemoteConfig, как в Sortelier.
public struct Balance: Equatable {
    public var cols = 7
    public var rows = 9
    public var energyMax = 100
    public var energyRegen: TimeInterval = 120
    public var orderSlots = 4
    /// С какой ступени при слиянии может появиться пузырь и с какой вероятностью.
    public var bubbleMinTier = 3
    public var bubbleChance = 0.1
    public var bubbleLifetime: TimeInterval = 30
    /// Сколько энергии стоит один кристалл в магазине. От этого считаются цены в кристаллах,
    /// чтобы покупка за кристаллы не была выгоднее, чем та же энергия (проверяет бот баланса).
    public var energyPerGem = 2
    public var basketSize = 6
    public var startGems = 20
    public var startCoins = 0
    /// На каждую ступень генератора вероятность сразу выдать предмет 2-й ступени.
    public var generatorUpgradeChance = 0.15
    /// Сколько верхних рядов при старте закрыто завалом.
    public var debrisRows = 3

    /// Кувшин светлячков: энергия, которая сгорела бы на потолке, копится медленнее в кувшине.
    public var jarCapacity = 60
    public var jarSlowdown = 2.0
    /// Бесплатно открыть кувшин можно раз в столько секунд.
    public var jarCooldown: TimeInterval = 8 * 3600

    /// Опыт до следующего уровня: xpBase * уровень^2.
    public var xpBase = 12
    public var levelUpEnergy = 20
    public var levelUpGems = 2

    public init() {}

    public var cellCount: Int { cols * rows }

    /// Цена пузыря в кристаллах: по энергии столько же, сколько стоит сам предмет (2^ступень).
    public func popCost(_ item: Item) -> Int {
        max(1, (item.value + energyPerGem - 1) / energyPerGem)
    }

    /// Сколько опыта нужно, чтобы с уровня level перейти на следующий.
    public func xpToNext(level: Int) -> Int {
        xpBase * level * level
    }
}

/// Сохранение игрока.
public struct GameState: Codable, Equatable {
    public var cells: [Piece?]
    public var energy: Int
    public var energyUpdatedAt: Date
    public var coins: Int
    public var gems: Int
    public var stars: Int
    public var xp: Int
    public var orders: [Order]
    public var nextOrderId: Int
    public var basket: [Item]
    public var basketSize: Int
    /// Лучшая собранная ступень по цепочкам: от нее зависит сложность заказов.
    public var bestTier: [String: Int]
    public var unlockedChains: [String]
    public var mergesTotal: Int
    public var ordersTotal: Int
    /// Выполненные задачи деревни.
    public var completedTasks: [String] = []
    public var level: Int = 1
    /// Генераторы новых цепочек, которым не хватило места на поле: встанут, когда место появится.
    public var pendingGenerators: [String] = []
    /// Энергия в кувшине светлячков и когда его последний раз открыли бесплатно.
    public var jarEnergy: Int = 0
    public var jarOpenedAt: Date?

    public init(cells: [Piece?], energy: Int, energyUpdatedAt: Date, coins: Int, gems: Int, stars: Int, xp: Int,
                orders: [Order], nextOrderId: Int, basket: [Item], basketSize: Int, bestTier: [String: Int],
                unlockedChains: [String], mergesTotal: Int, ordersTotal: Int) {
        self.cells = cells
        self.energy = energy
        self.energyUpdatedAt = energyUpdatedAt
        self.coins = coins
        self.gems = gems
        self.stars = stars
        self.xp = xp
        self.orders = orders
        self.nextOrderId = nextOrderId
        self.basket = basket
        self.basketSize = basketSize
        self.bestTier = bestTier
        self.unlockedChains = unlockedChains
        self.mergesTotal = mergesTotal
        self.ordersTotal = ordersTotal
    }

    private enum CodingKeys: String, CodingKey {
        case cells, energy, energyUpdatedAt, coins, gems, stars, xp, orders, nextOrderId, basket, basketSize
        case bestTier, unlockedChains, mergesTotal, ordersTotal, completedTasks, level, pendingGenerators
        case jarEnergy, jarOpenedAt
    }

    /// Поля, которых не было в старых сохранениях, читаются со значениями по умолчанию.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cells = try c.decode([Piece?].self, forKey: .cells)
        energy = try c.decode(Int.self, forKey: .energy)
        energyUpdatedAt = try c.decode(Date.self, forKey: .energyUpdatedAt)
        coins = try c.decode(Int.self, forKey: .coins)
        gems = try c.decode(Int.self, forKey: .gems)
        stars = try c.decode(Int.self, forKey: .stars)
        xp = try c.decode(Int.self, forKey: .xp)
        orders = try c.decode([Order].self, forKey: .orders)
        nextOrderId = try c.decode(Int.self, forKey: .nextOrderId)
        basket = try c.decode([Item].self, forKey: .basket)
        basketSize = try c.decode(Int.self, forKey: .basketSize)
        bestTier = try c.decode([String: Int].self, forKey: .bestTier)
        unlockedChains = try c.decode([String].self, forKey: .unlockedChains)
        mergesTotal = try c.decode(Int.self, forKey: .mergesTotal)
        ordersTotal = try c.decode(Int.self, forKey: .ordersTotal)
        completedTasks = try c.decodeIfPresent([String].self, forKey: .completedTasks) ?? []
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 1
        pendingGenerators = try c.decodeIfPresent([String].self, forKey: .pendingGenerators) ?? []
        jarEnergy = try c.decodeIfPresent(Int.self, forKey: .jarEnergy) ?? 0
        jarOpenedAt = try c.decodeIfPresent(Date.self, forKey: .jarOpenedAt)
    }
}

/// Детерминированный генератор случайных чисел: тесты и симулятор баланса задают зерно.
public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
