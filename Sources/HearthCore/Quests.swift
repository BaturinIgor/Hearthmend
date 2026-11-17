import Foundation

/// Задания дня: три задачи на сутки (по UTC), награда за каждую и сундук за все три.
/// Задания выбираются по номеру дня, поэтому у всех игроков в один день они одинаковые по виду,
/// а цели растут с уровнем.
public enum QuestKind: String, Codable, CaseIterable {
    case merge, spawn, deliver, bigMerge
}

public struct Quest: Codable, Equatable {
    public var kind: QuestKind
    public var target: Int
    public var progress: Int = 0
    public var claimed = false

    public var done: Bool { progress >= target }
}

extension Balance {
    /// Ступень (с нуля), начиная с которой слияние считается крупным.
    public static let bigMergeTier = 3

    public func questReward(_ kind: QuestKind) -> ProductReward {
        switch kind {
        case .merge: return ProductReward(coins: 120)
        case .spawn: return ProductReward(energy: 15)
        case .deliver: return ProductReward(gems: 5)
        case .bigMerge: return ProductReward(gems: 6)
        }
    }

    /// Сундук за все три задания дня.
    public var questChest: ProductReward { ProductReward(gems: 10, energy: 25) }

    public func questTarget(_ kind: QuestKind, level: Int) -> Int {
        let l = min(max(level, 1), 12)
        switch kind {
        case .merge: return 15 + 3 * l
        case .spawn: return 25 + 3 * l
        case .deliver: return min(8, 3 + l / 3)
        case .bigMerge: return min(5, 1 + l / 4)
        }
    }
}

extension Game {
    /// Номер дня по UTC: задания сменяются в 00:00 UTC.
    public var questDay: Int { Int(floor(now().timeIntervalSince1970 / 86_400)) }

    /// Задания на сегодня. Если наступил новый день, выдает новые.
    @discardableResult
    public func ensureQuests() -> [Quest] {
        let day = questDay
        if state.questDay != day || state.quests.count != 3 {
            var rng = SplitMix64(seed: UInt64(truncatingIfNeeded: day) &* 2_654_435_761 &+ 17)
            let kinds = QuestKind.allCases.shuffled(using: &rng).prefix(3)
            state.quests = kinds.map { Quest(kind: $0, target: balance.questTarget($0, level: state.level)) }
            state.questDay = day
            state.questChestClaimed = false
        }
        return state.quests
    }

    /// Сколько наград за задания можно забрать (для отметки на кнопке).
    public var questsClaimable: Int {
        let qs = state.questDay == questDay ? state.quests : []
        let rewards = qs.filter { $0.done && !$0.claimed }.count
        let chest = !qs.isEmpty && qs.allSatisfy(\.claimed) && !state.questChestClaimed ? 1 : 0
        return rewards + chest
    }

    func progressQuest(_ kind: QuestKind, by amount: Int = 1) {
        ensureQuests()
        for i in state.quests.indices where state.quests[i].kind == kind && !state.quests[i].claimed {
            state.quests[i].progress = min(state.quests[i].target, state.quests[i].progress + amount)
        }
    }

    /// Забрать награду за выполненное задание.
    public func claimQuest(_ index: Int) -> ProductReward? {
        ensureQuests()
        guard state.quests.indices.contains(index), state.quests[index].done, !state.quests[index].claimed else { return nil }
        state.quests[index].claimed = true
        let reward = balance.questReward(state.quests[index].kind)
        grant(reward)
        return reward
    }

    /// Забрать сундук, когда все три награды получены.
    public func claimQuestChest() -> ProductReward? {
        ensureQuests()
        guard state.quests.allSatisfy(\.claimed), !state.questChestClaimed else { return nil }
        state.questChestClaimed = true
        let reward = balance.questChest
        grant(reward)
        return reward
    }

    func grant(_ reward: ProductReward) {
        state.gems += reward.gems
        state.coins += reward.coins
        state.stars += reward.stars
        if reward.energy > 0 { state.energy += reward.energy }
        if let decor = reward.decor { state.decorOwned[decor, default: 0] += 1 }
    }
}
