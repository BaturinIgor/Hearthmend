import Foundation

/// Событие «Витраж»: окно 6x8 из цветных осколков, каждый осколок - область одного цвета.
/// Стекло (ходы события) режет кусочек случайного цвета на верстак из 6 ячеек. Два одинаковых
/// кусочка сливаются в больший, и он закрывает больше клеток, чем два маленьких по отдельности.
/// Кусочек кладут на область своего цвета: он заполняет ближайшие пустые клетки этой области,
/// лишнее пропадает. Целая область дает бонус, целое окно - большой бонус и новое окно.
public struct MosaicState: Codable, Equatable {
    public static let cols = 6
    public static let rows = 8
    public static let size = cols * rows
    public static let benchSize = 6
    /// Сколько областей в окне.
    static let regionCount = 9

    /// Цвет каждой клетки (0..<Mosaic.colors).
    public var colors: [Int]
    /// Номер области каждой клетки.
    public var regions: [Int]
    public var filled: [Bool]
    public var bench: [Item?]
    /// Сколько окон уже собрано.
    public var windows: Int = 0
    var seed: UInt64

    static func generate(seed: UInt64, windows: Int = 0) -> MosaicState {
        var rng = SplitMix64(seed: seed &+ UInt64(windows) &* 0x9E3779B97F4A7C15)
        // центры осколков: разные клетки
        var centers: [Int] = []
        while centers.count < regionCount {
            let i = Int.random(in: 0..<size, using: &rng)
            if !centers.contains(i) { centers.append(i) }
        }
        var regions = [Int](repeating: 0, count: size)
        for i in 0..<size {
            let r = i / cols, c = i % cols
            var best = 0, bestD = Int.max
            for (n, k) in centers.enumerated() {
                let dr = r - k / cols, dc = c - k % cols
                // окно вытянутое: по вертикали осколки чуть длиннее
                let d = dr * dr * 2 + dc * dc * 3
                if d < bestD { bestD = d; best = n }
            }
            regions[i] = best
        }
        // соседние осколки разного цвета, где получается
        var regionColor = [Int](repeating: -1, count: regionCount)
        for n in 0..<regionCount {
            var near: Set<Int> = []
            for i in 0..<size where regions[i] == n {
                for j in neighbors(i) where regions[j] != n { near.insert(regionColor[regions[j]]) }
            }
            var options = (0..<Mosaic.colorCount).filter { !near.contains($0) }
            if options.isEmpty { options = Array(0..<Mosaic.colorCount) }
            regionColor[n] = options[Int.random(in: 0..<options.count, using: &rng)]
        }
        return MosaicState(colors: regions.map { regionColor[$0] }, regions: regions,
                           filled: Array(repeating: false, count: size),
                           bench: Array(repeating: nil, count: benchSize), windows: windows, seed: seed)
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

    public var freeSlots: [Int] { bench.indices.filter { bench[$0] == nil } }
    public var emptyCells: Int { filled.filter { !$0 }.count }

    /// Пустые клетки области, ближайшие к точке сначала.
    public func openCells(region: Int, near index: Int) -> [Int] {
        let r0 = index / Self.cols, c0 = index % Self.cols
        return filled.indices.filter { regions[$0] == region && !filled[$0] }.sorted {
            let a = abs($0 / Self.cols - r0) + abs($0 % Self.cols - c0)
            let b = abs($1 / Self.cols - r0) + abs($1 % Self.cols - c0)
            return (a, $0) < (b, $1)
        }
    }

    public func regionSize(_ region: Int) -> Int { regions.filter { $0 == region }.count }

    /// Сколько еще пустых клеток каждого цвета.
    public var needByColor: [Int] {
        var need = [Int](repeating: 0, count: Mosaic.colorCount)
        for i in filled.indices where !filled[i] { need[colors[i]] += 1 }
        return need
    }

    /// Какой цвет у кусочка.
    public static func color(of item: Item) -> Int? { Mosaic.chains.firstIndex(of: item.chain) }
}

public enum Mosaic {
    public static let chains = ["glass_ruby", "glass_amber", "glass_emerald", "glass_sapphire"]
    public static var colorCount: Int { chains.count }
    public static let maxTier = 3
    /// Сколько клеток закрывает кусочек каждой ступени: больше, чем два предыдущих вместе.
    public static let cover = [1, 3, 7, 16]
    public static let cellPoints = 1
    /// Бонус за целую область - за каждую ее клетку.
    public static let regionPoints = 1
    public static let windowPoints = 30
    /// Каждое собранное окно приносит еще и ящик на главное поле.
    public static let windowPrize: AdventurePrize = .chest(Chest(kind: .items, level: 0))

    public static let track: [AdventureMilestone] = [
        AdventureMilestone(points: 30, prize: .chest(Chest(kind: .energy, level: 1))),
        AdventureMilestone(points: 80, prize: .chest(Chest(kind: .coins, level: 2))),
        AdventureMilestone(points: 150, prize: .chest(Chest(kind: .items, level: 0))),
        AdventureMilestone(points: 240, prize: .chest(Chest(kind: .energy, level: 2))),
        AdventureMilestone(points: 350, prize: .chest(Chest(kind: .gems, level: 1))),
        AdventureMilestone(points: 480, prize: .chest(Chest(kind: .items, level: 1))),
        AdventureMilestone(points: 640, prize: .chest(Chest(kind: .energy, level: 3))),
        AdventureMilestone(points: 820, prize: .chest(Chest(kind: .coins, level: 4))),
        AdventureMilestone(points: 1020, prize: .generator("forest")),
        AdventureMilestone(points: 1260, prize: .chest(Chest(kind: .gems, level: 2))),
        AdventureMilestone(points: 1540, prize: .chest(Chest(kind: .energy, level: 4))),
        AdventureMilestone(points: 1860, prize: .decor("decor_lily")),
    ]
}

extension Game {
    public enum CutResult: Equatable {
        case noMoves
        case noRoom
        case cut(slot: Int, item: Item)
    }

