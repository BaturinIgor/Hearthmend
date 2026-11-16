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

    /// Магазин: пачка энергии за кристаллы, энергия за монеты (несколько раз в день, дорожает),
    /// места в корзине за монеты.
    public var energyPack = 100
    public var coinEnergyAmount = 25
    public var coinEnergyBasePrice = 300
    public var coinEnergyPerDay = 3
    public var basketMax = 12
    public var basketSlotBasePrice = 500

    /// Копилка: кристаллов за заказ, потолок и с какого количества ее можно разбить.
    public var piggyPerOrder = 2
    public var piggyMax = 300
    public var piggyMin = 120

    /// Ускорение генераторов x2 открывается с этого уровня.
    public var boostLevel = 6
    /// Открытки: кусочков в открытке и награда за собранную.
    public var postcardPieces = 9
    public var postcardGems = 10
    public var postcardCoins = 100

    /// Карточка штампов: штамп за каждую покупку, за полную карточку кристаллы и украшение.
    public var stampsPerCard = 6
    public var stampCardGems = 150

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
    /// Покупки и магазин.
    public var vipUntil: Date?
    public var purchasedOneTime: [String] = []
    public var grantedTransactions: [String] = []
    public var coinEnergyDay: Date?
    public var coinEnergyBought: Int = 0
    /// Ежедневная награда.
    public var dailyClaimedAt: Date?
    public var dailyStreak: Int = 0
    /// Событие выходных: ключ недели, ленточки, сколько ступеней выдано, выбор жителя.
    public var eventKey: String?
    public var eventTokens: Int = 0
    public var eventClaimed: Int = 0
    public var eventChoice: String?
    /// Украшения: в запасе и на карте.
    public var decorOwned: [String: Int] = [:]
    public var placedDecor: [PlacedDecor] = []
    public var nextDecorId: Int = 1
    /// Шаг обучения (TutorialStep). Старые сохранения с отданными заказами обучение пропускают.
    public var tutorialStep: Int = 0
    /// Копилка: кристаллы, которые капают за заказы и достаются при покупке.
    public var piggyGems: Int = 0
    /// Пропуск события и набор выходных: для какого события (eventKey) куплены.
    public var eventPassKey: String?
    public var eventPassClaimed: Int = 0
    public var weekendBundleKey: String?
    /// Ускорение генераторов x2 включено.
    public var boostOn: Bool = false
    /// Открытки: сколько собрано и сколько кусочков у текущей.
    public var postcardIndex: Int = 0
    public var postcardPieces: Int = 0
    public var stamps: Int = 0
    public var stampCards: Int = 0

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
        case vipUntil, purchasedOneTime, grantedTransactions, coinEnergyDay, coinEnergyBought, dailyClaimedAt, dailyStreak
        case eventKey, eventTokens, eventClaimed, eventChoice, decorOwned, placedDecor, nextDecorId
        case piggyGems, eventPassKey, eventPassClaimed, weekendBundleKey, boostOn, postcardIndex, postcardPieces, stamps, stampCards
        case tutorialStep
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
        vipUntil = try c.decodeIfPresent(Date.self, forKey: .vipUntil)
        purchasedOneTime = try c.decodeIfPresent([String].self, forKey: .purchasedOneTime) ?? []
        grantedTransactions = try c.decodeIfPresent([String].self, forKey: .grantedTransactions) ?? []
        coinEnergyDay = try c.decodeIfPresent(Date.self, forKey: .coinEnergyDay)
        coinEnergyBought = try c.decodeIfPresent(Int.self, forKey: .coinEnergyBought) ?? 0
        dailyClaimedAt = try c.decodeIfPresent(Date.self, forKey: .dailyClaimedAt)
        dailyStreak = try c.decodeIfPresent(Int.self, forKey: .dailyStreak) ?? 0
        eventKey = try c.decodeIfPresent(String.self, forKey: .eventKey)
        eventTokens = try c.decodeIfPresent(Int.self, forKey: .eventTokens) ?? 0
        eventClaimed = try c.decodeIfPresent(Int.self, forKey: .eventClaimed) ?? 0
        eventChoice = try c.decodeIfPresent(String.self, forKey: .eventChoice)
        decorOwned = try c.decodeIfPresent([String: Int].self, forKey: .decorOwned) ?? [:]
        placedDecor = try c.decodeIfPresent([PlacedDecor].self, forKey: .placedDecor) ?? []
        nextDecorId = try c.decodeIfPresent(Int.self, forKey: .nextDecorId) ?? 1
        tutorialStep = try c.decodeIfPresent(Int.self, forKey: .tutorialStep)
            ?? (ordersTotal > 0 ? TutorialStep.done.rawValue : 0)
        piggyGems = try c.decodeIfPresent(Int.self, forKey: .piggyGems) ?? 0
        eventPassKey = try c.decodeIfPresent(String.self, forKey: .eventPassKey)
        eventPassClaimed = try c.decodeIfPresent(Int.self, forKey: .eventPassClaimed) ?? 0
        weekendBundleKey = try c.decodeIfPresent(String.self, forKey: .weekendBundleKey)
        boostOn = try c.decodeIfPresent(Bool.self, forKey: .boostOn) ?? false
        postcardIndex = try c.decodeIfPresent(Int.self, forKey: .postcardIndex) ?? 0
        postcardPieces = try c.decodeIfPresent(Int.self, forKey: .postcardPieces) ?? 0
        stamps = try c.decodeIfPresent(Int.self, forKey: .stamps) ?? 0
        stampCards = try c.decodeIfPresent(Int.self, forKey: .stampCards) ?? 0
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
