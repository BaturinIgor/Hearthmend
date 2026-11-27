import Foundation

/// События выходных: с пятницы по воскресенье заказы дают ленточки, ленточки открывают награды
/// на дорожке. Посередине игрок выбирает, кому из жителей помочь, и от выбора зависит украшение.
/// Украшения ставятся на карту деревни куда угодно.
public struct EventMilestone: Codable, Equatable {
    public let tokens: Int
    public var gems: Int?
    public var energy: Int?
    public var coins: Int?
    public var decor: String?
    /// Украшение по выбору игрока: без выбора эта ступень не открывается.
    public var choiceDecor: Bool?
}

public struct EventChoice: Codable, Equatable {
    public let id: String
    public let decor: String
}

public struct EventDef: Codable, Equatable, Identifiable {
    public let id: String
    public let milestones: [EventMilestone]
    public let choices: [EventChoice]

    public var maxTokens: Int { milestones.last?.tokens ?? 0 }
}

public struct EventsDef: Codable, Equatable {
    public let events: [EventDef]

    public static func load(from data: Data) throws -> EventsDef {
        try JSONDecoder().decode(EventsDef.self, from: data)
    }

    public static let bundled: EventsDef = {
        guard let url = Bundle.module.url(forResource: "events", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let def = try? load(from: data) else {
            fatalError("events.json не найден или поврежден")
        }
        return def
    }()
}

/// Украшение, поставленное на карту. x, y - середина нижнего края в клетках карты (можно дробные).
public struct PlacedDecor: Codable, Equatable, Identifiable {
    public let id: Int
    public let key: String
    public var x: Double
    public var y: Double
}

/// Что дала ступень события: интерфейс показывает это игроку.
public struct EventReward: Equatable {
    public var gems = 0
    public var energy = 0
    public var coins = 0
    public var decor: String?

    public init(gems: Int = 0, energy: Int = 0, coins: Int = 0, decor: String? = nil) {
        self.gems = gems
        self.energy = energy
        self.coins = coins
        self.decor = decor
    }
}

extension Game {
    // MARK: - Расписание

    /// Календарь событий: григорианский в часовом поясе игрока.
    static var eventCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        cal.firstWeekday = 2
        return cal
    }

    /// Событие идет с пятницы 00:00 до конца воскресенья. Ключ - неделя года, по нему же выбирается событие.
    public func eventSchedule(at date: Date) -> (key: String, def: EventDef, ends: Date)? {
        let cal = Self.eventCalendar
        let weekday = cal.component(.weekday, from: date) // 1 - воскресенье, 6 - пятница, 7 - суббота
        guard weekday == 6 || weekday == 7 || weekday == 1, !events.events.isEmpty else { return nil }
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = comps.yearForWeekOfYear ?? 0, week = comps.weekOfYear ?? 0
        let def = events.events[(year * 53 + week) % events.events.count]
        let dayStart = cal.startOfDay(for: date)
        let daysLeft = weekday == 1 ? 1 : (weekday == 7 ? 2 : 3)
        let ends = cal.date(byAdding: .day, value: daysLeft, to: dayStart) ?? date
        return ("\(year)-\(week)-\(def.id)", def, ends)
    }

    /// Текущее событие или nil. Переход на новое событие сбрасывает ленточки и выбор.
    public var activeEvent: EventDef? {
        guard let s = eventSchedule(at: now()) else { return nil }
        if state.eventKey != s.key {
            state.eventKey = s.key
            state.eventTokens = 0
            state.eventClaimed = 0
            state.eventChoice = nil
        }
        return s.def
    }

    public var eventEndsAt: Date? { eventSchedule(at: now())?.ends }

    // MARK: - Ленточки и награды

    /// Начисляет ленточки (вызывается при сдаче заказа) и выдает открывшиеся награды.
    @discardableResult
    func addEventTokens(_ amount: Int) -> [EventReward] {
        guard let def = activeEvent, amount > 0 else { return [] }
        state.eventTokens = min(def.maxTokens, state.eventTokens + amount)
        return claimEventMilestones()
    }

    /// Выдает все ступени, до которых хватает ленточек. Ступень с выбором ждет, пока игрок выберет.
    @discardableResult
    public func claimEventMilestones() -> [EventReward] {
        guard let def = activeEvent else { return [] }
        var rewards: [EventReward] = []
        while state.eventClaimed < def.milestones.count {
            let m = def.milestones[state.eventClaimed]
            guard state.eventTokens >= m.tokens else { break }
            var reward = EventReward(gems: m.gems ?? 0, energy: m.energy ?? 0, coins: m.coins ?? 0, decor: m.decor)
            if m.choiceDecor == true {
                guard let choice = state.eventChoice,
                      let picked = def.choices.first(where: { $0.id == choice }) else { break }
                reward.decor = picked.decor
            }
            state.gems += reward.gems
            state.energy += reward.energy
            state.coins += reward.coins
            if let decor = reward.decor { giveDecor(decor) }
            state.eventClaimed += 1
            rewards.append(reward)
        }
        return rewards + claimEventPassRewards()
    }

    /// Выбор жителя. Сделать его можно один раз за событие.
    @discardableResult
    public func chooseEvent(_ choiceId: String) -> [EventReward] {
        guard let def = activeEvent, state.eventChoice == nil,
              def.choices.contains(where: { $0.id == choiceId }) else { return [] }
        state.eventChoice = choiceId
        return claimEventMilestones()
    }

    /// Нужно ли сейчас выбрать жителя: следующая ступень с выбором уже открыта ленточками.
    public var eventNeedsChoice: Bool {
        guard let def = activeEvent, state.eventChoice == nil,
              state.eventClaimed < def.milestones.count else { return false }
        let m = def.milestones[state.eventClaimed]
        return m.choiceDecor == true && state.eventTokens >= m.tokens
    }

    // MARK: - Украшения на карте

    public static let mapSize = (width: 32.0, height: 134.0)

    @discardableResult
    /// Новое украшение в запас деревни.
    func giveDecor(_ key: String) {
        state.decorOwned[key, default: 0] += 1
        state.newDecor = true
    }

    /// Игрок открыл запас украшений: точка гаснет.
    public func seeNewDecor() { state.newDecor = false }

    public func placeDecor(_ key: String, x: Double, y: Double) -> PlacedDecor? {
        guard (state.decorOwned[key] ?? 0) > 0 else { return nil }
        let placed = PlacedDecor(id: state.nextDecorId, key: key, x: clampX(x), y: clampY(y))
        state.nextDecorId += 1
        state.decorOwned[key]! -= 1
        if state.decorOwned[key] == 0 { state.decorOwned[key] = nil }
        state.placedDecor.append(placed)
        return placed
    }

    public func moveDecor(id: Int, x: Double, y: Double) {
        guard let i = state.placedDecor.firstIndex(where: { $0.id == id }) else { return }
        state.placedDecor[i].x = clampX(x)
        state.placedDecor[i].y = clampY(y)
    }

    /// Убирает украшение обратно в запас.
    public func storeDecor(id: Int) {
        guard let i = state.placedDecor.firstIndex(where: { $0.id == id }) else { return }
        let key = state.placedDecor.remove(at: i).key
        state.decorOwned[key, default: 0] += 1
    }

    func clampX(_ x: Double) -> Double { min(max(x, 0.5), Self.mapSize.width - 0.5) }
    /// Не выше тумана над закрытыми районами: margin - запас под высоту предмета (основание на y).
    func clampY(_ y: Double, margin: Double = 1.5) -> Double {
        let top = max(1, (fogRow ?? 0) + margin)
        return min(max(y, top), Self.mapSize.height)
    }
}