    /// Что случилось, когда кусочек положили в окно.
    public struct MosaicSet: Equatable {
        public var cells: [Int] = []
        /// Сколько клеток кусочек мог закрыть, но не хватило места в области.
        public var wasted = 0
        public var regionDone = false
        public var windowDone = false
        public var points = 0
        public var prizes: [AdventurePrize] = []
    }

    private var mosaic: MosaicState? { adventure?.mosaic }

    /// Режет кусочек стекла на свободную ячейку верстака. Чаще выпадают цвета, которых в окне
    /// осталось больше всего, чтобы игрок не застревал с ненужным цветом.
    @discardableResult
    public func cutGlass() -> CutResult {
        guard let m = mosaic else { return .noMoves }
        guard let slot = m.freeSlots.first else { return .noRoom }
        guard spendAdventureMoves(1) else { return .noMoves }
        let need = m.needByColor
        let weights = need.map { Double($0) + 2 }
        var roll = Double.random(in: 0..<weights.reduce(0, +), using: &rng)
        var color = 0
        for (n, w) in weights.enumerated() {
            if roll < w { color = n; break }
            roll -= w
        }
        let item = Item(chain: Mosaic.chains[color], tier: Double.random(in: 0..<1, using: &rng) < 0.06 ? 1 : 0)
        state.adventure?.mosaic?.bench[slot] = item
        return .cut(slot: slot, item: item)
    }

    /// Перенос на верстаке: на такой же кусочек - слияние, иначе обмен.
    @discardableResult
    public func moveGlass(from: Int, to: Int) -> Bool {
        guard let m = mosaic, from != to, m.bench.indices.contains(from), m.bench.indices.contains(to),
              let a = m.bench[from] else { return false }
        if canMergeGlass(from, to) {
            state.adventure?.mosaic?.bench[to] = Item(chain: a.chain, tier: a.tier + 1)
            state.adventure?.mosaic?.bench[from] = nil
        } else {
            state.adventure?.mosaic?.bench.swapAt(from, to)
        }
        return true
    }

    public func canMergeGlass(_ a: Int, _ b: Int) -> Bool {
        guard let m = mosaic, a != b, m.bench.indices.contains(a), m.bench.indices.contains(b),
              let x = m.bench[a], let y = m.bench[b] else { return false }
        return x == y && x.tier < Mosaic.maxTier
    }

    /// Можно ли положить кусочек в эту клетку: тот же цвет и клетка еще пустая.
    public func canSetGlass(slot: Int, cell: Int) -> Bool {
        guard let m = mosaic, m.bench.indices.contains(slot), m.filled.indices.contains(cell),
              let item = m.bench[slot], !m.filled[cell] else { return false }
        return MosaicState.color(of: item) == m.colors[cell]
    }

    /// Кладет кусочек в окно: он закрывает ближайшие пустые клетки той же области.
    public func setGlass(slot: Int, cell: Int) -> MosaicSet? {
        guard canSetGlass(slot: slot, cell: cell), let m = mosaic, let item = m.bench[slot] else { return nil }
        let region = m.regions[cell]
        let open = m.openCells(region: region, near: cell)
        let n = Mosaic.cover[min(max(item.tier, 0), Mosaic.maxTier)]
        var result = MosaicSet()
        result.cells = Array(open.prefix(n))
        result.wasted = max(0, n - open.count)
        state.adventure?.mosaic?.bench[slot] = nil
        for i in result.cells { state.adventure?.mosaic?.filled[i] = true }
        result.points = result.cells.count * Mosaic.cellPoints
        if open.count <= n {
            result.regionDone = true
            result.points += m.regionSize(region) * Mosaic.regionPoints
        }
        if state.adventure?.mosaic?.filled.allSatisfy({ $0 }) == true {
            result.windowDone = true
            result.points += Mosaic.windowPoints
            grantAdventurePrize(Mosaic.windowPrize)
            result.prizes.append(Mosaic.windowPrize)
            // новое окно, верстак остается
            let bench = m.bench.enumerated().map { $0.offset == slot ? nil : $0.element }
            var next = MosaicState.generate(seed: m.seed, windows: m.windows + 1)
            next.bench = bench
            state.adventure?.mosaic = next
        }
        result.prizes += addAdventurePoints(result.points)
        return result
    }

    /// Разбивает кусочек на верстаке, чтобы освободить место.
    @discardableResult
    public func shatterGlass(_ slot: Int) -> Bool {
        guard let m = mosaic, m.bench.indices.contains(slot), m.bench[slot] != nil else { return false }
        state.adventure?.mosaic?.bench[slot] = nil
        return true
    }

    /// Есть ли кусочек, который уже можно положить в окно.
    public var mosaicCanPlace: Bool {
        guard let m = mosaic else { return false }
        let need = m.needByColor
        return m.bench.contains { item in item.flatMap(MosaicState.color(of:)).map { need[$0] > 0 } ?? false }
    }
}
