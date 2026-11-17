import XCTest
@testable import HearthCore

final class GreenhouseTests: XCTestCase {
    /// Понедельник недели, когда идет «Теплица».
    private func makeGame() -> (Game, TestClock) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let clock = TestClock()
        clock.date = cal.date(from: DateComponents(year: 2027, month: 1, day: 18, hour: 12))!
        let game = Game(seed: 6, now: { clock.date })
        game.state.level = 10
        while game.adventureSchedule(at: clock.date)?.kind != .greenhouse { clock.advance(7 * 86_400) }
        XCTAssertNotNil(game.adventure?.greenhouse)
        return (game, clock)
    }

    private func put(_ game: Game, _ bed: Int, _ item: Item, readyIn: TimeInterval) {
        game.state.adventure?.greenhouse?.beds[bed] = Plant(item: item, readyAt: game.now().addingTimeInterval(readyIn))
    }

    func testPointsMoreThanDoublePerTier() {
        for t in 1...Greenhouse.maxTier {
            XCTAssertGreaterThan(Greenhouse.tierPoints[t], Greenhouse.tierPoints[t - 1] * 2)
        }
    }

    func testPlantGrowsInRealTime() {
        let (game, clock) = makeGame()
        let moves = game.adventure!.moves
        guard case .planted(let bed, let item) = game.plantSeed() else { return XCTFail() }
        XCTAssertEqual(item.tier, 0)
        XCTAssertEqual(game.adventure!.moves, moves - 1)
        XCTAssertNil(game.harvest(bed), "еще не созрело")
        clock.advance(Greenhouse.growTime[0])
        let r = game.harvest(bed)
        XCTAssertEqual(r?.points, Greenhouse.tierPoints[0])
        XCTAssertNil(game.adventure!.greenhouse!.beds[bed])
    }

    func testMergeBeatsTwoHarvestsAndIsFaster() {
        let (game, clock) = makeGame()
        let seed = Item(chain: Greenhouse.chains[0], tier: 0)
        put(game, 0, seed, readyIn: 600)
        put(game, 1, seed, readyIn: 3000)
        XCTAssertTrue(game.canMergePlants(0, 1))
        XCTAssertTrue(game.movePlant(from: 0, to: 1))
        let p = game.adventure!.greenhouse!.beds[1]!
        XCTAssertEqual(p.item.tier, 1)
        XCTAssertNil(game.adventure!.greenhouse!.beds[0])
        // зреет от более спелого из двух плюс половина своего срока: меньше полного срока ступени
        XCTAssertLessThan(p.readyAt.timeIntervalSince(game.now()), Greenhouse.growTime[1])
        clock.advance(p.readyAt.timeIntervalSince(game.now()))
        XCTAssertGreaterThan(game.harvest(1)!.points, Greenhouse.tierPoints[0] * 2)
    }

    func testDifferentPlantsSwap() {
        let (game, _) = makeGame()
        let a = Item(chain: Greenhouse.chains[0], tier: 0), b = Item(chain: Greenhouse.chains[1], tier: 0)
        put(game, 0, a, readyIn: 100)
        put(game, 5, b, readyIn: 100)
        XCTAssertTrue(game.movePlant(from: 0, to: 5))
        XCTAssertEqual(game.adventure!.greenhouse!.beds[0]?.item, b)
        XCTAssertEqual(game.adventure!.greenhouse!.beds[5]?.item, a)
        XCTAssertFalse(game.movePlant(from: 3, to: 4), "с пустой грядки нечего переносить")
    }

    func testWateringOnceEveryFourHours() {
        let (game, clock) = makeGame()
        XCTAssertFalse(game.water(), "пустую теплицу не поливают")
        put(game, 0, Item(chain: Greenhouse.chains[2], tier: 2), readyIn: 7200)
        XCTAssertTrue(game.greenhouseNeedsAttention)
        XCTAssertTrue(game.water())
        XCTAssertEqual(game.adventure!.greenhouse!.beds[0]!.readyAt.timeIntervalSince(game.now()), 3600, accuracy: 1)
        XCTAssertFalse(game.water())
        clock.advance(Greenhouse.waterEvery)
        XCTAssertTrue(game.waterReady)
    }

    func testTopTierHarvestBringsChest() {
        let (game, _) = makeGame()
        put(game, 0, Item(chain: Greenhouse.chains[1], tier: Greenhouse.maxTier), readyIn: -1)
        let chests = game.state.pendingChests.count + game.state.cells.filter { if case .chest? = $0 { return true } else { return false } }.count
        let r = game.harvest(0)!
        XCTAssertTrue(r.prizes.contains(Greenhouse.goldenPrize))
        let after = game.state.pendingChests.count + game.state.cells.filter { if case .chest? = $0 { return true } else { return false } }.count
        XCTAssertGreaterThan(after, chests)
    }

    func testNoRoomAndNoSeeds() {
        let (game, _) = makeGame()
        game.state.adventure?.moves = 100
        for _ in 0..<GreenhouseState.size { _ = game.plantSeed() }
        XCTAssertEqual(game.plantSeed(), .noRoom)
        game.state.adventure?.greenhouse?.beds[3] = nil
        game.state.adventure?.moves = 0
        XCTAssertEqual(game.plantSeed(), .noMoves)
    }

    func testGreenhouseSurvivesSave() throws {
        let (game, clock) = makeGame()
        _ = game.plantSeed()
        let data = try JSONEncoder().encode(game.state)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        let restored = Game(state: decoded, seed: 1, now: { clock.date })
        XCTAssertEqual(restored.adventure?.greenhouse, game.adventure?.greenhouse)
    }

    /// Бот заходит несколько раз в день: дорожка проходится заметно, но не целиком, без перекоса в экономике.
    func testGreenhouseBalance() {
        for seed in UInt64(1)...2 {
            var config = SimConfig()
            config.seed = seed
            let r = Simulator.run(config)
            let gh = zip(r.adventureKinds, r.adventureProgress).filter { $0.0 == .greenhouse }.map(\.1)
            let avg = gh.reduce(0, +) / Double(max(1, gh.count))
            print("Теплица \(seed): событий \(gh.count), дорожка \(Int(avg * 100))%, урожаев \(r.greenhouseHarvests), поливов \(r.greenhouseWaterings), ценность \(Int(r.adventureValue)) из энергии \(r.energySpent), дней \(String(format: "%.1f", r.days))")
            XCTAssertGreaterThan(gh.count, 1)
            XCTAssertGreaterThan(avg, 0.4)
            XCTAssertLessThan(avg, 1.0)
            XCTAssertLessThan(Double(r.adventureValue), Double(r.energySpent) * 0.15)
        }
    }
}
