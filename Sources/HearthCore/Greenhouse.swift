import Foundation

/// Событие «Теплица»: грядки 4x5, растения растут по настоящему времени. Семена (ходы события)
/// сажают росток. Два одинаковых растения сливаются в одно следующей ступени и дозревают быстрее,
/// а созревшее собирается за очки: чем выше ступень, тем больше очков. Раз в 4 часа лейка
/// бесплатно ускоряет все грядки на час: событие зовет заглянуть несколько раз за день.
public struct Plant: Codable, Equatable {
    public var item: Item
    public var readyAt: Date

    public func ripe(at now: Date) -> Bool { now >= readyAt }
}

public struct GreenhouseState: Codable, Equatable {
    public static let cols = 4
    public static let rows = 5
    public static let size = cols * rows

    public var beds: [Plant?]
    /// Когда лейка снова будет полной.
    public var waterAt: Date
    public var harvested: Int = 0

    static func make(now: Date) -> GreenhouseState {
        GreenhouseState(beds: Array(repeating: nil, count: size), waterAt: now)
    }

    public var freeBeds: [Int] { beds.indices.filter { beds[$0] == nil } }
}

public enum Greenhouse {
    public static let chains = ["gh_tomato", "gh_sunflower", "gh_strawberry"]
    public static let maxTier = 4
    /// Сколько растет растение каждой ступени, если его посадить с нуля.
    public static let growTime: [TimeInterval] = [3600, 1.5 * 3600, 2.5 * 3600, 4 * 3600, 6 * 3600]
    /// Очки за урожай: каждая ступень больше чем вдвое, поэтому сливать выгодно.
    public static let tierPoints = [2, 5, 12, 28, 65]
    public static let waterEvery: TimeInterval = 4 * 3600
    public static let waterBoost: TimeInterval = 3600
    /// Урожай последней ступени приносит еще и ящик на главное поле.
    public static let goldenPrize: AdventurePrize = .chest(Chest(kind: .items, level: 0))

    public static func points(_ item: Item) -> Int { tierPoints[min(max(item.tier, 0), maxTier)] }

    public static let track: [AdventureMilestone] = [
        AdventureMilestone(points: 15, prize: .chest(Chest(kind: .energy, level: 1))),
        AdventureMilestone(points: 40, prize: .chest(Chest(kind: .coins, level: 2))),
        AdventureMilestone(points: 75, prize: .chest(Chest(kind: .items, level: 0))),
        AdventureMilestone(points: 120, prize: .chest(Chest(kind: .energy, level: 2))),
        AdventureMilestone(points: 175, prize: .chest(Chest(kind: .gems, level: 1))),
        AdventureMilestone(points: 240, prize: .chest(Chest(kind: .items, level: 1))),
        AdventureMilestone(points: 320, prize: .chest(Chest(kind: .energy, level: 3))),
        AdventureMilestone(points: 410, prize: .chest(Chest(kind: .coins, level: 4))),
        AdventureMilestone(points: 510, prize: .generator("garden")),
        AdventureMilestone(points: 630, prize: .chest(Chest(kind: .gems, level: 2))),
        AdventureMilestone(points: 770, prize: .chest(Chest(kind: .energy, level: 4))),
        AdventureMilestone(points: 930, prize: .decor("decor_flowers_big")),
    ]
}

extension Game {
    public enum PlantResult: Equatable {
        case noMoves
        case noRoom
        case planted(index: Int, item: Item)
    }

    private var greenhouse: GreenhouseState? { adventure?.greenhouse }

    /// Сажает росток на первую свободную грядку (или на указанную).
    @discardableResult
    public func plantSeed(at bed: Int? = nil) -> PlantResult {
        guard let g = greenhouse else { return .noMoves }
        let target = bed.flatMap { g.beds.indices.contains($0) && g.beds[$0] == nil ? $0 : nil } ?? g.freeBeds.first
        guard let index = target else { return .noRoom }
        guard spendAdventureMoves(1) else { return .noMoves }
        let chain = Greenhouse.chains[Int.random(in: 0..<Greenhouse.chains.count, using: &rng)]
        let item = Item(chain: chain, tier: 0)
        state.adventure?.greenhouse?.beds[index] = Plant(item: item, readyAt: now().addingTimeInterval(Greenhouse.growTime[0]))
        return .planted(index: index, item: item)
    }

    /// Перенос на поле теплицы: на такое же растение - слияние, иначе обмен грядками.
    /// Слитое растение дозревает с той же минуты, что и более спелое из двух, плюс половина своего срока.
    @discardableResult
    public func movePlant(from: Int, to: Int) -> Bool {
        guard let g = greenhouse, from != to, g.beds.indices.contains(from), g.beds.indices.contains(to),
              let a = g.beds[from] else { return false }
        if let b = g.beds[to], a.item == b.item, a.item.tier < Greenhouse.maxTier {
            let next = Item(chain: a.item.chain, tier: a.item.tier + 1)
            let start = max(now(), min(a.readyAt, b.readyAt))
            state.adventure?.greenhouse?.beds[to] = Plant(item: next, readyAt: start.addingTimeInterval(Greenhouse.growTime[next.tier] / 2))
            state.adventure?.greenhouse?.beds[from] = nil
            return true
        }
        state.adventure?.greenhouse?.beds.swapAt(from, to)
        return true
    }

    public func canMergePlants(_ a: Int, _ b: Int) -> Bool {
        guard let g = greenhouse, a != b, let x = g.beds[a], let y = g.beds[b] else { return false }
        return x.item == y.item && x.item.tier < Greenhouse.maxTier
    }

    /// Собирает созревшее растение. Возвращает очки и награды, которые открылись.
    public func harvest(_ bed: Int) -> (points: Int, prizes: [AdventurePrize])? {
        guard let g = greenhouse, g.beds.indices.contains(bed), let p = g.beds[bed], p.ripe(at: now()) else { return nil }
        state.adventure?.greenhouse?.beds[bed] = nil
        state.adventure?.greenhouse?.harvested += 1
        var prizes: [AdventurePrize] = []
        if p.item.tier >= Greenhouse.maxTier {
            grantAdventurePrize(Greenhouse.goldenPrize)
            prizes.append(Greenhouse.goldenPrize)
        }
        let pts = Greenhouse.points(p.item)
        prizes += addAdventurePoints(pts)
        return (pts, prizes)
    }

    public var waterReady: Bool {
        guard let g = greenhouse else { return false }
        return now() >= g.waterAt
    }

    /// Лейка: все растения дозревают на час быстрее. Наполняется раз в 4 часа.
    @discardableResult
    public func water() -> Bool {
        guard waterReady, let g = greenhouse, g.beds.contains(where: { $0 != nil }) else { return false }
        for i in g.beds.indices {
            if let p = g.beds[i] { state.adventure?.greenhouse?.beds[i]?.readyAt = p.readyAt.addingTimeInterval(-Greenhouse.waterBoost) }
        }
        state.adventure?.greenhouse?.waterAt = now().addingTimeInterval(Greenhouse.waterEvery)
        return true
    }

    /// Есть что собрать или чем полить: красная точка.
    public var greenhouseNeedsAttention: Bool {
        guard let g = greenhouse else { return false }
        return g.beds.contains { $0?.ripe(at: now()) == true } || (waterReady && g.beds.contains { $0 != nil })
    }
}
