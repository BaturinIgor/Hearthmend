import Foundation

/// Событие «Остров»: поле 7x9, большая часть под туманом. Ракушки (ходы события) тратятся на
/// прилив: он выносит на свободную клетку острова предмет первой ступени. Предметы двигаются
/// бесплатно; когда рядом сходятся 3 одинаковых, они сливаются в 1 следующей ступени, а 5 - в 2.
/// Слияние у края очищает соседний туман: там бывают подарки, ящики и три клада.
public enum IslandSecret: Codable, Equatable {
    case item(Item)
    case chest(Chest)
    case treasure(Int)
}

public struct IslandCell: Codable, Equatable {
    public var fog: Bool
    public var item: Item?
    public var secret: IslandSecret?
}

public struct IslandState: Codable, Equatable {
    public static let cols = 7
    public static let rows = 9

    public var cells: [IslandCell]

    static func generate(seed: UInt64) -> IslandState {
        var rng = SplitMix64(seed: seed)
        let cols = Self.cols, rows = Self.rows
        let center = (rows / 2) * cols + cols / 2
        var cells: [IslandCell] = []
        for i in 0..<(cols * rows) {
            let d = Self.distance(i, center)
            var cell = IslandCell(fog: d > 2, item: nil, secret: nil)
            if cell.fog {
                let k = Double.random(in: 0..<1, using: &rng)
                if k < 0.22 {
                    let chain = Island.chains[Int.random(in: 0..<Island.chains.count, using: &rng)]
                    cell.secret = .item(Item(chain: chain, tier: d >= 4 && k < 0.08 ? 1 : 0))
                } else if k < 0.30 {
                    let kinds: [ChestKind] = [.energy, .coins, .items]
                    cell.secret = .chest(Chest(kind: kinds[Int.random(in: 0..<kinds.count, using: &rng)], level: d >= 4 ? 1 : 0))
                }
            }
            cells.append(cell)
        }
        // клады: чем дальше от берега, тем ценнее; последний в углу острова
        let far = cells.indices.filter { Self.distance($0, center) == 4 }
        let farther = cells.indices.filter { Self.distance($0, center) == 6 }
        let corners = [0, cols - 1, (rows - 1) * cols, rows * cols - 1]
        let spots = [far[Int.random(in: 0..<far.count, using: &rng)],
                     farther[Int.random(in: 0..<farther.count, using: &rng)],
                     corners[Int.random(in: 0..<corners.count, using: &rng)]]
        for (n, i) in spots.enumerated() { cells[i].secret = .treasure(n) }
        // на берегу уже лежат первые предметы, чтобы было с чего начать
        for (n, i) in [center - 1, center + 1, center - cols].enumerated() {
            cells[i].item = Item(chain: Island.chains[n % Island.chains.count], tier: 0)
        }
        return IslandState(cells: cells)
    }

    /// Шаги по клеткам (по горизонтали и вертикали).
    static func distance(_ a: Int, _ b: Int) -> Int {
        abs(a / cols - b / cols) + abs(a % cols - b % cols)
    }

    static func neighbors(_ index: Int) -> [Int] {
        let r = index / cols, c = index % cols
        var n: [Int] = []
        if r > 0 { n.append(index - cols) }
        if r < rows - 1 { n.append(index + cols) }
        if c > 0 { n.append(index - 1) }
        if c < cols - 1 { n.append(index + 1) }
        return n
    }

    public var fogLeft: Int { cells.filter(\.fog).count }
    public var freeCells: [Int] { cells.indices.filter { !cells[$0].fog && cells[$0].item == nil } }

    /// Клад виден, если рядом с ним уже есть очищенная земля: туман над ним редеет.
    public func treasureVisible(_ index: Int) -> Bool {
        guard cells.indices.contains(index), cells[index].fog, case .treasure? = cells[index].secret else { return false }
        return Self.neighbors(index).contains { !cells[$0].fog }
            || Self.neighbors(index).flatMap(Self.neighbors).contains { !cells[$0].fog }
    }

    /// Связная группа одинаковых предметов вокруг клетки.
    public func group(at index: Int) -> [Int] {
        guard cells.indices.contains(index), !cells[index].fog, let item = cells[index].item else { return [] }
        var seen: Set<Int> = [index], queue = [index], out: [Int] = []
        while let i = queue.popLast() {
            out.append(i)
            for j in Self.neighbors(i) where !seen.contains(j) && !cells[j].fog && cells[j].item == item {
                seen.insert(j)
                queue.append(j)
            }
        }
        return out.sorted()
    }
}

public enum Island {
    public static let chains = ["island_flower", "island_gem", "island_amber"]
    public static let maxTier = 5
    /// Очки за предмет, который получился при слиянии, по его ступени.
    public static let tierPoints = [0, 1, 4, 10, 25, 60]
    public static let fogPoints = 1
    public static let treasures: [AdventurePrize] = [
        .chest(Chest(kind: .items, level: 2)),
        .chest(Chest(kind: .coins, level: 3)),
        .chest(Chest(kind: .energy, level: 3)),
    ]

    /// Сколько получится и сколько уйдет при слиянии группы: 3 → 1, 5 → 2, лишнее остается.
    public static func mergeCounts(_ n: Int) -> (made: Int, used: Int) {
        guard n >= 3 else { return (0, 0) }
        let fives = n / 5, rest = n % 5
        return rest >= 3 ? (fives * 2 + 1, fives * 5 + 3) : (fives * 2, fives * 5)
    }

