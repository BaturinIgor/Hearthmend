import XCTest
@testable import HearthCore

final class VillageTests: XCTestCase {
    private var clock: TestClock!

    override func setUp() {
        super.setUp()
        clock = TestClock()
    }

    private func makeGame(debris: Bool = false) -> Game {
        var b = Balance()
        if !debris { b.debrisRows = 0 }
        let clock = self.clock!
        return Game(balance: b, seed: 7, now: { clock.date })
    }

    // MARK: - Данные

    func testVillageDataIsConsistent() {
        let village = VillageDef.bundled
        let ids = village.allTasks.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "id задач уникальны")
        for district in village.districts {
            let local = Set(district.tasks.map(\.id))
            for task in district.tasks {
                XCTAssertGreaterThan(task.cost, 0)
                for req in task.requires {
                    XCTAssertTrue(local.contains(req), "\(task.id) требует \(req) из своего района")
                }
                if let chain = task.unlocksChain {
                    XCTAssertNotNil(Catalog.bundled.chain(chain), "цепочка \(chain) есть в каталоге")
                    XCTAssertFalse(Game.startChains.contains(chain))
                }
            }
        }
        // каждая цепочка вне стартовых открывается ровно одной задачей
        let unlocks = village.allTasks.compactMap(\.unlocksChain)
        let extra = Catalog.bundled.chains.map(\.id).filter { !Game.startChains.contains($0) }
        XCTAssertEqual(unlocks.sorted(), extra.sorted())
    }

    func testEveryTaskIsReachable() {
        let game = makeGame()
        game.testSetStars(100_000)
        var guardCount = 0
        while let task = game.availableTasks.first, guardCount < 1000 {
            XCTAssertEqual(game.complete(taskId: task.id), .done(task))
            guardCount += 1
        }
        XCTAssertTrue(game.isVillageComplete, "все задачи достижимы, циклов в requires нет")
        XCTAssertEqual(game.state.completedTasks.count, game.village.allTasks.count)
    }

    // MARK: - Задачи

    func testFirstTaskAvailableOthersLocked() {
        let game = makeGame()
        XCTAssertEqual(game.availableTasks.map(\.id), ["square_clear"])
        XCTAssertEqual(game.complete(taskId: "square_well"), .locked)
        XCTAssertEqual(game.complete(taskId: "farm_fence"), .locked, "следующий район закрыт")
    }

    func testCompleteSpendsStars() {
        let game = makeGame()
        let cost = game.village.task("square_clear")!.cost
        game.testSetStars(cost - 1)
        XCTAssertEqual(game.complete(taskId: "square_clear"), .notEnoughStars(missing: 1))
        game.testSetStars(cost + 3)
        guard case .done = game.complete(taskId: "square_clear") else { return XCTFail() }
        XCTAssertEqual(game.state.stars, 3)
        XCTAssertEqual(game.complete(taskId: "square_clear"), .locked, "второй раз нельзя")
        XCTAssertEqual(Set(game.availableTasks.map(\.id)), ["square_well", "square_lamps"])
    }

    func testTaskGivesGems() {
        let game = makeGame()
        game.testSetStars(1000)
        for id in ["square_clear", "square_well"] { _ = game.complete(taskId: id) }
        let gems = game.state.gems
        _ = game.complete(taskId: "square_home")
        XCTAssertEqual(game.state.gems, gems + 5)
    }

    func testResidentUnlocksChainAndPlacesGenerator() {
        let game = makeGame()
        game.testSetStars(1000)
        for id in ["square_clear", "square_well", "square_home", "square_beekeeper"] {
            guard case .done = game.complete(taskId: id) else { return XCTFail(id) }
        }
        XCTAssertTrue(game.state.unlockedChains.contains("apiary"))
        XCTAssertEqual(game.state.bestTier["apiary"], 1)
        XCTAssertTrue(game.state.cells.contains(.generator(GeneratorPiece(chain: "apiary", tier: 0))))
        XCTAssertTrue(game.state.pendingGenerators.isEmpty)
    }

    func testGeneratorWaitsForFreeCell() {
        let game = makeGame()
        game.testSetStars(1000)
        for i in 0..<game.balance.cellCount { game.testSet(i, .item(Item(chain: "quarry", tier: 6))) }
        game.testSet(0, .item(Item(chain: "garden", tier: 0)))
        for id in ["square_clear", "square_well", "square_home", "square_beekeeper"] {
            _ = game.complete(taskId: id)
        }
        XCTAssertEqual(game.state.pendingGenerators, ["apiary"], "места нет, генератор ждет")
        _ = game.sell(at: 0)
        XCTAssertEqual(game.state.cells[0], .generator(GeneratorPiece(chain: "apiary", tier: 0)))
        XCTAssertTrue(game.state.pendingGenerators.isEmpty)
    }

    func testNextDistrictOpensAfterPrevious() {
        let game = makeGame()
        game.testSetStars(1000)
        for task in game.village.districts[0].tasks {
            XCTAssertNil(game.availableTasks.first { $0.id.hasPrefix("farm") })
            _ = game.complete(taskId: task.id)
        }
        XCTAssertEqual(game.currentDistrict?.id, "farmstead")
        XCTAssertEqual(game.availableTasks.map(\.id), ["farm_fence"])
    }

    // MARK: - Уровни

    func testLevelUpGivesEnergyAndGems() {
        let game = makeGame()
        game.testSetEnergy(10)
        game.testSetGems(0)
        game.testSetXP(game.xpToNextLevel - 1)
        let item = Item(chain: "garden", tier: 1)
        game.testSet(0, .item(item))
        game.testSetOrders([Order(id: 999, needs: [item], coins: 6, stars: 1, xp: 2)])
        XCTAssertNotNil(game.deliver(orderId: 999))
        XCTAssertEqual(game.lastLevelUps, [2])
        XCTAssertEqual(game.state.level, 2)
        XCTAssertEqual(game.state.xp, 1)
        XCTAssertEqual(game.state.energy, 10 + game.balance.levelUpEnergy)
        XCTAssertEqual(game.state.gems, game.balance.levelUpGems)
    }

    func testXPCurveGrows() {
        let b = Balance()
        for level in 1..<30 {
            XCTAssertLessThan(b.xpToNext(level: level), b.xpToNext(level: level + 1))
        }
    }

    // MARK: - Сохранения

    func testOldSaveWithoutVillageFieldsLoads() throws {
        let game = makeGame()
        let data = try JSONEncoder().encode(game.state)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "completedTasks")
        json.removeValue(forKey: "level")
        json.removeValue(forKey: "pendingGenerators")
        let old = try JSONSerialization.data(withJSONObject: json)
        let state = try JSONDecoder().decode(GameState.self, from: old)
        XCTAssertEqual(state.level, 1)
        XCTAssertEqual(state.completedTasks, [])
        XCTAssertEqual(state.pendingGenerators, [])
        XCTAssertEqual(state.cells, game.state.cells)
    }

    func testVillageProgressSurvivesSave() throws {
        let game = makeGame()
        game.testSetStars(game.village.task("square_clear")!.cost + 8)
        _ = game.complete(taskId: "square_clear")
        let data = try JSONEncoder().encode(game.state)
        let loaded = try JSONDecoder().decode(GameState.self, from: data)
        let clock = self.clock!
        let again = Game(state: loaded, balance: game.balance, seed: 1, now: { clock.date })
        XCTAssertEqual(again.state.completedTasks, ["square_clear"])
        XCTAssertEqual(again.state.stars, 8)
    }
}
