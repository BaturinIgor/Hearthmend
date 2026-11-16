import Foundation

/// Карточка штампов: каждая покупка в магазине ставит штамп. Полная карточка дает кристаллы
/// и редкое украшение, и начинается новая. Украшения идут по кругу.
public enum Stamps {
    public static let decor = ["decor_pond", "decor_lamp_double", "decor_lamp_hanging"]
}

public struct StampReward: Equatable {
    /// Штампов на карточке после этой покупки (0, если карточка только что закрылась).
    public var stamps: Int
    public var of: Int
    public var completed = false
    public var gems = 0
    public var decor: String?
}

extension Game {
    public var stampDecor: String { Stamps.decor[state.stampCards % Stamps.decor.count] }

    func addStamp() -> StampReward {
        let total = balance.stampsPerCard
        state.stamps += 1
        guard state.stamps >= total else { return StampReward(stamps: state.stamps, of: total) }
        let reward = StampReward(stamps: 0, of: total, completed: true, gems: balance.stampCardGems, decor: stampDecor)
        state.gems += reward.gems
        if let decor = reward.decor { state.decorOwned[decor, default: 0] += 1 }
        state.stampCards += 1
        state.stamps = 0
        return reward
    }
}
