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
    public var bubblePopCost = 5
    public var basketSize = 6
    public var startGems = 20
    public var startCoins = 0
    /// На каждую ступень генератора вероятность сразу выдать предмет 2-й ступени.
    public var generatorUpgradeChance = 0.15
    /// Сколько верхних рядов при старте закрыто завалом.
    public var debrisRows = 3

    public init() {}

    public var cellCount: Int { cols * rows }
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
