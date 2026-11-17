import Foundation

/// Раскладка деревни: переезд старых сохранений на большую карту, перестановка построек игроком
/// и сцены истории (что говорят жители, когда открывается и отстраивается район).
extension Game {
    /// Текущая версия карты, см. GameState.mapRev.
    public static let mapRevision = 1
    /// На сколько клеток сдвинулась карта вниз в версии 1.
    static let mapShiftV1 = 40.0

    func migrateVillage() {
        if state.mapRev < 1 {
            for i in state.placedDecor.indices { state.placedDecor[i].y += Self.mapShiftV1 }
            for (id, spot) in state.buildingSpots where spot.count == 2 {
                state.buildingSpots[id] = [spot[0], spot[1] + Self.mapShiftV1]
            }
            // старые игроки уже видели эти районы: сцены только для нового
            for district in village.districts where isDistrictOpen(district) {
                markStorySeen("\(district.id).intro")
                if district.tasks.allSatisfy({ state.completedTasks.contains($0.id) }) { markStorySeen("\(district.id).done") }
            }
            state.mapRev = 1
        }
        // цепочки, которые теперь открывают уже построенные здания (рыбалка у домика рыбака)
        for task in village.allTasks where state.completedTasks.contains(task.id) {
            if let chain = task.unlocksChain, catalog.chain(chain) != nil, !state.unlockedChains.contains(chain) {
                state.unlockedChains.append(chain)
                state.bestTier[chain] = max(state.bestTier[chain] ?? 0, 1)
                state.pendingGenerators.append(chain)
            }
        }
        placePendingGenerators()
    }

    // MARK: - Перестановка построек

    /// Где стоит постройка: на своем месте из village.json или там, куда ее передвинул игрок.
    public func spot(of task: VillageTask) -> (x: Double, y: Double) {
        if let s = state.buildingSpots[task.id], s.count == 2 { return (s[0], s[1]) }
        return (task.x, Double(task.y))
    }

    /// Двигать можно только готовые постройки, в пределах карты.
    @discardableResult
    public func moveBuilding(_ id: String, x: Double, y: Double) -> Bool {
        guard let task = village.task(id), state.completedTasks.contains(task.id) else { return false }
        state.buildingSpots[id] = [clampX(x), min(max(y, 2), Self.mapSize.height)]
        return true
    }

    /// Вернуть постройку на исходное место.
    public func resetBuilding(_ id: String) {
        state.buildingSpots[id] = nil
    }

    // MARK: - История

    /// Сцена, которую пора показать: открылся район (его вступление) или он отстроен (финал).
    /// Ключи строк: story.<район>.intro и story.<район>.done, реплики - .1, .2 и так далее.
    public var pendingStory: String? {
        for district in village.districts {
            let intro = "\(district.id).intro"
            let done = "\(district.id).done"
            let open = isDistrictOpen(district)
            let finished = district.tasks.allSatisfy { state.completedTasks.contains($0.id) }
            if open, !state.storySeen.contains(intro) { return intro }
            if finished, !state.storySeen.contains(done) { return done }
        }
        return nil
    }

    public func markStorySeen(_ id: String) {
        if !state.storySeen.contains(id) { state.storySeen.append(id) }
    }
}
