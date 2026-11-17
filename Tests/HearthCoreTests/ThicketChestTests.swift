import XCTest
@testable import HearthCore

final class ThicketChestTests: XCTestCase {
    private var clock: TestClock!

    override func setUp() {
        super.setUp()
        clock = TestClock()
    }

    private func makeGame(thickets: Bool = true, seed: UInt64 = 5) -> Game {
        var b = Balance()
        if !thickets { b.thicketOpen = 0; b.debrisRows = 0 }
        let clock = self.clock!
        return Game(balance: b, seed: seed, now: { clock.date })
    }

    private func emptyGame() -> Game {
        let game = makeGame(thickets: false)
        for i in 0..<game.balance.cellCount { game.testSet(i, nil) }
        return game
    }

    // MARK: - Заросли

    func testNewGameStartsWithOpenSquare() {
        let game = makeGame()
        let b = game.balance
        let open = game.state.cells.indices.filter { i in
            if case .thicket? = game.state.cells[i] { return false }
            return true
        }
        XCTAssertEqual(open.count, b.thicketOpen * b.thicketOpen)
        let left = (b.cols - b.thicketOpen) / 2
        for i in open {
            XCTAssertGreaterThanOrEqual(i / b.cols, b.rows - b.thicketOpen)
            XCTAssertTrue((left..<(left + b.thicketOpen)).contains(i % b.cols))
        }
        let gens = game.state.cells.compactMap { p -> String? in
            if case .generator(let g)? = p { return g.chain }
            return nil
        }
        XCTAssertEqual(Set(gens), Set(Game.startChains))
        XCTAssertEqual(game.state.thicketRows, Array(0..<b.rows))
        XCTAssertGreaterThan(game.state.cells.filter { $0 == nil }.count, 2, "есть куда класть первые предметы")
        // ступени у края низкие, чтобы первые заросли открывались сразу
        for t in game.revealedThickets { XCTAssertEqual(t.item.tier, 0) }
        XCTAssertFalse(game.revealedThickets.isEmpty)
        for case .thicket(let item)? in game.state.cells {
            XCTAssertTrue(Game.startChains.contains(item.chain))
            XCTAssertLessThanOrEqual(item.tier, 3)
        }
    }

    func testOnlyThicketsNextToOpenCellsAreRevealed() {
        let game = emptyGame()
        let cols = game.balance.cols
        let leaf = Piece.thicket(Item(chain: "garden", tier: 0))
        for i in 0..<(2 * cols) { game.testSet(i, leaf) }
        XCTAssertTrue(game.isRevealed(cols + 3), "рядом открытый ряд")
        XCTAssertFalse(game.isRevealed(3), "все соседи в зарослях")
        game.testSet(cols + 3, nil)
        XCTAssertTrue(game.isRevealed(3))
    }

    func testSameItemClearsRevealedThicket() {
        let game = emptyGame()
        let cols = game.balance.cols
        let carrot = Item(chain: "garden", tier: 1)
        for i in 0..<(2 * cols) { game.testSet(i, .thicket(Item(chain: "forest", tier: 0))) }
        game.testSet(cols + 2, .thicket(carrot))
        game.testSet(3 * cols, .item(carrot))
        let merges = game.state.mergesTotal
        XCTAssertEqual(game.move(from: 3 * cols, to: cols + 2), .unlocked(item: Item(chain: "garden", tier: 2)))
        XCTAssertEqual(game.piece(at: cols + 2), .item(Item(chain: "garden", tier: 2)))
        XCTAssertNil(game.piece(at: 3 * cols))
        XCTAssertEqual(game.state.mergesTotal, merges + 1)
        XCTAssertTrue(game.isRevealed(2), "над расчищенной клеткой видно")
    }

    func testWrongOrHiddenThicketDoesNotOpen() {
        let game = emptyGame()
        let cols = game.balance.cols
        let carrot = Item(chain: "garden", tier: 1)
        for i in 0..<(2 * cols) { game.testSet(i, .thicket(carrot)) }
        game.testSet(3 * cols, .item(Item(chain: "garden", tier: 0)))
        XCTAssertEqual(game.move(from: 3 * cols, to: cols), .invalid, "другой предмет")
        game.testSet(3 * cols, .item(carrot))
        XCTAssertEqual(game.move(from: 3 * cols, to: 0), .invalid, "заросль еще не видна")
        game.testSet(3 * cols + 1, .generator(GeneratorPiece(chain: "garden", tier: 0)))
        XCTAssertEqual(game.move(from: 3 * cols + 1, to: cols), .invalid, "генератор в заросли не кладется")
        XCTAssertEqual(game.thicketsLeft, 2 * cols)
    }

