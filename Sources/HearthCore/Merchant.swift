import Foundation

/// Странствующий торговец: время от времени заезжает в деревню с особым заказом из трех предметов
/// разных цепочек, на ступенях около лучших собранных. Ждет несколько часов. За такой заказ звезд
/// не дают, зато дают кристаллы, монеты, а каждый третий раз - редкое украшение.
public struct MerchantVisit: Codable, Equatable {
    public var needs: [Item]
    public var leavesAt: Date
    public var coins: Int
    public var gems: Int
    public var energy: Int
    public var decor: String?
}

public enum Merchant {
    /// Украшения торговца, по кругу.
    public static let decor = ["decor_picnic", "decor_lantern", "decor_barrel_green", "decor_barrel_red"]
}

extension Balance {
    /// Счастливое слияние: с какой ступени, как часто и сколько энергии максимум.
    public static let luckyMinTier = 2
    public static let luckyChance = 0.04
    public static let luckyMaxEnergy = 4

    /// Торговец приходит с этого уровня игрока.
    public static let merchantLevel = 6
    /// Сколько торговец ждет и через сколько приходит снова.
    public static let merchantStay: TimeInterval = 4 * 3600
    public static let merchantGap: TimeInterval = 3 * 3600
}

extension Game {
    public var merchantUnlocked: Bool { state.level >= Balance.merchantLevel }

    /// Обновляет торговца по часам: уезжает, когда вышло время, и приезжает, когда пора.
    /// Возвращает true, если торговец только что приехал.
    @discardableResult
    public func updateMerchant() -> Bool {
        let t = now()
        if let visit = state.merchant, t >= visit.leavesAt {
            state.merchant = nil
            state.merchantNextAt = visit.leavesAt.addingTimeInterval(Balance.merchantGap)
        }
        guard state.merchant == nil, merchantUnlocked else { return false }
        guard let next = state.merchantNextAt else {
            // первый раз торговец приезжает сразу, как откроется
            state.merchant = makeMerchant(at: t)
            return true
        }
        guard t >= next else { return false }
        // если игрок долго не заходил, торговец ждет его с момента входа
        state.merchant = makeMerchant(at: max(t, next))
        return true
    }

    /// Через сколько приедет торговец (nil, если он здесь или еще не открыт).
    public var merchantArrivesIn: TimeInterval? {
        guard state.merchant == nil, merchantUnlocked, let next = state.merchantNextAt else { return nil }
        return max(0, next.timeIntervalSince(now()))
    }

    public func canDeliverMerchant() -> Bool {
        guard let visit = state.merchant else { return false }
        return canDeliver(Order(id: -1, needs: visit.needs, coins: 0, stars: 0, xp: 0))
    }

    /// Отдать торговцу все три предмета.
    public func deliverMerchant() -> MerchantVisit? {
        guard let visit = state.merchant, now() < visit.leavesAt, canDeliverMerchant() else { return nil }
        for need in visit.needs {
            if let i = state.cells.firstIndex(where: { $0?.item == need }) { state.cells[i] = nil }
        }
        grant(ProductReward(gems: visit.gems, energy: visit.energy, coins: visit.coins, decor: visit.decor))
        state.merchant = nil
        state.merchantsServed += 1
        state.merchantNextAt = now().addingTimeInterval(Balance.merchantGap)
        return visit
    }

    private func makeMerchant(at t: Date) -> MerchantVisit {
        let chains = state.unlockedChains.filter { catalog.chain($0) != nil }.shuffled(using: &rng)
        var needs: [Item] = []
        for i in 0..<3 {
            let chain = chains[i % chains.count]
            let best = state.bestTier[chain] ?? 1
            let top = min(catalog.maxTier(of: chain), max(2, best))
            let tier = max(1, top - Int.random(in: 0...1, using: &rng))
            needs.append(Item(chain: chain, tier: tier))
        }
        let value = needs.reduce(0) { $0 + $1.value }
        let third = (state.merchantsServed + 1) % 3 == 0
        return MerchantVisit(needs: needs,
                             leavesAt: t.addingTimeInterval(Balance.merchantStay),
                             coins: value * 4,
                             gems: 6,
                             energy: third ? 0 : 20,
                             decor: third ? Merchant.decor[(state.merchantsServed / 3) % Merchant.decor.count] : nil)
    }
}
