import Foundation

/// Событие «Ночь фонарей»: темная деревня 7x9. Фонарики (ходы события) вешают на любую пустую
/// клетку. Два одинаковых фонаря сливаются в один ярче (на месте второго), и он светит дальше.
/// Светло только там, куда сейчас достает свет фонарей. Клетка, которую осветили впервые, отдает
/// то, что пряталось в темноте: желание, светлячков (дают фонарики) или ящик. Когда светла вся
/// деревня сразу, наступает следующая ночь с новой картой.
public enum LanternSecret: Codable, Equatable {
    case wish
    case fireflies
    case chest(Chest)
}

public struct LanternCell: Codable, Equatable {
    /// Клетку уже освещали этой ночью (секрет забран, очки за нее получены).
    public var lit: Bool = false
    /// Ступень фонаря на клетке.
    public var lantern: Int?
    public var secret: LanternSecret?
}

public struct LanternsState: Codable, Equatable {
    public static let cols = 7
    public static let rows = 9
    public static let size = cols * rows

    public var cells: [LanternCell]
    /// Сколько ночей уже пройдено.
    public var nights: Int = 0
    var seed: UInt64

    static func generate(seed: UInt64, nights: Int = 0) -> LanternsState {
        var rng = SplitMix64(seed: seed &+ UInt64(nights) &* 0xA24BAED4963EE407)
        var cells = [LanternCell](repeating: LanternCell(), count: size)
        var spots = Array(0..<size)
        spots.shuffle(using: &rng)
        var k = 0
        for _ in 0..<Lanterns.wishesPerNight { cells[spots[k]].secret = .wish; k += 1 }
        for _ in 0..<Lanterns.firefliesPerNight { cells[spots[k]].secret = .fireflies; k += 1 }
        let kinds: [ChestKind] = [.energy, .coins, .items]
        for _ in 0..<Lanterns.chestsPerNight {
            cells[spots[k]].secret = .chest(Chest(kind: kinds[Int.random(in: 0..<kinds.count, using: &rng)], level: 0))
            k += 1
        }
        return LanternsState(cells: cells, nights: nights, seed: seed)
    }

    /// Клетки в радиусе (по шагам) вокруг точки.
    public static func area(_ index: Int, radius: Int) -> [Int] {
        let r0 = index / cols, c0 = index % cols
        var out: [Int] = []
        for r in max(0, r0 - radius)...min(rows - 1, r0 + radius) {
            let d = radius - abs(r - r0)
            for c in max(0, c0 - d)...min(cols - 1, c0 + d) { out.append(r * cols + c) }
        }
        return out
    }

    /// Клетки, куда сейчас достает свет фонарей.
    public var shining: Set<Int> {
        var out: Set<Int> = []
        for i in cells.indices { if let t = cells[i].lantern { out.formUnion(Self.area(i, radius: Lanterns.radius(t))) } }
        return out
    }

    public var darkLeft: Int { Self.size - shining.count }
    public var emptyCells: [Int] { cells.indices.filter { cells[$0].lantern == nil } }

    /// Сколько темных сейчас клеток осветит фонарь этой ступени здесь.
    public func darkAround(_ index: Int, tier: Int, shining: Set<Int>? = nil) -> Int {
        let lit = shining ?? self.shining
        return Self.area(index, radius: Lanterns.radius(tier)).filter { !lit.contains($0) }.count
    }
}

public enum Lanterns {
    public static let maxTier = 3
    public static let wishesPerNight = 8
    public static let firefliesPerNight = 3
    public static let chestsPerNight = 2
    public static let cellPoints = 1
    public static let wishPoints = 6
    public static let nightPoints = 25
    public static let fireflyMoves = 2
    public static let nightPrize: AdventurePrize = .chest(Chest(kind: .items, level: 0))

    public static func radius(_ tier: Int) -> Int { min(max(0, tier), maxTier) }

