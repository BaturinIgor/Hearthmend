import Foundation

/// Событие «Глубины»: шахта уходит вниз. Копать можно клетку рядом с уже открытой, у клеток
/// разная твердость (1-3 кирки). В земле находки трех цепочек по 5 уровней: они падают на
/// маленькое поле 5x5, там сливаются и сдаются в вагонетку за очки. Фонарь открывает все вокруг,
/// на глубине 12, 24 и 36 рядов спрятаны большие клады.
public enum DepthContent: Codable, Equatable {
    case find(Item)
    case lantern
    case chest(Chest)
    case treasure(Int)
}

public struct DepthCell: Codable, Equatable {
    /// Сколько ударов осталось: 0 - открыта, -1 - скала, через нее не пройти.
    public var hardness: Int
    public var content: DepthContent?

    public var isOpen: Bool { hardness == 0 }
    public var isRock: Bool { hardness < 0 }
}

public struct DepthsState: Codable, Equatable {
    public static let width = 7
    public static let depth = 36
    public static let boardSize = 25

    public var cells: [DepthCell]
    public var board: [Item?]

    static func generate(seed: UInt64) -> DepthsState {
        var rng = SplitMix64(seed: seed)
        var cells: [DepthCell] = []
        let treasureRows = Depths.treasureRows
        var treasureCols: [Int: Int] = [:]
        for row in treasureRows { treasureCols[row] = Int.random(in: 0..<width, using: &rng) }
        for r in 0..<depth {
            let rockCol = r > 0 && Double.random(in: 0..<1, using: &rng) < 0.35 ? Int.random(in: 0..<width, using: &rng) : -1
            for c in 0..<width {
                if c == rockCol, treasureCols[r] != c {
                    cells.append(DepthCell(hardness: -1, content: nil))
                    continue
                }
                let deep = Double(r) / Double(depth)
                let roll = Double.random(in: 0..<1, using: &rng)
                let hardness = roll < 0.6 - deep * 0.4 ? 1 : roll < 0.9 - deep * 0.3 ? 2 : 3
                var content: DepthContent?
                if let i = treasureRows.firstIndex(of: r), treasureCols[r] == c {
                    content = .treasure(i)
                } else {
                    let k = Double.random(in: 0..<1, using: &rng)
                    if k < 0.36 {
                        let w = Double.random(in: 0..<1, using: &rng)
                        let chain = w < 0.5 ? Depths.chains[0] : w < 0.8 ? Depths.chains[1] : Depths.chains[2]
                        let tier = Double.random(in: 0..<1, using: &rng) < 0.1 + deep * 0.2 ? 1 : 0
                        content = .find(Item(chain: chain, tier: tier))
                    } else if k < 0.40 {
                        content = .lantern
                    } else if k < 0.44 {
                        let kinds: [ChestKind] = [.energy, .coins, .items]
                        content = .chest(Chest(kind: kinds[Int.random(in: 0..<kinds.count, using: &rng)], level: r < depth / 2 ? 0 : 1))
                    }
                }
                cells.append(DepthCell(hardness: hardness, content: content))
            }
        }
        return DepthsState(cells: cells, board: Array(repeating: nil, count: boardSize))
    }
}

public enum Depths {
    public static let chains = ["depth_ore", "depth_gem", "depth_fossil"]
    public static let maxTier = 4
    /// Очки за находку: цепочка (руда, самоцвет, окаменелость) x уровень. Каждый уровень больше
    /// чем вдвое, поэтому сливать перед сдачей выгодно.
    public static let chainPoints = [1, 2, 3]
    public static let tierPoints = [1, 3, 7, 16, 36]
    public static let treasureRows = [11, 23, 35]
    public static let treasures: [AdventurePrize] = [
        .chest(Chest(kind: .items, level: 2)),
        .chest(Chest(kind: .coins, level: 3)),
        .chest(Chest(kind: .energy, level: 3)),
    ]

    public static func points(_ item: Item) -> Int {
        let c = chains.firstIndex(of: item.chain) ?? 0
        return chainPoints[c] * tierPoints[min(max(item.tier, 0), maxTier)]
    }

    public static let track: [AdventureMilestone] = [
        AdventureMilestone(points: 10, prize: .chest(Chest(kind: .energy, level: 1))),
        AdventureMilestone(points: 25, prize: .chest(Chest(kind: .coins, level: 2))),
        AdventureMilestone(points: 45, prize: .chest(Chest(kind: .items, level: 0))),
        AdventureMilestone(points: 70, prize: .chest(Chest(kind: .energy, level: 2))),
        AdventureMilestone(points: 100, prize: .chest(Chest(kind: .gems, level: 1))),
        AdventureMilestone(points: 140, prize: .chest(Chest(kind: .items, level: 1))),
        AdventureMilestone(points: 185, prize: .chest(Chest(kind: .energy, level: 3))),
        AdventureMilestone(points: 240, prize: .chest(Chest(kind: .coins, level: 4))),
        AdventureMilestone(points: 300, prize: .generator("quarry")),
        AdventureMilestone(points: 370, prize: .chest(Chest(kind: .gems, level: 2))),
        AdventureMilestone(points: 450, prize: .chest(Chest(kind: .energy, level: 4))),
        AdventureMilestone(points: 550, prize: .decor("decor_minecart")),
    ]
}

