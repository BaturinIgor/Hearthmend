import XCTest
@testable import HearthCore

/// Живое поле, очаг и починка (1.2).
final class BoardLifeTests: XCTestCase {
    var clock: TestClock!

    override func setUp() {
        super.setUp()
        clock = TestClock()
    }

    /// Пустое поле без зарослей, обучение пройдено.
    private func emptyGame(seed: UInt64 = 42) -> Game {
        var b = Balance()
        b.debrisRows = 0
        b.thicketOpen = 0
        let clock = self.clock!
        let game = Game(balance: b, seed: seed, now: { clock.date })
        for i in 0..<b.cellCount { game.testSet(i, nil) }
        game.skipTutorial()
        game.state.hearthGiven = true
        game.tickBoard()
        return game
    }

    private func empties(_ g: Game) -> Int { g.state.cells.filter { $0 == nil }.count }

    // MARK: - Живое поле

    func testPairGrowsItemsOverTime() {
        let g = emptyGame()
        g.testSet(10, .item(Item(chain: "garden", tier: 1)))
        g.testSet(11, .item(Item(chain: "forest", tier: 1)))
        XCTAssertEqual(g.lifeProducers.map(\.index), [10])
        clock.advance(Balance.lifeInterval - 1)
        XCTAssertTrue(g.tickBoard().isEmpty, "раньше срока ничего не растет")
        clock.advance(1)
        let events = g.tickBoard()
        XCTAssertEqual(events.count, 1)
        guard case .grew(let from, let to, let item)? = events.first else { return XCTFail() }
        XCTAssertEqual(from, 10)
        XCTAssertEqual(item, Item(chain: "garden", tier: 0))
        XCTAssertTrue(g.neighbors(of: 10).contains(to), "кладет рядом с парой")
        XCTAssertEqual(g.piece(at: to), .item(item))
    }

    func testEachPairWorksOncePerInterval() {
        let g = emptyGame()
        for i in [10, 12, 24, 26] { g.testSet(i, .item(Item(chain: "garden", tier: 1))) }
        for i in [11, 25] { g.testSet(i, .item(Item(chain: "forest", tier: 1))) }
        XCTAssertEqual(g.lifeProducers.count, 1, "много одинаковых пар - один источник")
        g.testSet(40, .item(Item(chain: "quarry", tier: 1)))
        g.testSet(41, .item(Item(chain: "forest", tier: 1)))
        XCTAssertEqual(g.lifeProducers.count, 2, "другая пара работает отдельно")
        clock.advance(Balance.lifeInterval)
        XCTAssertEqual(g.tickBoard().count, 2)
    }

    func testLonePieceOrLowTierDoesNotGrow() {
        let g = emptyGame()
        g.testSet(10, .item(Item(chain: "garden", tier: 0)))
        g.testSet(11, .item(Item(chain: "forest", tier: 1)))
        g.testSet(30, .item(Item(chain: "garden", tier: 3)))
        XCTAssertTrue(g.lifeProducers.isEmpty)
        clock.advance(Balance.lifeInterval * 5)
        XCTAssertTrue(g.tickBoard().isEmpty)
    }

    func testOfflineBatchIsCappedAndLeavesFreeCells() {
        let g = emptyGame()
        g.testSet(10, .item(Item(chain: "garden", tier: 1)))
        g.testSet(11, .item(Item(chain: "forest", tier: 1)))
        clock.advance(Balance.lifeInterval * 50)
        XCTAssertEqual(g.tickBoard().count, Balance.lifeMaxBatch, "за долгий перерыв не больше lifeMaxBatch")

        // почти полное поле: живое поле не занимает последние клетки
        let full = emptyGame()
        for i in full.state.cells.indices { full.testSet(i, .generator(GeneratorPiece(chain: "quarry", tier: 0))) }
        full.testSet(10, .item(Item(chain: "garden", tier: 1)))
        full.testSet(11, .item(Item(chain: "forest", tier: 1)))
        for i in [0, 1, 2, 3, 4, 5, 6] { full.testSet(i, nil) }
        clock.advance(Balance.lifeInterval * 4)
        full.tickBoard()
        XCTAssertEqual(empties(full), Balance.lifeKeepFree)
    }

    func testClockBackwardsDoesNotGrow() {
        let g = emptyGame()
        g.testSet(10, .item(Item(chain: "garden", tier: 1)))
        g.testSet(11, .item(Item(chain: "forest", tier: 1)))
        clock.advance(-3600 * 5)
        XCTAssertTrue(g.tickBoard().isEmpty)
        clock.advance(Balance.lifeInterval)
        XCTAssertEqual(g.tickBoard().count, 1)
    }