    func testClearedRowGivesChestOnce() {
        let game = emptyGame()
        let cols = game.balance.cols
        let seed = Item(chain: "garden", tier: 0)
        for c in 0..<cols { game.testSet(c, .thicket(seed)) }
        game.state.thicketRows = [0]
        for c in 0..<cols {
            game.testSet(cols + c, .item(seed))
            XCTAssertEqual(game.move(from: cols + c, to: c), .unlocked(item: Item(chain: "garden", tier: 1)))
        }
        XCTAssertTrue(game.state.thicketRows.isEmpty)
        let chests = game.state.cells.compactMap { p -> Chest? in
            if case .chest(let c)? = p { return c }
            return nil
        }
        XCTAssertEqual(chests.count, 1)
        XCTAssertEqual(game.lastChests.count, 1)
    }

    func testRowChestWaitsForSpace() {
        let game = emptyGame()
        let cols = game.balance.cols
        let seed = Item(chain: "garden", tier: 0)
        for i in 0..<game.balance.cellCount { game.testSet(i, .item(Item(chain: "quarry", tier: 5))) }
        game.testSet(0, .thicket(seed))
        game.testSet(cols, .item(seed))
        for c in 1..<cols { game.testSet(c, nil) }
        for c in 1..<cols { game.testSet(c, .item(Item(chain: "forest", tier: 5))) }
        game.state.thicketRows = [0]
        XCTAssertEqual(game.move(from: cols, to: 0), .unlocked(item: Item(chain: "garden", tier: 1)))
        // клетка, откуда взяли предмет, свободна: ящик встает туда
        XCTAssertEqual(game.state.pendingChests.count, 0)
        if case .chest? = game.piece(at: cols) {} else { XCTFail("ящик в освободившейся клетке") }
    }

    func testThicketsSurviveSave() throws {
        let game = makeGame()
        game.state.pendingChests = [Chest(kind: .gems, level: 2)]
        let data = try JSONEncoder().encode(game.state)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(decoded, game.state)
    }

    // MARK: - Ящики

    func testChestsMergeUpToTopLevel() {
        let game = emptyGame()
        for level in 0..<(Balance.chestLevels - 1) {
            game.testSet(0, .chest(Chest(kind: .coins, level: level)))
            game.testSet(1, .chest(Chest(kind: .coins, level: level)))
            XCTAssertEqual(game.move(from: 0, to: 1), .mergedChest(Chest(kind: .coins, level: level + 1)))
        }
        game.testSet(0, .chest(Chest(kind: .coins, level: Balance.chestLevels - 1)))
        XCTAssertEqual(game.move(from: 0, to: 1), .swapped, "самый большой ящик не растет")
        game.testSet(0, .chest(Chest(kind: .energy, level: 0)))
        game.testSet(1, .chest(Chest(kind: .coins, level: 0)))
        XCTAssertEqual(game.move(from: 0, to: 1), .swapped, "разные ящики не сливаются")
    }

    func testMergingChestsIsWorthWaiting() {
        for amounts in [Balance.chestCoins, Balance.chestEnergy, Balance.chestGems, Balance.chestItems] {
            XCTAssertEqual(amounts.count, Balance.chestLevels)
        }
        for amounts in [Balance.chestCoins, Balance.chestEnergy, Balance.chestGems] {
            for l in 1..<amounts.count {
                XCTAssertGreaterThan(amounts[l], amounts[l - 1] * 2, "слить выгоднее, чем открыть по одному")
                XCTAssertLessThanOrEqual(Double(amounts[l]), Double(amounts[l - 1]) * 2.6, "но без перекоса")
            }
        }
    }

