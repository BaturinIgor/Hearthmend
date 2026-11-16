import Foundation

/// Покупки в App Store: что дает каждый продукт. ID должны совпадать с App Store Connect
/// и с Hearthmend/Resources/Products.storekit.
public struct ProductReward: Equatable {
    public enum Kind: Equatable {
        case plain
        /// Разбить копилку: кристаллы, накопленные за заказы.
        case piggy
        /// Пропуск события: вторая дорожка наград текущих выходных.
        case eventPass
        /// Набор выходных: раз за событие.
        case weekend
    }

    public var gems = 0
    public var energy = 0
    public var coins = 0
    public var stars = 0
    public var decor: String?
    /// Подписка VIP на столько дней.
    public var vipDays = 0
    /// Покупается один раз (стартовый набор, набор строителя).
    public var oneTime = false
    public var kind: Kind = .plain

    public init(gems: Int = 0, energy: Int = 0, coins: Int = 0, stars: Int = 0, decor: String? = nil,
                vipDays: Int = 0, oneTime: Bool = false, kind: Kind = .plain) {
        self.gems = gems
        self.energy = energy
        self.coins = coins
        self.stars = stars
        self.decor = decor
        self.vipDays = vipDays
        self.oneTime = oneTime
        self.kind = kind
    }
}

public enum Products {
    public static let prefix = "com.personal.hearthmend."
    public static let gemsSmall = prefix + "gems.small"
    public static let gemsMedium = prefix + "gems.medium"
    public static let gemsLarge = prefix + "gems.large"
    public static let gemsChest = prefix + "gems.chest"
    public static let starter = prefix + "starter"
    public static let vipMonthly = prefix + "vip.monthly"
    public static let gemsHuge = prefix + "gems.huge"
    public static let gemsMega = prefix + "gems.mega"
    public static let piggy = prefix + "piggy"
    public static let eventPass = prefix + "event.pass"
    public static let weekendBundle = prefix + "bundle.weekend"
    public static let builder = prefix + "builder"

    /// Награды. Цены задаются в App Store Connect (tools/asc_iap.py): кристаллы 0.99 / 4.99 / 9.99 / 19.99 /
    /// 49.99 / 99.99, стартовый набор 1.99, копилка 2.99, пропуск события 3.99, набор выходных 4.99,
    /// набор строителя 6.99, VIP 4.99 в месяц.
    public static let rewards: [String: ProductReward] = [
        gemsSmall: ProductReward(gems: 80),
        gemsMedium: ProductReward(gems: 450),
        gemsLarge: ProductReward(gems: 1000),
        gemsChest: ProductReward(gems: 2200),
        gemsHuge: ProductReward(gems: 6000),
        gemsMega: ProductReward(gems: 13000),
        starter: ProductReward(gems: 250, energy: 200, coins: 1000, oneTime: true),
        vipMonthly: ProductReward(vipDays: 30),
        piggy: ProductReward(kind: .piggy),
        eventPass: ProductReward(kind: .eventPass),
        weekendBundle: ProductReward(gems: 300, energy: 150, decor: "decor_pond", kind: .weekend),
        builder: ProductReward(gems: 300, stars: 60, decor: "decor_lamp_double", oneTime: true),
    ]

    /// Вторая дорожка пропуска события: по награде на каждую ступень (7 ступеней в events.json).
    public static let eventPassRewards: [EventReward] = [
        EventReward(gems: 30),
        EventReward(energy: 50),
        EventReward(gems: 50),
        EventReward(energy: 80),
        EventReward(decor: "decor_lamp_hanging"),
        EventReward(gems: 100),
        EventReward(gems: 150, energy: 100),
    ]
    /// Если пропуск куплен, а события уже нет (купили в последнюю секунду), - кристаллы взамен.
    public static let eventPassFallbackGems = 450

    public static var all: [String] { rewards.keys.sorted() }
}

extension Game {
    // MARK: - Покупки в App Store

