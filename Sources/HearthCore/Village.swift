import Foundation

/// Задача восстановления деревни: стоит звезды, открывается после других задач,
/// на карте превращает руины в постройку и иногда приводит жителя с новой цепочкой.
public struct VillageTask: Codable, Equatable, Identifiable {
    public let id: String
    public let cost: Int
    public let requires: [String]
    /// Спрайт постройки на карте деревни.
    public let building: String
    /// Место на карте в клетках по 16 пикселей.
    public let x: Double
    public let y: Int
    public var gems: Int?
    public var unlocksChain: String?
    public var resident: String?
}

public struct District: Codable, Equatable, Identifiable {
    public let id: String
    public let tasks: [VillageTask]

    public var totalCost: Int { tasks.reduce(0) { $0 + $1.cost } }
}

public struct VillageDef: Codable, Equatable {
    public let districts: [District]

    public var allTasks: [VillageTask] { districts.flatMap(\.tasks) }

    public func task(_ id: String) -> VillageTask? {
        allTasks.first { $0.id == id }
    }

    public func district(of taskId: String) -> District? {
        districts.first { $0.tasks.contains { $0.id == taskId } }
    }

    public static func load(from data: Data) throws -> VillageDef {
        try JSONDecoder().decode(VillageDef.self, from: data)
    }

    public static let bundled: VillageDef = {
        guard let url = Bundle.module.url(forResource: "village", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let def = try? load(from: data) else {
            fatalError("village.json не найден или поврежден")
        }
        return def
    }()
}

extension Game {
    // MARK: - Деревня

    /// Район открыт, когда все задачи предыдущего района выполнены.
    public func isDistrictOpen(_ district: District) -> Bool {
        guard let index = village.districts.firstIndex(of: district) else { return false }
        guard index > 0 else { return true }
        let previous = village.districts[index - 1]
        return previous.tasks.allSatisfy { state.completedTasks.contains($0.id) }
    }

    /// Первый закрытый район: над картой висит туман с его названием.
    public var nextLockedDistrict: District? {
        village.districts.first { !isDistrictOpen($0) }
    }

    /// До какой строки карты (в клетках, сверху) лежит туман над закрытыми районами.
    /// Чуть выше самой северной постройки открытых районов, чтобы крыши не прятались. nil - все открыто.
    public var fogRow: Double? {
        guard nextLockedDistrict != nil else { return nil }
        let open = village.districts.filter(isDistrictOpen).flatMap(\.tasks)
        guard let top = open.map(\.y).min() else { return nil }
        return max(0, Double(top) - 7)
    }

    public var currentDistrict: District? {
        village.districts.first { d in !d.tasks.allSatisfy { state.completedTasks.contains($0.id) } }
    }

    public var isVillageComplete: Bool { currentDistrict == nil }

    public func isAvailable(_ task: VillageTask) -> Bool {
        guard !state.completedTasks.contains(task.id),
              let district = village.district(of: task.id), isDistrictOpen(district) else { return false }
        return task.requires.allSatisfy { state.completedTasks.contains($0) }
    }

    /// Задачи, которые можно выполнить сейчас (хватает звезд или нет).
    public var availableTasks: [VillageTask] {
        village.allTasks.filter(isAvailable)
    }

    public enum TaskResult: Equatable {
        case done(VillageTask)
        case notEnoughStars(missing: Int)
        case locked
    }

    public func complete(taskId: String) -> TaskResult {
        guard let task = village.task(taskId), isAvailable(task) else { return .locked }
        guard state.stars >= task.cost else { return .notEnoughStars(missing: task.cost - state.stars) }
        state.stars -= task.cost
        state.completedTasks.append(task.id)
        advanceTutorial(from: .build)
        state.gems += task.gems ?? 0
        if let chain = task.unlocksChain, catalog.chain(chain) != nil, !state.unlockedChains.contains(chain) {
            state.unlockedChains.append(chain)
            state.bestTier[chain] = max(state.bestTier[chain] ?? 0, 1)
            state.pendingGenerators.append(chain)
            placePendingGenerators()
        }
        return .done(task)
    }

    /// Ставит генераторы новых цепочек в свободные клетки поближе к нижнему ряду.
    @discardableResult
    public func placePendingGenerators() -> [Int] {
        var placed: [Int] = []
        let bottomCenter = (balance.rows - 1) * balance.cols + balance.cols / 2
        while let chain = state.pendingGenerators.first, let cell = nearestEmpty(to: bottomCenter) {
            state.cells[cell] = .generator(GeneratorPiece(chain: chain, tier: 0))
            state.pendingGenerators.removeFirst()
            placed.append(cell)
        }
        placePendingChests()
        return placed
    }

    // MARK: - Уровни

    /// Начисляет опыт. Возвращает уровни, которые игрок получил (обычно ноль или один).
    @discardableResult
    func addXP(_ amount: Int) -> [Int] {
        state.xp += amount
        var gained: [Int] = []
        while state.xp >= balance.xpToNext(level: state.level) {
            state.xp -= balance.xpToNext(level: state.level)
            state.level += 1
            state.energy += balance.levelUpEnergy
            state.gems += balance.levelUpGems
            gained.append(state.level)
        }
        return gained
    }

    public var xpToNextLevel: Int { balance.xpToNext(level: state.level) }
}