    public static let track: [AdventureMilestone] = [
        AdventureMilestone(points: 12, prize: .chest(Chest(kind: .energy, level: 1))),
        AdventureMilestone(points: 30, prize: .chest(Chest(kind: .coins, level: 2))),
        AdventureMilestone(points: 55, prize: .chest(Chest(kind: .items, level: 0))),
        AdventureMilestone(points: 85, prize: .chest(Chest(kind: .energy, level: 2))),
        AdventureMilestone(points: 125, prize: .chest(Chest(kind: .gems, level: 1))),
        AdventureMilestone(points: 170, prize: .chest(Chest(kind: .items, level: 1))),
        AdventureMilestone(points: 225, prize: .chest(Chest(kind: .energy, level: 3))),
        AdventureMilestone(points: 290, prize: .chest(Chest(kind: .coins, level: 4))),
        AdventureMilestone(points: 370, prize: .generator("fishing")),
        AdventureMilestone(points: 460, prize: .chest(Chest(kind: .gems, level: 2))),
        AdventureMilestone(points: 570, prize: .chest(Chest(kind: .energy, level: 4))),
        AdventureMilestone(points: 700, prize: .decor("decor_boat")),
    ]
}

extension Game {
    public enum TideResult: Equatable {
        case noMoves
        case noRoom
        case placed(index: Int, item: Item)
    }

    public struct IslandMerge: Equatable {
        public let at: Int
        public let item: Item
        public let made: Int
    }

    /// Что случилось после переноса на острове.
    public struct IslandMove: Equatable {
        /// Слияния по порядку (каскад): клетка, где появился новый предмет, и сколько их.
        public var merges: [IslandMerge] = []
        public var cleared: [Int] = []
        public var prizes: [AdventurePrize] = []
        public var points = 0
    }

    private var island: IslandState? { adventure?.island }

    /// Прилив: за ракушку на свободную клетку у середины выносит предмет первой ступени.
    @discardableResult
    public func tide() -> TideResult {
        guard let s = island else { return .noMoves }
        let free = s.freeCells
        guard !free.isEmpty else { return .noRoom }
        guard spendAdventureMoves(1) else { return .noMoves }
        let index = free[Int.random(in: 0..<free.count, using: &rng)]
        let chain = Island.chains[Int.random(in: 0..<Island.chains.count, using: &rng)]
        let item = Item(chain: chain, tier: Double.random(in: 0..<1, using: &rng) < 0.08 ? 1 : 0)
        state.adventure?.island?.cells[index].item = item
        return .placed(index: index, item: item)
    }

    public func canMoveOnIsland(from: Int, to: Int) -> Bool {
        guard let s = island, from != to, s.cells.indices.contains(from), s.cells.indices.contains(to) else { return false }
        return !s.cells[from].fog && !s.cells[to].fog && s.cells[from].item != nil
    }

    /// Переносит предмет (на занятую клетку - обмен) и сливает группы, которые сошлись.
    public func moveOnIsland(from: Int, to: Int) -> IslandMove? {
        guard canMoveOnIsland(from: from, to: to) else { return nil }
        // туман и секреты остаются на своих клетках, переезжают только предметы
        let a = state.adventure?.island?.cells[from].item ?? nil
        let b = state.adventure?.island?.cells[to].item ?? nil
        state.adventure?.island?.cells[from].item = b
        state.adventure?.island?.cells[to].item = a
        var result = IslandMove()
        resolveIsland(at: to, into: &result)
        if state.adventure?.island?.cells[from].item != nil { resolveIsland(at: from, into: &result) }
        if result.points > 0 { result.prizes += addAdventurePoints(result.points) }
        return result
    }

    /// Убирает предмет с острова (волна уносит его без очков), чтобы освободить место.
    @discardableResult
    public func washAway(_ index: Int) -> Bool {
        guard let s = island, s.cells.indices.contains(index), !s.cells[index].fog, s.cells[index].item != nil else { return false }
        state.adventure?.island?.cells[index].item = nil
        return true
    }

    private func resolveIsland(at index: Int, into result: inout IslandMove) {
        var at = index
        for _ in 0..<10 {
            guard let s = state.adventure?.island, let item = s.cells[at].item, item.tier < Island.maxTier else { return }
            let group = s.group(at: at)
            let (made, used) = Island.mergeCounts(group.count)
            guard made > 0 else { return }
            // уходят дальние, новые встают ближе к месту, куда положили
            let order = group.sorted { IslandState.distance($0, at) < IslandState.distance($1, at) }
            let consumed = Array(order.prefix(used))
            let next = Item(chain: item.chain, tier: item.tier + 1)
            for i in consumed { state.adventure?.island?.cells[i].item = nil }
            for i in consumed.prefix(made) { state.adventure?.island?.cells[i].item = next }
            result.merges.append(IslandMerge(at: at, item: next, made: made))
            result.points += Island.tierPoints[next.tier] * made
            for i in consumed { clearFog(around: i, into: &result) }
            // последняя ступень сразу уходит в копилку очков и освобождает место
            if next.tier >= Island.maxTier {
                for i in consumed.prefix(made) { state.adventure?.island?.cells[i].item = nil }
                return
            }
            at = consumed[0]
        }
    }

    private func clearFog(around index: Int, into result: inout IslandMove) {
        for j in IslandState.neighbors(index) {
            guard let cell = state.adventure?.island?.cells[j], cell.fog else { continue }
            state.adventure?.island?.cells[j].fog = false
            state.adventure?.island?.cells[j].secret = nil
            result.cleared.append(j)
            result.points += Island.fogPoints
            switch cell.secret {
            case .item(let item)?:
                if cell.item == nil { state.adventure?.island?.cells[j].item = item }
            case .chest(let chest)?:
                grantAdventurePrize(.chest(chest))
                result.prizes.append(.chest(chest))
            case .treasure(let n)?:
                let prize = Island.treasures[min(n, Island.treasures.count - 1)]
                grantAdventurePrize(prize)
                result.prizes.append(prize)
            case nil:
                break
            }
        }
    }
}