    public var isVIP: Bool {
        guard let until = state.vipUntil else { return false }
        return until > now()
    }

    public func hasBought(_ productId: String) -> Bool {
        state.purchasedOneTime.contains(productId)
    }

    /// Выдает награду за покупку. Одна транзакция выдается один раз, даже если StoreKit
    /// присылает ее повторно (после перезапуска, восстановления или с другого устройства).
    @discardableResult
    public func grantPurchase(productId: String, transactionId: String, expires: Date? = nil) -> Bool {
        guard let reward = Products.rewards[productId],
              !state.grantedTransactions.contains(transactionId) else { return false }
        if reward.oneTime, hasBought(productId) { return false }
        state.grantedTransactions.append(transactionId)
        if state.grantedTransactions.count > 500 { state.grantedTransactions.removeFirst(100) }
        state.gems += reward.gems
        state.energy += reward.energy
        state.coins += reward.coins
        state.stars += reward.stars
        if let decor = reward.decor { state.decorOwned[decor, default: 0] += 1 }
        if reward.oneTime { state.purchasedOneTime.append(productId) }
        switch reward.kind {
        case .plain:
            break
        case .piggy:
            // деньги уже списаны: отдаем все, что накопилось, даже если меньше порога
            state.gems += state.piggyGems
            state.piggyGems = 0
        case .eventPass:
            if activeEvent != nil, let key = state.eventKey, state.eventPassKey != key {
                state.eventPassKey = key
                state.eventPassClaimed = 0
                lastEventRewards += claimEventPassRewards()
            } else {
                state.gems += Products.eventPassFallbackGems
            }
        case .weekend:
            if activeEvent != nil { state.weekendBundleKey = state.eventKey }
        }
        if reward.vipDays > 0 {
            let base = max(state.vipUntil ?? now(), now())
            let until = expires ?? base.addingTimeInterval(Double(reward.vipDays) * 86400)
            state.vipUntil = max(state.vipUntil ?? until, until)
        }
        return true
    }

    /// Можно ли сейчас предложить покупку (магазин прячет то, что купить нельзя).
    public func canOffer(_ productId: String) -> Bool {
        guard let reward = Products.rewards[productId] else { return false }
        if reward.oneTime, hasBought(productId) { return false }
        switch reward.kind {
        case .plain: return true
        case .piggy: return state.piggyGems >= balance.piggyMin
        case .eventPass: return activeEvent != nil && !hasEventPass
        case .weekend:
            guard activeEvent != nil else { return false }
            return state.weekendBundleKey != state.eventKey
        }
    }

    // MARK: - Копилка

    /// Копилка наполняется за каждый заказ. Разбить ее можно покупкой, когда накопилось piggyMin.
    func fillPiggy() {
        state.piggyGems = min(balance.piggyMax, state.piggyGems + balance.piggyPerOrder)
    }

    public var piggyFull: Bool { state.piggyGems >= balance.piggyMax }

    // MARK: - Пропуск события

    public var hasEventPass: Bool {
        // activeEvent первым: он сбрасывает ключ, если наступило новое событие
        guard activeEvent != nil, let key = state.eventKey else { return false }
        return state.eventPassKey == key
    }

    /// Награды второй дорожки за все уже открытые ступени, если пропуск куплен.
    @discardableResult
    func claimEventPassRewards() -> [EventReward] {
        guard hasEventPass else { return [] }
        var rewards: [EventReward] = []
        let upTo = min(state.eventClaimed, Products.eventPassRewards.count)
        while state.eventPassClaimed < upTo {
            let r = Products.eventPassRewards[state.eventPassClaimed]
            state.gems += r.gems
            state.energy += r.energy
            state.coins += r.coins
            if let decor = r.decor { state.decorOwned[decor, default: 0] += 1 }
            state.eventPassClaimed += 1
            rewards.append(r)
        }
        return rewards
    }

