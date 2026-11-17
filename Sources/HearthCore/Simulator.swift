import Foundation

/// Бот, который играет в игру по простой разумной стратегии. Нужен, чтобы проверять баланс тестами:
/// сколько дней уходит на район, не застревает ли поле, нет ли выгодных петель (имбы).
public struct SimConfig {
    /// Сколько раз в день игрок заходит в игру и тратит всю энергию.
    public var sessionsPerDay = 4
    public var maxDays = 150
    public var seed: UInt64 = 1
    /// Открывать ли пузыри за кристаллы.
    public var popBubbles = true
    /// Открывать ли кувшин светлячков бесплатно, когда можно.
    public var openJar = true
    /// Забирать ежедневную награду и покупать энергию за монеты, когда хватает.
    public var claimDaily = true
    public var buyCoinEnergy = true
    /// Забирать награды заданий дня и альбома.
    public var claimQuests = true
    /// Включать ускорение генераторов x2, как только оно откроется.
    public var useBoost = false
    /// Брать животных и забирать их подарки.
    public var keepPets = true
    /// Выполнять заказы странствующего торговца.
    public var serveMerchant = true
    /// Играть в большие события (Глубины и др.) на ходы с заказов.
    public var playAdventures = true
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
    public var energyFromCoins = 0
    public var energyFromEvents = 0
    public var eventMilestones = 0
    public var energyFromQuests = 0
    public var gemsFromQuests = 0
    public var gemsFromCollection = 0
    public var coinsFromCollection = 0
    public var coinsSpent = 0
    public var gemsFromFriends = 0
    public var energyFromFriends = 0
    public var gemsFromAchievements = 0
    public var merchantsServed = 0
    public var gemsFromMerchant = 0
    public var energyFromMerchant = 0
    public var bestFriends = 0
    public var energyFromLucky = 0
    public var petsAdopted = 0
    public var coinsOnPets = 0
    public var energyFromPets = 0
    public var gemsFromPets = 0
    public var coinsFromPets = 0
    public var petsAllDay: Double?
    public var chestsOpened = 0
    public var energyFromShopGift = 0
    public var bestGeneratorLevel = 0
    /// Большие события: сколько сыграно, доля пройденной дорожки в каждом, ценность наград в энергии.
    public var adventureProgress: [Double] = []
    public var adventureValue = 0.0
    public var adventureDepth: [Int] = []
    public var islandFogLeft: [Int] = []
    public var adventureKinds: [AdventureKind] = []
    public var adventurePoints: [Int] = []
    public var islandMerges = 0
    public var islandWashed = 0
    public var greenhouseHarvests = 0
    public var greenhouseWaterings = 0
    public var mosaicWindows = 0
    public var mosaicWasted = 0
    public var mosaicShattered = 0
    public var generatorsDropped = 0
    public var energyFromChests = 0
    public var coinsFromChests = 0
    public var gemsFromChests = 0
    public var thicketsCleared = 0
    /// День, к которому расчищены все заросли (nil - не расчищены или их не было).
    public var thicketsDoneDay: Double?
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
        пузыри \(bubblesPopped) за \(gemsSpentOnBubbles) кр, энергия с уровней \(energyFromLevels), из кувшина \(energyFromJar), за монеты \(energyFromCoins) (\(coinsSpent) мон), с событий \(energyFromEvents) (\(eventMilestones) наград), с заданий \(energyFromQuests), застреваний \(stalledSessions)
        кристаллы: задания \(gemsFromQuests), альбом \(gemsFromCollection), дружба \(gemsFromFriends), достижения \(gemsFromAchievements), торговец \(gemsFromMerchant); монеты из альбома \(coinsFromCollection)
        торговец: \(merchantsServed) раз, энергия \(energyFromMerchant); дружба: энергия \(energyFromFriends), лучших друзей \(bestFriends), счастливые слияния \(energyFromLucky)
        животные: \(petsAdopted) за \(coinsOnPets) мон, все к дню \(petsAllDay.map { String(format: "%.1f", $0) } ?? "-"), подарки: энергия \(energyFromPets), кр \(gemsFromPets), мон \(coinsFromPets)
        заросли: \(thicketsCleared), все к дню \(thicketsDoneDay.map { String(format: "%.1f", $0) } ?? "-"); ящики: \(chestsOpened), энергия \(energyFromChests), мон \(coinsFromChests), кр \(gemsFromChests)
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
        var adventureKey: String?
        var adventureLast: AdventureState?

