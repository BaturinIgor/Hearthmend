import Foundation

/// Бот, который играет в игру по простой разумной стратегии. Нужен, чтобы проверять баланс тестами:
/// сколько дней уходит на район, не застревает ли поле, нет ли выгодных петель (имбы).
public struct SimConfig {
    /// Сколько раз в день игрок заходит в игру и тратит всю энергию.
    public var sessionsPerDay = 4
    public var maxDays = 60
    public var seed: UInt64 = 1
    /// Открывать ли пузыри за кристаллы.
    public var popBubbles = true
    /// Открывать ли кувшин светлячков бесплатно, когда можно.
    public var openJar = true
    /// Останавливаться, когда вся деревня отстроена.
    public var stopWhenVillageDone = true
    public var balance = Balance()

    public init() {}
}

public struct SimReport: CustomStringConvertible {
    public var days = 0.0
    public var sessions = 0
    public var energySpent = 0
    public var spawns = 0
    public var merges = 0
    public var orders = 0
    public var coinsFromOrders = 0
    public var coinsFromSelling = 0
    public var itemsSold = 0
    public var starsEarned = 0
    public var gemsSpentOnBubbles = 0
    public var bubblesPopped = 0
    public var energyFromLevels = 0
    public var energyFromJar = 0
    public var level = 1
    public var tasksDone = 0
    /// День, к которому отстроен каждый район.
    public var districtDoneDay: [String: Double] = [:]
    /// Сессии, в которых поле было забито и боту нечего было сделать с энергией.
    public var stalledSessions = 0
    public var bestTier: [String: Int] = [:]
    public var villageDone = false

    public var description: String {
        let districts = districtDoneDay.sorted { $0.value < $1.value }
            .map { "\($0.key)=\(String(format: "%.1f", $0.value))д" }.joined(separator: " ")
        return """
        дней \(String(format: "%.1f", days)), сессий \(sessions), энергия \(energySpent), слияний \(merges), \
        заказов \(orders), звезд \(starsEarned), задач \(tasksDone), уровень \(level)
        монеты: заказы \(coinsFromOrders), продажа \(coinsFromSelling) (\(itemsSold) шт), \
        пузыри \(bubblesPopped) за \(gemsSpentOnBubbles) кр, энергия с уровней \(energyFromLevels), из кувшина \(energyFromJar), застреваний \(stalledSessions)
        районы: \(districts)
        """
    }
}

public enum Simulator {
    public static func run(_ config: SimConfig) -> SimReport {
        let clock = SimClock()
        let game = Game(balance: config.balance, seed: config.seed, now: { clock.date })
        var report = SimReport()
        var rng = SplitMix64(seed: config.seed &+ 99)
        let sessionGap = 24 * 3600 / Double(config.sessionsPerDay)
        let start = clock.date

        for session in 0..<(config.maxDays * config.sessionsPerDay) {
            if session > 0 {
                // заходит не ровно по часам
                clock.advance(sessionGap * Double.random(in: 0.8...1.2, using: &rng))
            }
            game.refreshEnergy()
            game.expireBubbles()
            if config.openJar { report.energyFromJar += game.openJar() }
            report.sessions += 1
            let stalled = playSession(game, config: config, report: &report)
            if stalled { report.stalledSessions += 1 }
            let day = clock.date.timeIntervalSince(start) / 86400
            for district in game.village.districts where report.districtDoneDay[district.id] == nil {
                if district.tasks.allSatisfy({ game.state.completedTasks.contains($0.id) }) {
                    report.districtDoneDay[district.id] = day
                }
            }
            report.days = day
            if game.isVillageComplete {
                report.villageDone = true
                if config.stopWhenVillageDone { break }
            }
        }
        report.level = game.state.level
        report.tasksDone = game.state.completedTasks.count
        report.bestTier = game.state.bestTier
        return report
    }

    /// Одна сессия: играет, пока есть что делать. Возвращает true, если энергия осталась,
    /// а поле забито так, что потратить ее некуда.
    private static func playSession(_ game: Game, config: SimConfig, report: inout SimReport) -> Bool {
        for _ in 0..<5000 {
            if deliverOrder(game, report: &report) { continue }
            if completeTask(game, report: &report) { continue }
            if mergeSomething(game, report: &report) { continue }
            if config.popBubbles, popBubble(game, report: &report) { continue }
            if game.state.energy > 0 {
                switch spawn(game, report: &report) {
                case .spawned: continue
                case .boardFull:
                    if sellJunk(game, report: &report) { continue }
                    return true
                default:
                    return false
                }
            }
            return false
        }
        return false
    }

    private static func deliverOrder(_ game: Game, report: inout SimReport) -> Bool {
        let ready = game.state.orders.filter(game.canDeliver).sorted { $0.coins > $1.coins }
        guard let order = ready.first else { return false }
        let energyBefore = game.state.energy
        guard game.deliver(orderId: order.id) != nil else { return false }
        report.orders += 1
        report.coinsFromOrders += order.coins
        report.starsEarned += order.stars
        if !game.lastLevelUps.isEmpty { report.energyFromLevels += game.state.energy - energyBefore }
        return true
    }

    private static func completeTask(_ game: Game, report: inout SimReport) -> Bool {
        for task in game.availableTasks.sorted(by: { $0.cost < $1.cost }) where game.state.stars >= task.cost {
            if case .done = game.complete(taskId: task.id) { return true }
        }
        return false
    }

    /// Сколько каждого предмета нужно заказам.
    private static func demand(_ game: Game) -> [Item: Int] {
        var result: [Item: Int] = [:]
        for order in game.state.orders {
            for need in order.needs { result[need, default: 0] += 1 }
        }
        return result
    }