    /// Подписка из StoreKit: срок действия по последней транзакции.
    public func updateVIP(expires: Date?) {
        state.vipUntil = expires
    }

    // MARK: - Магазин внутри игры

    /// Энергия за кристаллы: ровно по курсу energyPerGem, без скидок, чтобы не было выгодных петель.
    public var energyPackGems: Int { balance.energyPack / balance.energyPerGem }

    public func buyEnergyWithGems() -> Bool {
        guard state.gems >= energyPackGems else { return false }
        state.gems -= energyPackGems
        state.energy += balance.energyPack
        return true
    }

    /// Энергия за монеты: несколько раз в день, каждый раз дороже. Сбрасывается в начале суток.
    public var coinEnergyPrice: Int? {
        let bought = coinEnergyBoughtToday
        guard bought < balance.coinEnergyPerDay else { return nil }
        return balance.coinEnergyBasePrice << bought
    }

    var coinEnergyBoughtToday: Int {
        guard let day = state.coinEnergyDay, Calendar.current.isDate(day, inSameDayAs: now()) else { return 0 }
        return state.coinEnergyBought
    }

    public func buyEnergyWithCoins() -> Bool {
        guard let price = coinEnergyPrice, state.coins >= price else { return false }
        let bought = coinEnergyBoughtToday
        state.coins -= price
        state.energy += balance.coinEnergyAmount
        state.coinEnergyDay = now()
        state.coinEnergyBought = bought + 1
        return true
    }

    /// Новое место в корзине за монеты, каждое дороже.
    public var basketSlotPrice: Int? {
        guard state.basketSize < balance.basketMax else { return nil }
        return balance.basketSlotBasePrice * (state.basketSize - balance.basketSize + 1)
    }

    public func buyBasketSlot() -> Bool {
        guard let price = basketSlotPrice, state.coins >= price else { return false }
        state.coins -= price
        state.basketSize += 1
        return true
    }

    /// Открыть кувшин раньше срока за кристаллы (или бесплатно с VIP).
    public var jarOpenGems: Int { isVIP ? 0 : max(1, state.jarEnergy / balance.energyPerGem) }

    @discardableResult
    public func openJarNow() -> Int {
        refreshEnergy()
        let cost = jarOpenGems
        guard state.jarEnergy > 0, state.gems >= cost else { return 0 }
        state.gems -= cost
        return openJar(paid: true)
    }

    // MARK: - Ежедневная награда

    /// Подарок раз в сутки, растет по дням подряд (серия до dailyRewards.count, потом по кругу).
    public var dailyRewardReady: Bool {
        guard let last = state.dailyClaimedAt else { return true }
        return !Calendar.current.isDate(last, inSameDayAs: now())
    }

    /// Какой день серии будет следующим (с 0).
    public var dailyStreakNext: Int {
        guard let last = state.dailyClaimedAt else { return 0 }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: last), to: cal.startOfDay(for: now())).day ?? 0
        if days == 0 { return state.dailyStreak }
        return days == 1 ? state.dailyStreak + 1 : 0
    }

    @discardableResult
    public func claimDaily() -> ProductReward? {
        guard dailyRewardReady else { return nil }
        let day = dailyStreakNext
        var reward = Balance.dailyRewards[day % Balance.dailyRewards.count]
        if isVIP { reward.gems *= 2 }
        state.dailyStreak = day
        state.dailyClaimedAt = now()
        state.gems += reward.gems
        state.energy += reward.energy
        state.coins += reward.coins
        return reward
    }
}

extension Balance {
    /// Награды за дни подряд: седьмой день самый щедрый.
    public static let dailyRewards: [ProductReward] = [
        ProductReward(energy: 20),
        ProductReward(coins: 200),
        ProductReward(gems: 5),
        ProductReward(energy: 40),
        ProductReward(coins: 500),
        ProductReward(gems: 10),
        ProductReward(gems: 20, energy: 100),
    ]
}
