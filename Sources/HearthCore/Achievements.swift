import Foundation

/// Достижения: долгие цели с тремя ступенями (бронза, серебро, золото). Каждая ступень дает кристаллы.
/// Прогресс считается по тому, что уже хранится в сохранении, поэтому старые игроки сразу
/// получают то, что заработали раньше.
public enum AchievementKind: String, Codable, CaseIterable {
    case merges, orders, buildings, level, album, postcards, friends, merchant, decor
}

public enum Achievements {
    public static let tierGems = [5, 12, 25]

    public static func goals(_ kind: AchievementKind, village: VillageDef, catalog: Catalog) -> [Int] {
        switch kind {
        case .merges: return [100, 1000, 5000]
        case .orders: return [50, 400, 1500]
        case .buildings: return [10, 25, village.allTasks.count]
        case .level: return [5, 12, 20]
        case .album: return [20, 40, catalog.chains.reduce(0) { $0 + catalog.maxTier(of: $1.id) + 1 }]
        case .postcards: return [5, 30, 100]
        case .friends: return [1, 4, Friends.all.count]
        case .merchant: return [3, 15, 40]
        case .decor: return [3, 8, 15]
        }
    }
}

extension Game {
    public func achievementGoals(_ kind: AchievementKind) -> [Int] {
        Achievements.goals(kind, village: village, catalog: catalog)
    }

    public func achievementValue(_ kind: AchievementKind) -> Int {
        switch kind {
        case .merges: return state.mergesTotal
        case .orders: return state.ordersTotal
        case .buildings: return state.completedTasks.count
        case .level: return state.level
        case .album: return state.discovered.count
        case .postcards: return state.postcardIndex
        case .friends: return bestFriends
        case .merchant: return state.merchantsServed
        case .decor: return state.placedDecor.count
        }
    }

    /// Сколько ступеней достигнуто (0...3).
    public func achievementTier(_ kind: AchievementKind) -> Int {
        let value = achievementValue(kind)
        return achievementGoals(kind).filter { value >= $0 }.count
    }

    public func achievementClaimed(_ kind: AchievementKind) -> Int { state.achievementsClaimed[kind.rawValue] ?? 0 }

    public var achievementsClaimable: Int {
        AchievementKind.allCases.reduce(0) { $0 + max(0, achievementTier($1) - achievementClaimed($1)) }
    }

    /// Забрать следующую ступень достижения.
    public func claimAchievement(_ kind: AchievementKind) -> ProductReward? {
        let claimed = achievementClaimed(kind)
        guard achievementTier(kind) > claimed else { return nil }
        state.achievementsClaimed[kind.rawValue] = claimed + 1
        let reward = ProductReward(gems: Achievements.tierGems[claimed])
        grant(reward)
        return reward
    }
}