    func testOpenResourceChests() {
        let game = emptyGame()
        let (coins, energy, gems) = (game.state.coins, game.state.energy, game.state.gems)
        game.testSet(0, .chest(Chest(kind: .coins, level: 1)))
        game.testSet(1, .chest(Chest(kind: .energy, level: 0)))
        game.testSet(2, .chest(Chest(kind: .gems, level: 3)))
        XCTAssertEqual(game.openChest(at: 0), .opened(ChestReward(coins: Balance.chestCoins[1])))
        XCTAssertEqual(game.openChest(at: 1), .opened(ChestReward(energy: Balance.chestEnergy[0])))
        XCTAssertEqual(game.openChest(at: 2), .opened(ChestReward(gems: Balance.chestGems[3])))
        XCTAssertEqual(game.state.coins, coins + Balance.chestCoins[1])
        XCTAssertEqual(game.state.energy, energy + Balance.chestEnergy[0])
        XCTAssertEqual(game.state.gems, gems + Balance.chestGems[3])
        XCTAssertNil(game.piece(at: 0))
        XCTAssertEqual(game.state.chestsOpened, 3)
        XCTAssertEqual(game.openChest(at: 0), .notChest)
    }

    func testItemChestNeedsSpace() {
        let game = emptyGame()
        let n = game.balance.cellCount
        for i in 0..<n { game.testSet(i, .item(Item(chain: "quarry", tier: 5))) }
        game.testSet(0, .chest(Chest(kind: .items, level: 2)))
        game.testSet(1, nil)
        XCTAssertEqual(game.openChest(at: 0), .needSpace(Balance.chestItems[2] - 2))
        if case .chest? = game.piece(at: 0) {} else { XCTFail("ящик остался") }
        for i in 2..<6 { game.testSet(i, nil) }
        guard case .opened(let r) = game.openChest(at: 0) else { return XCTFail() }
        XCTAssertEqual(r.items.count, Balance.chestItems[2])
        for spill in r.items {
            XCTAssertEqual(game.piece(at: spill.cell), .item(spill.item))
            XCTAssertTrue(Balance.chestItemTiers[2].contains(spill.item.tier))
            XCTAssertTrue(game.state.unlockedChains.contains(spill.item.chain))
        }
    }

    func testChestsDropRarelyFromMerges() {
        var dropped: [ChestKind: Int] = [:]
        let tries = 20_000
        let game = emptyGame()
        let item = Item(chain: "garden", tier: Balance.chestMinTier - 1)
        for _ in 0..<tries {
            for i in 0..<6 { game.testSet(i, nil) }
            game.testSet(0, .item(item))
            game.testSet(1, .item(item))
            _ = game.move(from: 0, to: 1)
            for cell in game.lastChests {
                if case .chest(let c)? = game.piece(at: cell) { dropped[c.kind, default: 0] += 1 }
            }
        }
        let total = dropped.values.reduce(0, +)
        let rate = Double(total) / Double(tries)
        XCTAssertEqual(rate, Balance.chestChance, accuracy: 0.006)
        XCTAssertGreaterThan(dropped[.items] ?? 0, dropped[.gems] ?? 0)
        XCTAssertGreaterThan(dropped[.coins] ?? 0, dropped[.gems] ?? 0)

        // ниже нужной ступени ящиков нет
        let low = emptyGame()
        let small = Item(chain: "garden", tier: 0)
        for _ in 0..<2_000 {
            low.testSet(0, .item(small))
            low.testSet(1, .item(small))
            _ = low.move(from: 0, to: 1)
            XCTAssertTrue(low.lastChests.isEmpty)
            low.testSet(1, nil)
        }
    }

    func testBotClearsThicketsAndChestsStayATreat() {
        for seed in UInt64(1)...3 {
            var config = SimConfig()
            config.seed = seed
            let r = Simulator.run(config)
            print("Бот \(seed): дней \(String(format: "%.1f", r.days)), заросли \(r.thicketsCleared) к дню \(r.thicketsDoneDay.map { String(format: "%.1f", $0) } ?? "-"), ящики \(r.chestsOpened): энергия \(r.energyFromChests), мон \(r.coinsFromChests), кр \(r.gemsFromChests), застреваний \(r.stalledSessions)")
            XCTAssertTrue(r.villageDone, "деревня отстроена")
            XCTAssertNotNil(r.thicketsDoneDay, "бот расчистил все заросли")
            XCTAssertLessThan(r.thicketsDoneDay ?? 99, 20, "заросли расчищаются за первые недели")
            XCTAssertGreaterThan(r.chestsOpened, 10)
            XCTAssertLessThanOrEqual(Double(r.energyFromChests), Double(r.energySpent) * 0.05, "энергия из ящиков - приятная мелочь")
            XCTAssertLessThan(r.gemsFromChests, 150)
        }
    }
}