    public static let track: [AdventureMilestone] = [
        AdventureMilestone(points: 36, prize: .chest(Chest(kind: .energy, level: 1))),
        AdventureMilestone(points: 96, prize: .chest(Chest(kind: .coins, level: 2))),
        AdventureMilestone(points: 180, prize: .chest(Chest(kind: .items, level: 0))),
        AdventureMilestone(points: 290, prize: .chest(Chest(kind: .energy, level: 2))),
        AdventureMilestone(points: 420, prize: .chest(Chest(kind: .gems, level: 1))),
        AdventureMilestone(points: 580, prize: .chest(Chest(kind: .items, level: 1))),
        AdventureMilestone(points: 770, prize: .chest(Chest(kind: .energy, level: 3))),
        AdventureMilestone(points: 980, prize: .chest(Chest(kind: .coins, level: 4))),
        AdventureMilestone(points: 1220, prize: .generator("apiary")),
        AdventureMilestone(points: 1510, prize: .chest(Chest(kind: .gems, level: 2))),
        AdventureMilestone(points: 1850, prize: .chest(Chest(kind: .energy, level: 4))),
        AdventureMilestone(points: 2230, prize: .decor("decor_lamp_hanging")),
    ]
}

extension Game {
    /// Что случилось после того, как фонарь повесили или слили.
    public struct LanternLight: Equatable {
        public var lit: [Int] = []
        public var wishes: [Int] = []
        public var fireflies: [Int] = []
        public var chests: [Int] = []
        public var nightDone = false
        public var moves = 0
        public var points = 0
        public var prizes: [AdventurePrize] = []
    }

    private var lanterns: LanternsState? { adventure?.lanterns }

    public func canHangLantern(_ index: Int) -> Bool {
        guard let s = lanterns, s.cells.indices.contains(index) else { return false }
        return s.cells[index].lantern == nil
    }

    /// Вешает фонарик первой ступени на пустую клетку.
    public func hangLantern(_ index: Int) -> LanternLight? {
        guard canHangLantern(index), spendAdventureMoves(1) else { return nil }
        state.adventure?.lanterns?.cells[index].lantern = 0
        return shine(at: index, tier: 0)
    }

    /// Куда повесить фонарик: на темную клетку, вокруг которой темнее всего.
    public var bestLanternSpot: Int? {
        guard let s = lanterns else { return nil }
        let lit = s.shining
        func score(_ i: Int) -> Int { (lit.contains(i) ? 0 : 3) + s.darkAround(i, tier: 2, shining: lit) }
        return s.emptyCells.max { (score($0), -$0) < (score($1), -$1) }
    }

    public func canMergeLanterns(_ a: Int, _ b: Int) -> Bool {
        guard let s = lanterns, a != b, s.cells.indices.contains(a), s.cells.indices.contains(b),
              let x = s.cells[a].lantern, let y = s.cells[b].lantern else { return false }
        return x == y && x < Lanterns.maxTier
    }

    /// Сливает фонарь с таким же: новый, более яркий, загорается на месте второго.
    /// Просто переносить фонари нельзя, иначе один яркий фонарь осветил бы все бесплатно.
    public func moveLantern(from: Int, to: Int) -> LanternLight? {
        guard canMergeLanterns(from, to), let tier = lanterns?.cells[from].lantern else { return nil }
        state.adventure?.lanterns?.cells[from].lantern = nil
        state.adventure?.lanterns?.cells[to].lantern = tier + 1
        return shine(at: to, tier: tier + 1)
    }

    private func shine(at index: Int, tier: Int) -> LanternLight {
        var r = LanternLight()
        for i in LanternsState.area(index, radius: Lanterns.radius(tier)) {
            guard let cell = state.adventure?.lanterns?.cells[i], !cell.lit else { continue }
            state.adventure?.lanterns?.cells[i].lit = true
            state.adventure?.lanterns?.cells[i].secret = nil
            r.lit.append(i)
            r.points += Lanterns.cellPoints
            switch cell.secret {
            case .wish?:
                r.wishes.append(i)
                r.points += Lanterns.wishPoints
            case .fireflies?:
                r.fireflies.append(i)
                r.moves += Lanterns.fireflyMoves
            case .chest(let chest)?:
                r.chests.append(i)
                grantAdventurePrize(.chest(chest))
                r.prizes.append(.chest(chest))
            case nil:
                break
            }
        }
        state.adventure?.moves += r.moves
        if let s = state.adventure?.lanterns, s.darkLeft == 0 {
            r.nightDone = true
            r.points += Lanterns.nightPoints
            grantAdventurePrize(Lanterns.nightPrize)
            r.prizes.append(Lanterns.nightPrize)
            state.adventure?.lanterns = LanternsState.generate(seed: s.seed, nights: s.nights + 1)
        }
        r.prizes += addAdventurePoints(r.points)
        return r
    }
}