    /// Самая низкая ступень, на которой стоит сливать: не трогает предметы, которые уже ждут заказы,
    /// и не растит цепочку выше, чем просят заказы (кроме случая, когда поле почти забито).
    private static func mergeSomething(_ game: Game, report: inout SimReport) -> Bool {
        let need = demand(game)
        let cells = game.state.cells
        let emptyCount = cells.filter { $0 == nil }.count
        var positions: [Item: [Int]] = [:]
        var generators: [GeneratorPiece: [Int]] = [:]
        for (i, piece) in cells.enumerated() {
            switch piece {
            case .item(let item)?: positions[item, default: []].append(i)
            case .generator(let g)?: generators[g, default: []].append(i)
            default: break
            }
        }
        // генераторы сливаем всегда: это выгодно и освобождает клетку
        for (_, idx) in generators where idx.count >= 2 {
            if case .mergedGenerator = game.move(from: idx[0], to: idx[1]) { return true }
        }
        let maxNeeded = Dictionary(need.keys.map { ($0.chain, $0.tier) }, uniquingKeysWith: max)
        let candidates = positions
            .filter { item, idx in
                let spare = idx.count - (need[item] ?? 0)
                guard spare >= 2 || (idx.count >= 2 && need[item] == nil) else { return false }
                guard game.catalog.next(item) != nil else { return false }
                let target = maxNeeded[item.chain] ?? 0
                return item.tier < target || emptyCount < 6
            }
            .sorted { $0.key.tier < $1.key.tier }
        for (_, idx) in candidates {
            if case .merged = game.move(from: idx[0], to: idx[1]) {
                report.merges += 1
                return true
            }
        }
        return false
    }

    private static func popBubble(_ game: Game, report: inout SimReport) -> Bool {
        let need = demand(game)
        for (i, piece) in game.state.cells.enumerated() {
            guard case .bubble(let item, _)? = piece else { continue }
            // открывает только то, что нужно заказам: так делает разумный игрок
            guard need[item] != nil || need.keys.contains(where: { $0.chain == item.chain && $0.tier > item.tier }) else { continue }
            let cost = game.balance.popCost(item)
            if game.popBubble(at: i) {
                report.bubblesPopped += 1
                report.gemsSpentOnBubbles += cost
                return true
            }
        }
        return false
    }

    /// Предметы, которых заказам еще не хватает (то, что уже лежит на поле, не считается).
    private static func missing(_ game: Game) -> [Item: Int] {
        var onBoard: [Item: Int] = [:]
        for case .item(let item)? in game.state.cells { onBoard[item, default: 0] += 1 }
        var result: [Item: Int] = [:]
        for (item, count) in demand(game) {
            let lack = count - (onBoard[item] ?? 0)
            if lack > 0 { result[item] = lack }
        }
        return result
    }

    /// Тратит энергию на цепочку, которой заказам не хватает больше всего с учетом заготовок на поле.
    private static func spawn(_ game: Game, report: inout SimReport) -> Game.SpawnResult {
        let lack = missing(game)
        var chainNeed: [String: Int] = [:]
        var topTier: [String: Int] = [:]
        for (item, count) in lack {
            chainNeed[item.chain, default: 0] += item.value * count
            topTier[item.chain] = max(topTier[item.chain] ?? 0, item.tier)
        }
        let reserved = demand(game)
        var seen: [Item: Int] = [:]
        for case .item(let item)? in game.state.cells {
            seen[item, default: 0] += 1
            guard let top = topTier[item.chain], item.tier < top,
                  seen[item]! > (reserved[item] ?? 0) else { continue }
            chainNeed[item.chain, default: 0] -= item.value
        }
        let gens = game.state.cells.enumerated().compactMap { i, piece -> (Int, GeneratorPiece)? in
            if case .generator(let g)? = piece { return (i, g) }
            return nil
        }
        guard !gens.isEmpty else { return .notGenerator }
        let best = gens.max { a, b in
            (chainNeed[a.1.chain] ?? Int.min / 2, a.1.tier) < (chainNeed[b.1.chain] ?? Int.min / 2, b.1.tier)
        }!
        let result = game.spawn(from: best.0)
        if case .spawned = result {
            report.spawns += 1
            report.energySpent += 1
        }
        return result
    }

    /// Продает предмет, который меньше всего пригодится. Сначала то, что не ведет к заказам:
    /// цепочки без спроса и ступени не ниже нужной. Заготовки для заказов продаются последними.
    private static func sellJunk(_ game: Game, report: inout SimReport) -> Bool {
        let need = demand(game)
        let target = Dictionary(need.keys.map { ($0.chain, $0.tier) }, uniquingKeysWith: max)
        var counts: [Item: Int] = [:]
        for case .item(let item)? in game.state.cells { counts[item, default: 0] += 1 }
        var reserved = need
        var junk: [(index: Int, item: Item, useful: Bool)] = []
        for (i, piece) in game.state.cells.enumerated() {
            guard case .item(let item)? = piece else { continue }
            if let left = reserved[item], left > 0 {
                reserved[item] = left - 1
                continue
            }
            let useful = item.tier < (target[item.chain] ?? 0)
            junk.append((i, item, useful))
        }
        junk.sort { a, b in
            if a.useful != b.useful { return !a.useful }
            let pairA = (counts[a.item] ?? 0) >= 2, pairB = (counts[b.item] ?? 0) >= 2
            if pairA != pairB { return !pairA }
            return a.item.tier < b.item.tier
        }
        guard let pick = junk.first else { return false }
        report.coinsFromSelling += game.sell(at: pick.index)
        report.itemsSold += 1
        return true
    }
}

final class SimClock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}
