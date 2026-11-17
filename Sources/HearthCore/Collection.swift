import Foundation

/// Альбом предметов: каждый новый предмет попадает в альбом, за первую находку дают монеты
/// (за старшие ступени еще и кристаллы), за полностью собранную цепочку - кристаллы.
/// Награды забираются в альбоме вручную: так находки заметны.
public struct CollectionReward: Equatable {
    public var coins = 0
    public var gems = 0
}

extension Balance {
    public func discoveryReward(_ item: Item) -> CollectionReward {
        CollectionReward(coins: 10 * (item.tier + 1), gems: item.tier >= 4 ? item.tier - 2 : 0)
    }

    public var chainCompleteGems: Int { 20 }
}

extension Game {
    public static func collectionKey(_ item: Item) -> String { "\(item.chain)#\(item.tier)" }

    public func isDiscovered(_ item: Item) -> Bool { state.discovered.contains(Game.collectionKey(item)) }
    public func isCollectionClaimed(_ item: Item) -> Bool { state.collectionClaimed.contains(Game.collectionKey(item)) }

    /// Отметить предмет найденным. Возвращает true, если он новый.
    @discardableResult
    func discover(_ item: Item) -> Bool {
        let key = Game.collectionKey(item)
        guard !state.discovered.contains(key) else { return false }
        state.discovered.append(key)
        lastDiscovery = item
        return true
    }

    /// Старые сохранения: все, что игрок уже собирал, считается найденным и оплаченным.
    func migrateCollection() {
        guard state.discovered.isEmpty else { return }
        for (chain, best) in state.bestTier where catalog.chain(chain) != nil {
            for tier in 0...max(0, best) {
                let key = Game.collectionKey(Item(chain: chain, tier: tier))
                state.discovered.append(key)
                state.collectionClaimed.append(key)
            }
        }
        for case .item(let item)? in state.cells { discover(item) }
        lastDiscovery = nil
    }

    /// Сколько наград ждет в альбоме.
    public var collectionClaimable: Int {
        let items = state.discovered.filter { !state.collectionClaimed.contains($0) }.count
        let chains = catalog.chains.filter { chainCollected($0.id) && !state.collectionChains.contains($0.id) }.count
        return items + chains
    }

    public func chainCollected(_ chain: String) -> Bool {
        let top = catalog.maxTier(of: chain)
        return (0...top).allSatisfy { isCollectionClaimed(Item(chain: chain, tier: $0)) }
    }

    public func claimDiscovery(_ item: Item) -> CollectionReward? {
        let key = Game.collectionKey(item)
        guard state.discovered.contains(key), !state.collectionClaimed.contains(key) else { return nil }
        state.collectionClaimed.append(key)
        let reward = balance.discoveryReward(item)
        state.coins += reward.coins
        state.gems += reward.gems
        return reward
    }

    public func claimChain(_ chain: String) -> Int? {
        guard chainCollected(chain), !state.collectionChains.contains(chain) else { return nil }
        state.collectionChains.append(chain)
        state.gems += balance.chainCompleteGems
        return balance.chainCompleteGems
    }
}
