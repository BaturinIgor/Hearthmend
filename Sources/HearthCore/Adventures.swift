import Foundation

/// Большие события (1.2): у каждого своя карта и своя валюта, которая зарабатывается заказами
/// на главном поле. Награды приходят на главное поле: ресурсы и ящики встают в свободные клетки
/// и сливаются дальше, генераторы и украшения - как обычно. Идут с понедельника по четверг,
/// вид события меняется каждую неделю; на выходных остается ярмарка ленточек.
public enum AdventureKind: String, Codable, CaseIterable {
    case depths, greenhouse, island, mosaic, lanterns

    /// Какие события уже готовы и входят в круг.
    public static let rotation: [AdventureKind] = [.depths, .island, .greenhouse, .mosaic]
}

/// Награда ступени события.
public enum AdventurePrize: Codable, Equatable {
    case chest(Chest)
    case generator(String)
    case decor(String)
}

public struct AdventureMilestone: Equatable {
    public let points: Int
    public let prize: AdventurePrize
}

public struct AdventureState: Codable, Equatable {
    public var key: String
    public var kind: AdventureKind
    /// Валюта события: кирки, семена, ракушки...
    public var moves: Int
    public var points: Int = 0
    public var claimed: Int = 0
    public var dailyDay: Int = Int.min
    public var depths: DepthsState?
    public var island: IslandState?
    public var greenhouse: GreenhouseState?
    public var mosaic: MosaicState?

    public init(key: String, kind: AdventureKind, moves: Int) {
        self.key = key
        self.kind = kind
        self.moves = moves
    }
}

extension Balance {
    /// С какого уровня открываются большие события.
    public static let adventureLevel = 4
    /// Сколько ходов дают на старте события и бесплатно раз в день.
    public static let adventureStartMoves = 10
    public static let adventureDailyMoves = 5
}

extension Game {
    // MARK: - Расписание

    /// Событие идет с понедельника 00:00 до конца четверга по времени игрока.
    public func adventureSchedule(at date: Date) -> (key: String, kind: AdventureKind, ends: Date)? {
        let cal = Self.eventCalendar
        let weekday = cal.component(.weekday, from: date) // 2 - понедельник ... 5 - четверг
        guard (2...5).contains(weekday), !AdventureKind.rotation.isEmpty else { return nil }
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = comps.yearForWeekOfYear ?? 0, week = comps.weekOfYear ?? 0
        let kind = AdventureKind.rotation[(year * 53 + week) % AdventureKind.rotation.count]
        let ends = cal.date(byAdding: .day, value: 6 - weekday, to: cal.startOfDay(for: date)) ?? date
        return ("\(year)-\(week)-\(kind.rawValue)", kind, ends)
    }

    public var adventureUnlocked: Bool { state.level >= Balance.adventureLevel }

    /// Текущее событие. Новое событие начинается с чистой карты; старое пропадает целиком.
    public var adventure: AdventureState? {
        guard adventureUnlocked, let s = adventureSchedule(at: now()) else { return nil }
        if state.adventure?.key != s.key {
            var a = AdventureState(key: s.key, kind: s.kind, moves: Balance.adventureStartMoves)
            switch s.kind {
            case .depths: a.depths = DepthsState.generate(seed: Self.seed(of: s.key))
            case .island: a.island = IslandState.generate(seed: Self.seed(of: s.key))
            case .greenhouse: a.greenhouse = GreenhouseState.make(now: now())
            case .mosaic: a.mosaic = MosaicState.generate(seed: Self.seed(of: s.key))
            default: break
            }
            state.adventure = a
        }
        return state.adventure
    }

    public var adventureEndsAt: Date? { adventureSchedule(at: now())?.ends }

    static func seed(of key: String) -> UInt64 {
        // FNV-1a: одинаковое поле у всех игроков в одну неделю
        var h: UInt64 = 0xcbf29ce484222325
        for b in key.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }

    // MARK: - Ходы

    /// Ходы за сданный заказ: 1-5 по сложности.
    static func adventureMoves(for order: Order) -> Int { min(5, max(1, (order.stars + 1) / 2)) }

    func addAdventureMoves(for order: Order) {
        guard adventure != nil else { return }
        state.adventure?.moves += Self.adventureMoves(for: order)
    }

    public var adventureDailyReady: Bool {
        guard let a = adventure else { return false }
        return a.dailyDay < questDay
    }

    @discardableResult
    public func claimAdventureDaily() -> Int {
        guard adventureDailyReady else { return 0 }
        state.adventure?.dailyDay = questDay
        state.adventure?.moves += Balance.adventureDailyMoves
        return Balance.adventureDailyMoves
    }

    func spendAdventureMoves(_ n: Int) -> Bool {
        guard let a = adventure, a.moves >= n else { return false }
        state.adventure?.moves -= n
        return true
    }

    // MARK: - Дорожка наград

    public func adventureTrack(_ kind: AdventureKind) -> [AdventureMilestone] {
        switch kind {
        case .depths: return Depths.track
        case .island: return Island.track
        case .greenhouse: return Greenhouse.track
        case .mosaic: return Mosaic.track
        default: return []
        }
    }

    /// Начисляет очки и выдает все открывшиеся награды.
    @discardableResult
    func addAdventurePoints(_ points: Int) -> [AdventurePrize] {
        guard let a = adventure, points > 0 else { return [] }
        state.adventure?.points += points
        let track = adventureTrack(a.kind)
        var prizes: [AdventurePrize] = []
        while let cur = state.adventure, cur.claimed < track.count, cur.points >= track[cur.claimed].points {
            let prize = track[cur.claimed].prize
            grantAdventurePrize(prize)
            prizes.append(prize)
            state.adventure?.claimed += 1
        }
        return prizes
    }

    func grantAdventurePrize(_ prize: AdventurePrize) {
        switch prize {
        case .chest(let chest): state.pendingChests.append(chest)
        case .generator(let chain): state.pendingGenerators.append(state.unlockedChains.contains(chain) ? chain : Game.startChains[0])
        case .decor(let key): state.decorOwned[key, default: 0] += 1
        }
        placePendingGenerators()
    }

    /// Красная точка на значке события: есть бесплатные ходы или есть чем ходить.
    public var adventureNeedsAttention: Bool {
        guard let a = adventure else { return false }
        return adventureDailyReady || a.moves >= 3 || greenhouseNeedsAttention
    }
}