extension Game {
    public enum DigResult: Equatable {
        case invalid
        case noMoves
        /// Клетка треснула, осталось столько ударов.
        case chipped(Int)
        /// Клетка открыта: что из нее досталось (находки уже на поле 5x5, призы на главном поле).
        case opened(found: [Item], prizes: [AdventurePrize], opened: [Int])
    }

    private var depths: DepthsState? { adventure?.depths }

    /// Можно ли копать клетку: она закрыта, не скала, и рядом открытая клетка (или это первый ряд).
    public func canDig(_ index: Int) -> Bool {
        guard let d = depths, d.cells.indices.contains(index) else { return false }
        let cell = d.cells[index]
        guard cell.hardness > 0 else { return false }
        if index < DepthsState.width { return true }
        return depthNeighbors(index).contains { d.cells[$0].isOpen }
    }

    func depthNeighbors(_ index: Int) -> [Int] {
        let w = DepthsState.width, r = index / w, c = index % w
        var n: [Int] = []
        if r > 0 { n.append(index - w) }
        if r < DepthsState.depth - 1 { n.append(index + w) }
        if c > 0 { n.append(index - 1) }
        if c < w - 1 { n.append(index + 1) }
        return n
    }

    /// Самый глубокий открытый ряд (-1 - еще ничего не открыто).
    public var depthsReached: Int {
        guard let d = depths else { return -1 }
        return (d.cells.indices.filter { d.cells[$0].isOpen }.map { $0 / DepthsState.width }.max()) ?? -1
    }

    /// Карта клада: следующий клад становится виден, когда до него осталось 5 рядов.
    public func depthTreasureVisible(_ index: Int) -> Bool {
        guard let d = depths, case .treasure? = d.cells[index].content else { return false }
        return index / DepthsState.width - depthsReached <= 5
    }

    public func dig(_ index: Int) -> DigResult {
        guard canDig(index) else { return .invalid }
        guard spendAdventureMoves(1) else { return .noMoves }
        state.adventure?.depths?.cells[index].hardness -= 1
        guard let left = state.adventure?.depths?.cells[index].hardness, left == 0 else {
            return .chipped(state.adventure?.depths?.cells[index].hardness ?? 0)
        }
        var found: [Item] = [], prizes: [AdventurePrize] = [], opened: [Int] = [index]
        collectDepth(index, found: &found, prizes: &prizes, opened: &opened)
        return .opened(found: found, prizes: prizes, opened: opened)
    }

    /// Забирает то, что лежит в открытой клетке. Находка ждет в клетке, если поле 5x5 занято.
    private func collectDepth(_ index: Int, found: inout [Item], prizes: inout [AdventurePrize], opened: inout [Int]) {
        guard let content = state.adventure?.depths?.cells[index].content else { return }
        switch content {
        case .find(let item):
            guard let slot = state.adventure?.depths?.board.firstIndex(where: { $0 == nil }) else { return }
            state.adventure?.depths?.board[slot] = item
            found.append(item)
        case .lantern:
            // фонарь освещает все вокруг: соседние клетки (и по диагонали) открываются без кирок
            state.adventure?.depths?.cells[index].content = nil
            let w = DepthsState.width, r = index / w, c = index % w
            for dr in -1...1 {
                for dc in -1...1 {
                    let rr = r + dr, cc = c + dc
                    guard rr >= 0, rr < DepthsState.depth, cc >= 0, cc < w else { continue }
                    let j = rr * w + cc
                    guard let cell = state.adventure?.depths?.cells[j], cell.hardness > 0 else { continue }
                    state.adventure?.depths?.cells[j].hardness = 0
                    opened.append(j)
                    collectDepth(j, found: &found, prizes: &prizes, opened: &opened)
                }
            }
            return
        case .chest(let chest):
            grantAdventurePrize(.chest(chest))
            prizes.append(.chest(chest))
        case .treasure(let i):
            let prize = Depths.treasures[min(i, Depths.treasures.count - 1)]
            grantAdventurePrize(prize)
            prizes.append(prize)
        }
        state.adventure?.depths?.cells[index].content = nil
    }

    /// Тап по открытой клетке, где осталась находка (поле было занято).
    @discardableResult
    public func collectDepth(_ index: Int) -> Item? {
        guard let cell = depths?.cells[index], cell.isOpen, case .find(let item)? = cell.content else { return nil }
        var found: [Item] = [], prizes: [AdventurePrize] = [], opened: [Int] = []
        collectDepth(index, found: &found, prizes: &prizes, opened: &opened)
        return found.isEmpty ? nil : item
    }

    /// Перенос находки на поле 5x5: на такую же - слияние, на пустую - перенос, иначе обмен.
    @discardableResult
    public func moveFind(from: Int, to: Int) -> Bool {
        guard let d = depths, from != to, d.board.indices.contains(from), d.board.indices.contains(to),
              let a = d.board[from] else { return false }
        if let b = d.board[to], a == b, a.tier < Depths.maxTier {
            state.adventure?.depths?.board[to] = Item(chain: a.chain, tier: a.tier + 1)
            state.adventure?.depths?.board[from] = nil
            return true
        }
        state.adventure?.depths?.board.swapAt(from, to)
        return true
    }

    /// Сдает находку в вагонетку. Возвращает очки и награды, которые открылись.
    @discardableResult
    public func deliverFind(_ slot: Int) -> (points: Int, prizes: [AdventurePrize])? {
        guard let item = depths?.board[slot] ?? nil else { return nil }
        state.adventure?.depths?.board[slot] = nil
        let pts = Depths.points(item)
        return (pts, addAdventurePoints(pts))
    }
}