    func testEveryPairUsesRealChains() {
        let ids = Set(Catalog.bundled.chains.map(\.id))
        for p in Balance.lifePairs {
            XCTAssertTrue(ids.contains(p.chain), p.chain)
            XCTAssertTrue(ids.contains(p.partner), p.partner)
        }
        XCTAssertTrue(Balance.lifePairs.contains { Game.startChains.contains($0.chain) && Game.startChains.contains($0.partner) },
                      "хотя бы одна пара работает с самого начала")
    }

    // MARK: - Очаг

    func testHearthAppearsAtLevelAndOnlyOnce() {
        let g = emptyGame()
        g.state.hearthGiven = false
        g.testSetLevel(Balance.hearthLevel - 1)
        g.tickBoard()
        XCTAssertNil(g.hearthIndex)
        g.testSetLevel(Balance.hearthLevel)
        g.tickBoard()
        let at = try! XCTUnwrap(g.hearthIndex)
        XCTAssertEqual(g.hearth?.fuel, Balance.hearthStartFuel)
        g.testSet(at, nil)
        g.tickBoard()
        XCTAssertNil(g.hearthIndex, "убранный очаг второй раз не выдается")
    }

    func testHearthRipensNeighborsAndBurnsFuel() {
        let g = emptyGame()
        g.testSet(24, .hearth(Hearth(fuel: 3600)))
        g.tickBoard()
        g.testSet(25, .item(Item(chain: "garden", tier: 0)))
        g.testSet(23, .item(Item(chain: "garden", tier: 1)))
        g.testSet(26, .item(Item(chain: "garden", tier: 0)))  // не сосед: не греется
        XCTAssertEqual(g.ripeness(at: 25), 0)
        XCTAssertNil(g.ripeness(at: 26))
        clock.advance(Balance.hearthRipenBase)
        let events = g.tickBoard()
        XCTAssertTrue(events.contains(.ripened(index: 25, item: Item(chain: "garden", tier: 1))))
        XCTAssertEqual(g.piece(at: 26), .item(Item(chain: "garden", tier: 0)))
        XCTAssertEqual(g.ripeness(at: 23) ?? 0, 0.5, accuracy: 0.01, "вторая ступень зреет вдвое дольше")
        XCTAssertEqual(g.hearth?.fuel ?? 0, 3600 - Balance.hearthRipenBase, accuracy: 0.1)
    }

    func testHearthGoesOutAndStopsWarming() {
        let g = emptyGame()
        g.testSet(24, .hearth(Hearth(fuel: 60)))
        g.tickBoard()
        g.testSet(25, .item(Item(chain: "garden", tier: 0)))
        clock.advance(Balance.hearthRipenBase * 4)
        let events = g.tickBoard()
        XCTAssertTrue(events.contains(.hearthOut(index: 24)))
        XCTAssertEqual(g.piece(at: 25), .item(Item(chain: "garden", tier: 0)), "минуты огня не хватило")
        XCTAssertTrue(g.warmCells.isEmpty)
    }

    func testMovingItemAwayLosesWarmth() {
        let g = emptyGame()
        g.testSet(24, .hearth(Hearth(fuel: 3600)))
        g.tickBoard()
        g.testSet(25, .item(Item(chain: "garden", tier: 0)))
        clock.advance(Balance.hearthRipenBase / 2)
        g.tickBoard()
        XCTAssertEqual(g.move(from: 25, to: 40), .moved)
        g.tickBoard()
        XCTAssertEqual(g.move(from: 40, to: 25), .moved)
        clock.advance(Balance.hearthRipenBase / 2 + 1)
        g.tickBoard()
        XCTAssertEqual(g.piece(at: 25), .item(Item(chain: "garden", tier: 0)), "тепло пропало, когда предмет унесли")
    }

    func testTopTiersDoNotRipen() {
        let g = emptyGame()
        g.testSet(24, .hearth(Hearth(fuel: Balance.hearthFuelMax)))
        g.tickBoard()
        g.testSet(25, .item(Item(chain: "garden", tier: Balance.hearthMaxTier)))
        clock.advance(Balance.hearthFuelMax)
        g.tickBoard()
        XCTAssertEqual(g.piece(at: 25), .item(Item(chain: "garden", tier: Balance.hearthMaxTier)))
    }

    func testFuelingHearth() {
        let g = emptyGame()
        g.testSet(24, .hearth(Hearth(fuel: 0)))
        g.testSet(30, .item(Item(chain: "forest", tier: 1)))
        g.testSet(31, .item(Item(chain: "garden", tier: 1)))
        XCTAssertEqual(g.move(from: 30, to: 24), .fueled(Hearth(fuel: Balance.hearthFuelBase * 2)))
        XCTAssertNil(g.piece(at: 30), "ветка сгорела")
        XCTAssertEqual(g.move(from: 31, to: 24), .swapped, "огородом не топят: просто меняются местами")
        let at = try! XCTUnwrap(g.hearthIndex)
        g.testSet(at, .hearth(Hearth(fuel: Balance.hearthFuelMax)))
        g.testSet(30, .item(Item(chain: "forest", tier: 0)))
        XCTAssertEqual(g.move(from: 30, to: at), .invalid, "полный очаг не берет")
        XCTAssertNotNil(g.piece(at: 30))
    }

