import XCTest
@testable import HearthCore

/// Большая карта, новые районы и цепочки, перестановка построек и история деревни.
final class VillageLayoutTests: XCTestCase {
    private func game(_ state: GameState? = nil) -> Game { Game(state: state, seed: 3) }

    func testSevenDistrictsAndNewChains() {
        let g = game()
        XCTAssertEqual(g.village.districts.map(\.id), ["square", "farmstead", "riverside", "orchard", "hilltop", "mine", "fair"])
        XCTAssertNotNil(g.catalog.chain("fishing"))
        XCTAssertNotNil(g.catalog.chain("crystal"))
        XCTAssertEqual(g.catalog.maxTier(of: "fishing"), 7)
        XCTAssertEqual(g.catalog.maxTier(of: "crystal"), 7)
        XCTAssertEqual(g.village.task("river_fisher")?.unlocksChain, "fishing")
        XCTAssertEqual(g.village.task("mine_camp")?.unlocksChain, "crystal")
    }

    func testAllBuildingsInsideMap() {
        for task in VillageDef.bundled.allTasks {
            XCTAssertGreaterThan(task.x, 0, task.id)
            XCTAssertLessThan(task.x, Game.mapSize.width, task.id)
            XCTAssertGreaterThan(Double(task.y), 0, task.id)
            XCTAssertLessThanOrEqual(Double(task.y), Game.mapSize.height, task.id)
        }
    }

    func testNewGameIsOnCurrentMap() {
        let g = game()
        XCTAssertEqual(g.state.mapRev, Game.mapRevision)
    }

    /// Старое сохранение: украшения сдвигаются вместе с картой, домик рыбака открывает рыбалку,
    /// сцены уже пройденных районов не показываются.
    func testOldSaveMigrates() throws {
        let old = game()
        for task in old.village.districts.prefix(3).flatMap(\.tasks) {
            old.state.stars += task.cost
            _ = old.complete(taskId: task.id)
        }
        old.state.placedDecor = [PlacedDecor(id: 1, key: "decor_bush", x: 10, y: 70)]
        old.state.unlockedChains.removeAll { $0 == "fishing" }
        old.state.cells = old.state.cells.map { piece in
            if case .generator(let g)? = piece, g.chain == "fishing" { return nil }
            return piece
        }
        // как выглядело сохранение до версии 1.1: без новых полей
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old.state)) as! [String: Any]
        for key in ["mapRev", "buildingSpots", "storySeen"] { json.removeValue(forKey: key) }
        let data = try JSONSerialization.data(withJSONObject: json)
        let state = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(state.mapRev, 0)

        let g = game(state)
        XCTAssertEqual(g.state.mapRev, Game.mapRevision)
        XCTAssertEqual(g.state.placedDecor.first?.y, 110)
        XCTAssertTrue(g.state.unlockedChains.contains("fishing"))
        XCTAssertTrue(g.state.cells.contains { if case .generator(let x)? = $0 { return x.chain == "fishing" }; return false },
                      "генератор рыбалки на поле")
        // сцены трех пройденных районов и вступление открытого сада уже «видены»
        XCTAssertNil(g.pendingStory)
        // мигрирует один раз
        let again = game(g.state)
        XCTAssertEqual(again.state.placedDecor.first?.y, 110)
    }

    func testStoryGoesDistrictByDistrict() {
        let g = game()
        XCTAssertEqual(g.pendingStory, "square.intro")
        g.markStorySeen("square.intro")
        XCTAssertNil(g.pendingStory)
        for task in g.village.districts[0].tasks {
            g.state.stars += task.cost
            _ = g.complete(taskId: task.id)
        }
        XCTAssertEqual(g.pendingStory, "square.done")
        g.markStorySeen("square.done")
        XCTAssertEqual(g.pendingStory, "farmstead.intro")
    }

    func testOnlyBuiltBuildingsMoveAndStayOnMap() {
        let g = game()
        let task = g.village.allTasks[0]
        XCTAssertFalse(g.moveBuilding(task.id, x: 5, y: 50), "недостроенную не двигаем")
        g.state.stars += task.cost
        _ = g.complete(taskId: task.id)
        XCTAssertTrue(g.moveBuilding(task.id, x: 5, y: 50))
        XCTAssertEqual(g.spot(of: task).x, 5)
        XCTAssertEqual(g.spot(of: task).y, 50)
        g.moveBuilding(task.id, x: -10, y: 999)
        XCTAssertGreaterThan(g.spot(of: task).x, 0)
        XCTAssertLessThanOrEqual(g.spot(of: task).y, Game.mapSize.height)
        g.resetBuilding(task.id)
        XCTAssertEqual(g.spot(of: task).x, task.x)
    }

    /// Новые цепочки попадают в заказы, когда открыты.
    func testOrdersUseNewChains() {
        let g = game()
        g.state.unlockedChains = ["fishing", "crystal"]
        g.state.bestTier = ["fishing": 3, "crystal": 3]
        g.state.orders = []
        g.refillOrders()
        XCTAssertFalse(g.state.orders.isEmpty)
        XCTAssertTrue(g.state.orders.allSatisfy { $0.needs.allSatisfy { ["fishing", "crystal"].contains($0.chain) } })
    }
}
