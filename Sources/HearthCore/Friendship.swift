import Foundation

/// Дружба с жителями. Каждый заказ просит житель, связанный с цепочкой первого предмета,
/// и отданный заказ добавляет ему сердечко. На пяти порогах житель дарит подарок, последний
/// подарок - его личное украшение для деревни.
public enum Friends {
    public static let byChain: [String: String] = [
        "garden": "tim", "forest": "jack", "quarry": "mike",
        "apiary": "mila", "farm": "chloe", "orchard": "katy",
        "fishing": "fin", "crystal": "bruno",
    ]
    /// Порядок, в котором жители появляются в игре.
    public static let all = ["tim", "jack", "mike", "mila", "chloe", "katy", "fin", "bruno"]
    /// Сколько сердечек нужно для каждого уровня дружбы.
    public static let thresholds = [3, 10, 25, 50, 100]
    public static var maxLevel: Int { thresholds.count }

    public static func chain(of resident: String) -> String? {
        byChain.first { $0.value == resident }?.key
    }

    public static func requester(of order: Order) -> String {
        byChain[order.needs.first?.chain ?? ""] ?? "tim"
    }

    public static func decor(of resident: String) -> String { "decor_friend_\(resident)" }

    /// Подарок за уровень дружбы (с 1).
    public static func reward(level: Int, resident: String) -> ProductReward {
        switch level {
        case 1: return ProductReward(coins: 150)
        case 2: return ProductReward(energy: 25)
        case 3: return ProductReward(gems: 8)
        case 4: return ProductReward(gems: 5, energy: 40)
        default: return ProductReward(gems: 15, decor: decor(of: resident))
        }
    }
}

/// Житель поднялся на новый уровень дружбы (для тоста).
public struct FriendLevelUp: Equatable {
    public let resident: String
    public let level: Int
}

extension Game {
    public func friendHearts(_ resident: String) -> Int { state.friendHearts[resident] ?? 0 }

    public func friendLevel(_ resident: String) -> Int {
        let hearts = friendHearts(resident)
        return Friends.thresholds.filter { hearts >= $0 }.count
    }

    /// Сердечки от текущего уровня до следующего: (есть, нужно). На последнем уровне nil.
    public func friendProgress(_ resident: String) -> (have: Int, need: Int)? {
        let level = friendLevel(resident)
        guard level < Friends.maxLevel else { return nil }
        let from = level == 0 ? 0 : Friends.thresholds[level - 1]
        return (friendHearts(resident) - from, Friends.thresholds[level] - from)
    }

    /// Житель уже в деревне: его цепочка открыта.
    public func friendMet(_ resident: String) -> Bool {
        guard let chain = Friends.chain(of: resident) else { return false }
        return state.unlockedChains.contains(chain)
    }

    public func friendClaimedLevel(_ resident: String) -> Int { state.friendClaimed[resident] ?? 0 }

    public func friendCanClaim(_ resident: String) -> Bool {
        friendLevel(resident) > friendClaimedLevel(resident)
    }

    /// Сколько подарков жителей можно забрать.
    public var friendsClaimable: Int {
        Friends.all.reduce(0) { $0 + max(0, friendLevel($1) - friendClaimedLevel($1)) }
    }

    /// Жители на последнем уровне дружбы.
    public var bestFriends: Int { Friends.all.filter { friendLevel($0) >= Friends.maxLevel }.count }

    /// Забрать следующий подарок жителя.
    public func claimFriend(_ resident: String) -> ProductReward? {
        guard friendCanClaim(resident) else { return nil }
        let level = friendClaimedLevel(resident) + 1
        state.friendClaimed[resident] = level
        let reward = Friends.reward(level: level, resident: resident)
        grant(reward)
        // лучший друг дарит генератор своей цепочки: его можно слить с таким же
        if level == Friends.maxLevel, let chain = Friends.chain(of: resident), state.unlockedChains.contains(chain) {
            state.pendingGenerators.append(chain)
            placePendingGenerators()
        }
        return reward
    }

    /// Сердечко жителю за отданный заказ. Возвращает новый уровень, если он вырос.
    func addFriendship(for order: Order) -> FriendLevelUp? {
        let resident = Friends.requester(of: order)
        let before = friendLevel(resident)
        state.friendHearts[resident, default: 0] += 1
        let after = friendLevel(resident)
        return after > before ? FriendLevelUp(resident: resident, level: after) : nil
    }
}