    func testFuelIsCappedAndBurnsOldFirst() {
        let g = emptyGame()
        g.testSet(24, .hearth(Hearth(fuel: 600)))
        g.tickBoard()
        clock.advance(1000)
        g.testSet(30, .item(Item(chain: "forest", tier: 0)))
        guard case .fueled(let h) = g.move(from: 30, to: 24) else { return XCTFail() }
        XCTAssertEqual(h.fuel, Balance.hearthFuelBase, accuracy: 0.1, "прошлое топливо догорело до броска")
        g.testSet(30, .item(Item(chain: "forest", tier: 9)))
        guard case .fueled(let big) = g.move(from: 30, to: 24) else { return XCTFail() }
        XCTAssertEqual(big.fuel, Balance.hearthFuelMax)
    }

    // MARK: - Починка

    func testMendingTurnsBrokenIntoItem() {
        let g = emptyGame()
        let broken = Item(chain: "garden", tier: 4)
        g.testSet(10, .broken(broken))
        XCTAssertEqual(g.mendTool(for: broken), Item(chain: "forest", tier: 2))
        g.testSet(11, .item(Item(chain: "forest", tier: 1)))
        XCTAssertEqual(g.move(from: 11, to: 10), .swapped, "слишком простой предмет не чинит")
        g.testSet(12, .item(Item(chain: "forest", tier: 3)))
        XCTAssertEqual(g.move(from: 12, to: 11), .mended(item: broken))
        XCTAssertEqual(g.piece(at: 11), .item(broken))
        XCTAssertNil(g.piece(at: 12))
        XCTAssertGreaterThanOrEqual(g.state.bestTier["garden"] ?? 0, 4)
    }

    func testBrokenCannotMergeOrBeStoredAndSellsCheap() {
        let g = emptyGame()
        let broken = Item(chain: "orchard", tier: 3)
        XCTAssertEqual(g.mendChain(for: "orchard"), "quarry")
        g.testSet(10, .broken(broken))
        g.testSet(11, .broken(broken))
        XCTAssertEqual(g.move(from: 11, to: 10), .swapped, "две сломанные не сливаются")
        XCTAssertFalse(g.store(at: 10))
        let coins = g.state.coins
        XCTAssertEqual(g.sell(at: 10), 2)
        XCTAssertEqual(g.state.coins, coins + 2)
        XCTAssertNil(g.undoSale(), "продажу сломанной не отменить")
    }

    func testGeneratorsSometimesGiveBrokenAfterLevel() {
        let g = emptyGame(seed: 7)
        g.testSet(0, .generator(GeneratorPiece(chain: "garden", tier: 0)))
        g.testSetLevel(Balance.brokenLevel - 1)
        func spawnMany() -> Int {
            var broken = 0
            for _ in 0..<400 {
                g.testSetEnergy(10)
                guard case .spawned(let cell, _) = g.spawn(from: 0) else { continue }
                if case .broken? = g.piece(at: cell) { broken += 1 }
                g.testSet(cell, nil)
            }
            return broken
        }
        XCTAssertEqual(spawnMany(), 0, "до уровня сломанных нет")
        g.testSetLevel(Balance.brokenLevel)
        let n = spawnMany()
        XCTAssertGreaterThan(n, 4)
        XCTAssertLessThan(n, 40)
    }

    // MARK: - Сохранение и баланс

    func testNewStateRoundTrips() throws {
        let g = emptyGame()
        g.testSet(24, .hearth(Hearth(fuel: 3600)))
        g.testSet(10, .broken(Item(chain: "farm", tier: 3)))
        g.testSet(25, .item(Item(chain: "garden", tier: 0)))
        g.tickBoard()
        clock.advance(60)
        g.tickBoard()
        let data = try JSONEncoder().encode(g.state)
        let back = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(back, g.state)
        XCTAssertNotNil(back.warmth[25])
    }

    func testOldSaveWithoutNewFieldsLoads() throws {
        let g = emptyGame()
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(g.state)) as! [String: Any]
        for k in ["lifeUpdatedAt", "hearthUpdatedAt", "warmth", "hearthGiven"] { json[k] = nil }
        let back = try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(back.hearthGiven)
        XCTAssertTrue(back.warmth.isEmpty)
    }

    /// Бот пользуется всеми тремя механиками и не застревает.
    func testBotUsesMechanics() {
        let r = SimRuns.standard(1)
        XCTAssertGreaterThan(r.lifeSpawned, 200)
        XCTAssertGreaterThan(r.ripened, 30)
        XCTAssertGreaterThan(r.brokenMended, 50)
        XCTAssertGreaterThan(r.hearthFueled, 50)
        XCTAssertEqual(r.stalledSessions, 0)
    }
}
