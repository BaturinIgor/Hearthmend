import Foundation

/// Маленькое событие выходных «Обмен»: игрок начинает с веточки и шесть раз меняется с жителями.
/// Каждый раз трое жителей предлагают обмен: «дам тебе вот это за твою вещь и предмет с поля».
/// Простой обмен просит то, что уже есть, щедрый - предмет на ступень-две выше, зато дает больше.
/// Последний обмен приносит рыночный прилавок того цвета, какой у жителя, с которым поменялись.
/// Если почти все обмены были щедрыми, в придачу дарят палатку.
public struct BarterOffer: Codable, Equatable {
    public var friend: String
    /// Какой предмет с поля отдать.
    public var needs: Item
    /// 0 - простой обмен, 1 - средний, 2 - щедрый.
    public var level: Int
    /// Что игрок получит: картинка вещи, а на последнем шаге - украшение.
    public var gives: String
    public var coins: Int
    public var energy: Int
}

public struct BarterState: Codable, Equatable {
    public var key: String
    /// Вещь, которая сейчас у игрока.
    public var good: String
    /// Сколько обменов сделано.
    public var step: Int = 0
    public var offers: [BarterOffer] = []
    /// Все вещи, через которые прошел игрок, начиная с веточки.
    public var trail: [String]
    /// Сумма щедрости обменов (1 за простой, 3 за щедрый).
    public var value: Int = 0
    public var stall: String?
    public var tent = false
    public var gems = 0

    public var finished: Bool { step >= Barter.steps }
}

public enum Barter {
    public static let steps = 6
    public static let start = "forest_twig"
    /// Что дают за обмен на каждом шаге: простой, средний, щедрый.
    public static let goods: [[String]] = [
        ["garden_carrot", "apiary_honey", "orchard_peach"],
        ["farm_cheese", "fishing_pike", "crystal_shard"],
        ["forest_stool", "quarry_lantern", "apiary_potted"],
        ["farm_picnic", "garden_barrel", "crystal_geode"],
        ["forest_bench", "quarry_cart", "fishing_boat"],
    ]
    /// Цвет прилавка у каждого жителя.
    public static let stallOf: [String: String] = [
        "mila": "decor_stall_red", "katy": "decor_stall_red",
        "tim": "decor_stall_green", "bruno": "decor_stall_green",
        "mike": "decor_stall_blue", "fin": "decor_stall_blue",
        "jack": "decor_stall_orange", "chloe": "decor_stall_orange",
    ]
    public static let tent = "decor_tent"
    /// С какой суммы щедрости дарят палатку: из шести обменов хотя бы четыре щедрых.
    public static let tentValue = 16
    /// Кристаллы в конце: по одному за каждое очко щедрости.
    public static func gems(value: Int) -> Int { value }
}

extension Balance {
    /// «Обмен» открывается с этого уровня.
    public static let barterLevel = 5
}

extension Game {
    /// Что принес обмен (для тоста и празднования).
    public struct BarterTrade: Equatable {
        public var offer: BarterOffer
        public var finished = false
        public var stall: String?
        public var tent = false
        public var gems = 0
    }

    public var barterUnlocked: Bool { state.level >= Balance.barterLevel }

    /// Текущий обмен или nil, если не выходные. Новые выходные начинают обмен с веточки.
    public var barter: BarterState? {
        guard barterUnlocked, let s = eventSchedule(at: now()) else { return nil }
        if state.barter?.key != s.key {
            var b = BarterState(key: s.key, good: Barter.start, trail: [Barter.start])
            b.offers = makeBarterOffers(step: 0)
            state.barter = b
        }
        return state.barter
    }

    public var barterEndsAt: Date? { barter == nil ? nil : eventEndsAt }

    public func canBarter(_ index: Int) -> Bool {
        guard let b = barter, !b.finished, b.offers.indices.contains(index) else { return false }
        return canDeliver(Order(id: -1, needs: [b.offers[index].needs], coins: 0, stars: 0, xp: 0))
    }

    /// Есть ли обмен, который можно сделать прямо сейчас (красная точка).
    public var barterReady: Bool {
        guard let b = barter, !b.finished else { return false }
        return b.offers.indices.contains { canBarter($0) }
    }

    /// Меняется с жителем: забирает предмет с поля, отдает награду и показывает новые предложения.
    @discardableResult
    public func barter(_ index: Int) -> BarterTrade? {
        guard canBarter(index), var b = state.barter else { return nil }
        let offer = b.offers[index]
        if let i = state.cells.firstIndex(where: { $0?.item == offer.needs }) { state.cells[i] = nil }
        grant(ProductReward(energy: offer.energy, coins: offer.coins))
        b.step += 1
        b.value += offer.level + 1
        b.good = offer.gives
        b.trail.append(offer.gives)
        var trade = BarterTrade(offer: offer)
        if b.finished {
            b.offers = []
            b.stall = offer.gives
            b.tent = b.value >= Barter.tentValue
            b.gems = Barter.gems(value: b.value)
            state.gems += b.gems
            giveDecor(offer.gives)
            if b.tent { giveDecor(Barter.tent) }
            trade.finished = true
            trade.stall = b.stall
            trade.tent = b.tent
            trade.gems = b.gems
        } else {
            b.offers = makeBarterOffers(step: b.step)
        }
        state.barter = b
        return trade
    }

    /// Трое жителей с цепочек, что уже открыты. Чем дальше обмен, тем выше ступени.
    func makeBarterOffers(step: Int) -> [BarterOffer] {
        var friends = Friends.all.filter { f in
            Friends.chain(of: f).map { state.unlockedChains.contains($0) && catalog.chain($0) != nil } ?? false
        }
        if friends.isEmpty { friends = ["tim"] }
        friends.shuffle(using: &rng)
        let base = 1 + step / 2
        return (0..<3).map { level in
            let friend = friends[level % friends.count]
            let chain = Friends.chain(of: friend) ?? "garden"
            let best = max(1, state.bestTier[chain] ?? 1)
            let top = max(1, catalog.orderTop(of: chain))
            let tier = max(1, min(top, base + level, best + level))
            let needs = Item(chain: chain, tier: tier)
            let last = step == Barter.steps - 1
            let gives = last ? (Barter.stallOf[friend] ?? "decor_stall_green") : Barter.goods[min(step, Barter.goods.count - 1)][level]
            return BarterOffer(friend: friend, needs: needs, level: level, gives: gives,
                               coins: needs.value * 2, energy: level == 2 ? 10 : 0)
        }
    }
}