        for session in 0..<(config.maxDays * config.sessionsPerDay) {
            if session > 0 {
                // заходит не ровно по часам
                clock.advance(sessionGap * Double.random(in: 0.8...1.2, using: &rng))
            }
            game.refreshEnergy()
            game.expireBubbles()
            if config.serveMerchant { game.updateMerchant() }
            if config.openJar { report.energyFromJar += game.openJar() }
            if config.claimDaily {
                game.claimDaily()
                if let gift = game.claimShopGift() { report.energyFromShopGift += gift.energy }
            }
            while config.buyCoinEnergy, let price = game.coinEnergyPrice, game.state.coins >= price, game.buyEnergyWithCoins() {
                report.energyFromCoins += game.balance.coinEnergyAmount
                report.coinsSpent += price
            }
            report.sessions += 1
            let stalled = playSession(game, config: config, report: &report)
            if stalled { report.stalledSessions += 1 }
            if config.playAdventures { playAdventure(game, report: &report, lastKey: &adventureKey, lastState: &adventureLast) }
            if config.claimQuests { claimRewards(game, report: &report) }
            let day = clock.date.timeIntervalSince(start) / 86400
            if config.keepPets {
                tendPets(game, report: &report)
                if report.petsAllDay == nil, game.state.petsOwned.count == Pets.all.count { report.petsAllDay = day }
            }
            for district in game.village.districts where report.districtDoneDay[district.id] == nil {
                if district.tasks.allSatisfy({ game.state.completedTasks.contains($0.id) }) {
                    report.districtDoneDay[district.id] = day
                }
            }
            report.days = day
            if report.thicketsDoneDay == nil, report.thicketsCleared > 0, game.thicketsLeft == 0 { report.thicketsDoneDay = day }
            if game.isVillageComplete {
                report.villageDone = true
                if config.stopWhenVillageDone { break }
            }
        }
        if let last = adventureLast { finishAdventure(last, game: game, report: &report) }
        report.level = game.state.level
        report.tasksDone = game.state.completedTasks.count
        report.bestFriends = game.bestFriends
        report.merchantsServed = game.state.merchantsServed
        report.bestTier = game.state.bestTier
        report.bestGeneratorLevel = game.bestGeneratorLevel
        return report
    }

    /// Одна сессия: играет, пока есть что делать. Возвращает true, если энергия осталась,
    /// а поле забито так, что потратить ее некуда.
    private static func playSession(_ game: Game, config: SimConfig, report: inout SimReport) -> Bool {
        for _ in 0..<5000 {
            if config.serveMerchant, let visit = game.deliverMerchant() {
                report.gemsFromMerchant += visit.gems
                report.energyFromMerchant += visit.energy
                continue
            }
            if deliverOrder(game, report: &report) { continue }
            if completeTask(game, report: &report) { continue }
            if clearThicket(game, report: &report) { continue }
            if handleChests(game, report: &report) { continue }
            if mergeSomething(game, report: &report) { continue }
            if config.popBubbles, popBubble(game, report: &report) { continue }
            if game.state.energy > 0 {
                switch spawn(game, config: config, report: &report) {
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

    /// Животные: забирает подарки и берет следующее животное, если после покупки энергии
    /// за монеты остается запас.
    private static func tendPets(_ game: Game, report: inout SimReport) {
        for id in game.state.petsOwned {
            if let r = game.collectPet(id) {
                report.energyFromPets += r.energy
                report.gemsFromPets += r.gems
                report.coinsFromPets += r.coins
            }
        }
        let reserve = (game.coinEnergyPrice ?? 0) * 2
        for pet in Pets.all where !game.petOwned(pet.id) && game.state.coins >= pet.cost + reserve {
            if game.adoptPet(pet.id) {
                report.petsAdopted += 1
                report.coinsOnPets += pet.cost
                if let r = game.collectPet(pet.id) {
                    report.energyFromPets += r.energy
                    report.gemsFromPets += r.gems
                    report.coinsFromPets += r.coins
                }
            }
        }
    }

    /// Задания дня и альбом: забирает все, что можно.
    private static func claimRewards(_ game: Game, report: inout SimReport) {
        for i in game.ensureQuests().indices {
            if let r = game.claimQuest(i) {
                report.energyFromQuests += r.energy
                report.gemsFromQuests += r.gems
            }
        }
        if let r = game.claimQuestChest() {
            report.energyFromQuests += r.energy
            report.gemsFromQuests += r.gems
        }
        for key in game.state.discovered {
            let parts = key.split(separator: "#")
            guard parts.count == 2, let tier = Int(parts[1]) else { continue }
            if let r = game.claimDiscovery(Item(chain: String(parts[0]), tier: tier)) {
                report.gemsFromCollection += r.gems
                report.coinsFromCollection += r.coins
            }
        }
        for chain in game.catalog.chains {
            if let gems = game.claimChain(chain.id) { report.gemsFromCollection += gems }
        }
        for resident in Friends.all {
            while let r = game.claimFriend(resident) {
                report.gemsFromFriends += r.gems
                report.energyFromFriends += r.energy
            }
        }
        for kind in AchievementKind.allCases {
            while let r = game.claimAchievement(kind) { report.gemsFromAchievements += r.gems }
        }
    }

    private static func deliverOrder(_ game: Game, report: inout SimReport) -> Bool {
        let ready = game.state.orders.filter(game.canDeliver).sorted { $0.coins > $1.coins }
        guard let order = ready.first else { return false }
        game.refreshEnergy()
        let energyBefore = game.state.energy
        guard game.deliver(orderId: order.id) != nil else { return false }
        report.orders += 1
        report.coinsFromOrders += order.coins
        report.starsEarned += order.stars
        let eventEnergy = game.lastEventRewards.reduce(0) { $0 + $1.energy }
        report.energyFromEvents += eventEnergy
        report.eventMilestones += game.lastEventRewards.count
        if !game.lastLevelUps.isEmpty { report.energyFromLevels += game.state.energy - energyBefore - eventEnergy }
        if game.eventNeedsChoice, let choice = game.activeEvent?.choices.first { game.chooseEvent(choice.id) }
        return true
    }

    private static func completeTask(_ game: Game, report: inout SimReport) -> Bool {
        for task in game.availableTasks.sorted(by: { $0.cost < $1.cost }) where game.state.stars >= task.cost {
            if case .done = game.complete(taskId: task.id) { return true }
        }
        return false
    }

    /// Сколько каждого предмета нужно заказам.
    private static func orderDemand(_ game: Game) -> [Item: Int] {
        var result: [Item: Int] = [:]
        for order in game.state.orders {
            for need in order.needs { result[need, default: 0] += 1 }
        }
        for need in game.state.merchant?.needs ?? [] { result[need, default: 0] += 1 }
        return result
    }

    /// Что нужно: заказы, торговец и видимые заросли (на них кладут такой же предмет).
    private static func demand(_ game: Game) -> [Item: Int] {
        var result = orderDemand(game)
        for t in game.revealedThickets { result[t.item, default: 0] += 1 }
        return result
    }

    /// Кладет лишний предмет на такой же в зарослях.
    private static func clearThicket(_ game: Game, report: inout SimReport) -> Bool {
        let reserved = orderDemand(game)
        var positions: [Item: [Int]] = [:]
        for (i, piece) in game.state.cells.enumerated() {
            if case .item(let item)? = piece { positions[item, default: []].append(i) }
        }
        for t in game.revealedThickets {
            guard let idx = positions[t.item], idx.count > (reserved[t.item] ?? 0) else { continue }
            if case .unlocked = game.move(from: idx.last!, to: t.index) {
                report.thicketsCleared += 1
                report.merges += 1
                return true
            }
        }
        return false
    }

    /// Ящики: одинаковые сливает, остальные открывает (с предметами - когда хватает места).
    private static func handleChests(_ game: Game, report: inout SimReport) -> Bool {
        var positions: [Chest: [Int]] = [:]
        for (i, piece) in game.state.cells.enumerated() {
            if case .chest(let c)? = piece { positions[c, default: []].append(i) }
        }
        // порядок словаря случайный от запуска к запуску: идем по клеткам, чтобы бот был повторяемым
        let groups = positions.sorted { $0.value[0] < $1.value[0] }
        for (chest, idx) in groups where idx.count >= 2 && chest.canMerge {
            if case .mergedChest = game.move(from: idx[0], to: idx[1]) { return true }
        }
        let empty = game.state.cells.filter { $0 == nil }.count
        for (chest, idx) in groups {
            if chest.kind == .items, empty < 3, chest.remaining > 1 { continue }
            if case .opened(let r) = game.openChest(at: idx[0]) {
                if game.piece(at: idx[0]).map({ if case .chest = $0 { return false } else { return true } }) ?? true {
                    report.chestsOpened += 1
                }
                report.energyFromChests += r.energy
                report.coinsFromChests += r.coins
                report.gemsFromChests += r.gems
                return true
            }
        }
        return false
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
        for idx in generators.values.sorted(by: { $0[0] < $1[0] }) where idx.count >= 2 {
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
            .sorted { ($0.key.tier, $0.value[0]) < ($1.key.tier, $1.value[0]) }
        for (_, idx) in candidates {
            let gens = generatorCount(game)
            if case .merged = game.move(from: idx[0], to: idx[1]) {
                report.generatorsDropped += max(0, generatorCount(game) - gens)
                report.merges += 1
                report.energyFromLucky += game.lastLuckyEnergy
                return true
            }
        }
        return false
    }

    // MARK: - Большие события

    static func prizeValue(_ prize: AdventurePrize) -> Double {
        switch prize {
        case .chest(let c):
            switch c.kind {
            case .energy: return Double(c.amount)
            case .coins: return Double(c.amount) / 12
            case .gems: return Double(c.amount * 2)
            case .items: return Double(c.amount) * 1.5
            }
        case .generator: return 20
        case .decor: return 0
        }
    }

    private static func finishAdventure(_ a: AdventureState, game: Game, report: inout SimReport) {
        let track = game.adventureTrack(a.kind)
        guard !track.isEmpty else { return }
        report.adventureProgress.append(Double(a.claimed) / Double(track.count))
        report.adventureKinds.append(a.kind)
        report.adventurePoints.append(a.points)
        report.adventureValue += track.prefix(a.claimed).reduce(0) { $0 + prizeValue($1.prize) }
        if let s = a.island {
            report.islandFogLeft.append(s.fogLeft)
            // клады, которые открылись
            for (n, prize) in Island.treasures.enumerated() where !s.cells.contains(where: { $0.fog && $0.secret == .treasure(n) }) {
                report.adventureValue += prizeValue(prize)
            }
        }
        if let d = a.depths {
            let deepest = d.cells.indices.filter { d.cells[$0].isOpen }.map { $0 / DepthsState.width }.max() ?? -1
            report.adventureDepth.append(deepest + 1)
            for (i, row) in Depths.treasureRows.enumerated() where deepest >= row {
                report.adventureValue += prizeValue(Depths.treasures[i])
            }
        }
    }

    private static func playAdventure(_ game: Game, report: inout SimReport, lastKey: inout String?, lastState: inout AdventureState?) {
        let current = game.adventure
        if let last = lastState, last.key != current?.key {
            finishAdventure(last, game: game, report: &report)
            lastState = nil
        }
        guard let a = current else { return }
        lastKey = a.key
        game.claimAdventureDaily()
        if a.kind == .island {
            playIsland(game, report: &report)
            lastState = game.adventure
            return
        }
        if a.kind == .greenhouse {
            playGreenhouse(game, report: &report)
            lastState = game.adventure
            return
        }
        if a.kind == .mosaic {
            playMosaic(game, report: &report)
            lastState = game.adventure
            return
        }
        guard a.kind == .depths else { return }
        for _ in 0..<3000 {
            if mergeFinds(game) { continue }
            if deliverFinds(game, all: false) { continue }
            if collectWaiting(game) { continue }
            guard (game.adventure?.moves ?? 0) > 0, let target = digTarget(game) else { break }
            _ = game.dig(target)
        }
        // в последний день сдает все, что осталось
        if let ends = game.adventureEndsAt, ends.timeIntervalSince(game.now()) < 9 * 3600 {
            while deliverFinds(game, all: true) {}
        }
        lastState = game.adventure
    }

    /// Остров: сводит одинаковые предметы к самой большой группе (лучше у тумана),
    /// при тесноте смывает лишнее, иначе зовет прилив.
    private static func playIsland(_ game: Game, report: inout SimReport) {
        for _ in 0..<4000 {
            guard let s = game.adventure?.island else { return }
            if case let (from, to)? = islandMergeMove(s) {
                if let r = game.moveOnIsland(from: from, to: to) {
                    report.islandMerges += r.merges.count
                    continue
                }
            }
            switch game.tide() {
            case .placed: continue
            case .noMoves: return
            case .noRoom:
                // смывает предмет, которому не с кем слиться
                var counts: [Item: Int] = [:]
                for c in s.cells where !c.fog { if let item = c.item { counts[item, default: 0] += 1 } }
                let lonely = s.cells.indices.filter { i in
                    guard !s.cells[i].fog, let item = s.cells[i].item else { return false }
                    return (counts[item] ?? 0) < 3
                }.min { (s.cells[$0].item?.tier ?? 0, $0) < (s.cells[$1].item?.tier ?? 0, $1) }
                guard let i = lonely ?? s.cells.indices.first(where: { !s.cells[$0].fog && s.cells[$0].item != nil }) else { return }
                game.washAway(i)
                report.islandWashed += 1
            }
        }
    }

    /// Теплица: поливает, сливает пары, собирает спелое без пары, сажает на свободные грядки.
    private static func playGreenhouse(_ game: Game, report: inout SimReport) {
        if game.water() { report.greenhouseWaterings += 1 }
        for _ in 0..<500 {
            guard let g = game.adventure?.greenhouse else { return }
            // пары одинаковых: сначала младшие
            var pair: (Int, Int)?
            var seen: [Item: Int] = [:]
            for i in g.beds.indices.sorted(by: { (g.beds[$0]?.item.tier ?? 99, $0) < (g.beds[$1]?.item.tier ?? 99, $1) }) {
                guard let p = g.beds[i], p.item.tier < Greenhouse.maxTier else { continue }
                if let j = seen[p.item] { pair = (i, j); break }
                seen[p.item] = i
            }
            if case let (a, b)? = pair, game.movePlant(from: a, to: b) { continue }
            // спелое без пары
            if let i = g.beds.indices.first(where: { g.beds[$0]?.ripe(at: game.now()) == true }), game.harvest(i) != nil {
                report.greenhouseHarvests += 1
                continue
            }
            if case .planted = game.plantSeed() { continue }
            return
        }
    }

    /// Витраж: кладет кусочек, который закрывает область почти без потерь; сливает пары, если
    /// в окне есть область под больший кусочек; при полном верстаке кладет самый выгодный или разбивает лишний.
    private static func playMosaic(_ game: Game, report: inout SimReport) {
        func record(_ r: Game.MosaicSet?) {
            guard let r else { return }
            report.mosaicWasted += r.wasted
            if r.windowDone {
                report.mosaicWindows += 1
                report.adventureValue += prizeValue(Mosaic.windowPrize)
            }
        }
        for _ in 0..<3000 {
            guard let m = game.adventure?.mosaic else { return }
            // лучшая область для каждого кусочка: самая большая пустая часть своего цвета
            var options: [(slot: Int, cell: Int, open: Int, cover: Int)] = []
            for (slot, item) in m.bench.enumerated() {
                guard let item, let color = MosaicState.color(of: item) else { continue }
                var best: (cell: Int, open: Int)?
                for region in Set(m.regions).sorted() {
                    guard let cell = m.regions.indices.first(where: { m.regions[$0] == region && !m.filled[$0] && m.colors[$0] == color }) else { continue }
                    let open = m.openCells(region: region, near: cell).count
                    if best == nil || open > best!.open { best = (cell, open) }
                }
                if let best { options.append((slot, best.cell, best.open, Mosaic.cover[item.tier])) }
            }
            // закрывает область целиком, потеряв не больше трети
            if let o = options.first(where: { $0.open <= $0.cover && ($0.cover - $0.open) * 3 <= $0.cover }) {
                record(game.setGlass(slot: o.slot, cell: o.cell)); continue
            }
            // пара, которой есть куда лечь после слияния
            var merged = false
            for a in m.bench.indices {
                for b in m.bench.indices where b > a && game.canMergeGlass(a, b) {
                    let next = Mosaic.cover[(m.bench[a]?.tier ?? 0) + 1]
                    if let o = options.first(where: { $0.slot == a }), o.open * 3 >= next * 2 {
                        merged = game.moveGlass(from: a, to: b)
                        break
                    }
                }
                if merged { break }
            }
            if merged { continue }
            if m.freeSlots.isEmpty {
                // самый крупный вклад без большой потери
                if let o = options.max(by: { min($0.open, $0.cover) < min($1.open, $1.cover) }) {
                    record(game.setGlass(slot: o.slot, cell: o.cell)); continue
                }
                if let slot = m.bench.indices.min(by: { (m.bench[$0]?.tier ?? 0) < (m.bench[$1]?.tier ?? 0) }) {
                    game.shatterGlass(slot)
                    report.mosaicShattered += 1
                    continue
                }
                return
            }
            switch game.cutGlass() {
            case .cut, .noRoom: continue
            case .noMoves:
                // ходы кончились: кладет все, что не ждет пары
                guard let o = options.first(where: { o in
                    !m.bench.indices.contains { $0 != o.slot && game.canMergeGlass($0, o.slot) }
                }) else { return }
                record(game.setGlass(slot: o.slot, cell: o.cell))
            }
        }
    }

    /// Ход, после которого сольются хотя бы 3 предмета: предмет того же вида ставится рядом с группой.
    static func islandMergeMove(_ s: IslandState) -> (Int, Int)? {
        var best: (from: Int, to: Int, score: Int)?
        var done: Set<Int> = []
        for i in s.cells.indices where !done.contains(i) {
            guard !s.cells[i].fog, let item = s.cells[i].item, item.tier < Island.maxTier else { continue }
            let group = s.group(at: i)
            done.formUnion(group)
            let members = Set(group)
            // свободные или чужие клетки вокруг группы
            let around = Set(group.flatMap(IslandState.neighbors)).subtracting(members).filter { !s.cells[$0].fog }
            for to in around.sorted() {
                // вместе с соседними группами того же вида
                var merged = members
                for n in IslandState.neighbors(to) where !s.cells[n].fog && s.cells[n].item == item { merged.formUnion(s.group(at: n)) }
                guard merged.count + 1 >= 3 else { continue }
                guard let from = s.cells.indices.first(where: { j in
                    !merged.contains(j) && j != to && !s.cells[j].fog && s.cells[j].item == item
                }) else { continue }
                let fog = IslandState.neighbors(to).filter { s.cells[$0].fog }.count
                    + group.flatMap(IslandState.neighbors).filter { s.cells[$0].fog }.count
                let score = (merged.count + 1) * 10 + fog * 3 + item.tier * 5
                if best == nil || score > best!.score { best = (from, to, score) }
            }
        }
        return best.map { ($0.from, $0.to) }
    }

    private static func mergeFinds(_ game: Game) -> Bool {
        guard let board = game.adventure?.depths?.board else { return false }
        var seen: [Item: Int] = [:]
        for (i, item) in board.enumerated() {
            guard let item, item.tier < Depths.maxTier else { continue }
            if let j = seen[item] { return game.moveFind(from: i, to: j) }
            seen[item] = i
        }
        return false
    }

    private static func deliverFinds(_ game: Game, all: Bool) -> Bool {
        guard let board = game.adventure?.depths?.board else { return false }
        let filled = board.compactMap { $0 }
        var counts: [Item: Int] = [:]
        for item in filled { counts[item, default: 0] += 1 }
        let crowded = filled.count > DepthsState.boardSize - 4
        let pick = board.indices.filter { i in
            guard let item = board[i] else { return false }
            if all { return true }
            if item.tier >= Depths.maxTier { return true }
            return crowded && (counts[item] ?? 0) < 2
        }.min { (board[$0]?.tier ?? 0) < (board[$1]?.tier ?? 0) }
        guard let slot = pick else { return false }
        return game.deliverFind(slot) != nil
    }

    private static func collectWaiting(_ game: Game) -> Bool {
        guard let d = game.adventure?.depths, d.board.contains(where: { $0 == nil }) else { return false }
        for i in d.cells.indices where d.cells[i].isOpen {
            if case .find? = d.cells[i].content, game.collectDepth(i) != nil { return true }
        }
        return false
    }

    private static func digTarget(_ game: Game) -> Int? {
        guard let d = game.adventure?.depths else { return nil }
        let w = DepthsState.width
        let treasure = d.cells.indices.first { game.depthTreasureVisible($0) }
        let options = d.cells.indices.filter { game.canDig($0) }
        return options.min { a, b in
            func score(_ i: Int) -> Double {
                var s = Double(d.cells[i].hardness) * 2 - Double(i / w) * 0.3
                if let t = treasure { s += Double(abs(t / w - i / w) + abs(t % w - i % w)) * 0.5 }
                return s
            }
            return score(a) < score(b)
        }
    }

    private static func generatorCount(_ game: Game) -> Int {
        game.state.pendingGenerators.count + game.state.cells.filter { if case .generator? = $0 { return true } else { return false } }.count
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
    private static func spawn(_ game: Game, config: SimConfig, report: inout SimReport) -> Game.SpawnResult {
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
        if config.useBoost, game.boostUnlocked, !game.state.boostOn { game.setBoost(true) }
        game.refreshEnergy()
        let energyBefore = game.state.energy
        let result = game.spawn(from: best.0)
        if case .spawned = result {
            report.spawns += 1
            report.energySpent += max(1, energyBefore - game.state.energy)
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
    init(_ date: Date = Date(timeIntervalSince1970: 1_800_000_000)) { self.date = date }
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}
