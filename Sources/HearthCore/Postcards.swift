import Foundation

/// Открытки: каждый заказ приносит кусочек открытки с видом деревни. Собрал все кусочки - получил
/// кристаллы, монеты и украшение, и начинается следующая открытка. Виды идут по кругу.
public enum Postcards {
    /// Виды деревни: картинки postcard_<id> собирает tools/village_map.py.
    public static let views = ["square", "farmstead", "riverside", "orchard", "hilltop", "mine", "fair"]
    /// Украшение за каждую открытку, по кругу.
    public static let decor = ["decor_bush", "decor_flowers_red", "decor_mushroom", "decor_nest",
                               "decor_flowers_purple", "decor_logs", "decor_bench", "decor_trough"]
}

public struct PostcardReward: Equatable {
    /// Какой по счету кусочек открылся (с 1) и сколько всего.
    public var piece: Int
    public var of: Int
    /// Заполнено, когда открытка собрана.
    public var completed: String?
    public var gems = 0
    public var coins = 0
    public var decor: String?
}

extension Game {
    public var postcardView: String { Postcards.views[state.postcardIndex % Postcards.views.count] }

    /// Добавляет кусочек за заказ и выдает награду за собранную открытку.
    func addPostcardPiece() -> PostcardReward {
        let total = balance.postcardPieces
        state.postcardPieces += 1
        var reward = PostcardReward(piece: state.postcardPieces, of: total)
        if state.postcardPieces >= total {
            reward.completed = postcardView
            reward.gems = balance.postcardGems
            reward.coins = balance.postcardCoins
            reward.decor = Postcards.decor[state.postcardIndex % Postcards.decor.count]
            state.gems += reward.gems
            state.coins += reward.coins
            if let decor = reward.decor { state.decorOwned[decor, default: 0] += 1 }
            state.postcardIndex += 1
            state.postcardPieces = 0
        }
        return reward
    }
}
