import XCTest
@testable import HearthCore

/// Часы, которые тест двигает вручную.
final class TestClock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}

final class GameTests: XCTestCase {
    var clock: TestClock!

    override func setUp() {
        super.setUp()
        clock = TestClock()
    }

    private func makeGame(balance: Balance = Balance(), seed: UInt64 = 42) -> Game {
        let clock = self.clock!
        return Game(catalog: .bundled, balance: balance, seed: seed, now: { clock.date })
    }

    /// Пустое поле без завалов: тест сам раскладывает предметы.
    private func emptyGame(balance: Balance = Balance(), seed: UInt64 = 42) -> Game {
        var b = balance
        b.debrisRows = 0
        b.thicketOpen = 0
        let game = makeGame(balance: b, seed: seed)
        for i in 0..<b.cellCount { game.testSet(i, nil) }
        return game
    }

    private let carrot = Item(chain: "garden", tier: 2)

    // MARK: - Каталог

    func testCatalogLoadsAllChains() {
        let catalog = Catalog.bundled
        XCTAssertEqual(catalog.chains.map(\.id), ["garden", "forest", "quarry", "apiary", "farm", "orchard", "fishing", "crystal"])
        for chain in catalog.chains {
            XCTAssertEqual(chain.items.count, chain.emoji.count, "у \(chain.id) эмодзи на каждую ступень")
            XCTAssertGreaterThanOrEqual(chain.items.count, 6, "\(chain.id): цепочка хотя бы из 6 ступеней")
            XCTAssertEqual(Set(chain.items).count, chain.items.count, "\(chain.id): ключи без повторов")
        }
        let keys = catalog.chains.flatMap(\.items)
        XCTAssertEqual(Set(keys).count, keys.count, "ключи предметов уникальны во всем каталоге")
    }

    func testNextStopsAtMaxTier() {
        let catalog = Catalog.bundled
        let max = catalog.maxTier(of: "garden")
        XCTAssertEqual(catalog.next(Item(chain: "garden", tier: 0)), Item(chain: "garden", tier: 1))
        XCTAssertNil(catalog.next(Item(chain: "garden", tier: max)))
    }

    // MARK: - Стартовое поле

    func testNewGameLayout() {
        var classic = Balance()
        classic.thicketOpen = 0
        let game = makeGame(balance: classic)
        let b = game.balance
        XCTAssertEqual(game.state.cells.count, b.cellCount)
        XCTAssertEqual(game.state.energy, b.energyMax)
        XCTAssertEqual(game.state.gems, b.startGems)
        XCTAssertEqual(game.state.unlockedChains, Game.startChains)
        let generators = game.state.cells.compactMap { piece -> String? in
            if case .generator(let g)? = piece { return g.chain }
            return nil
        }
        XCTAssertEqual(Set(generators), Set(Game.startChains))
        let debris = game.state.cells.filter { if case .debris? = $0 { return true }; return false }
        XCTAssertEqual(debris.count, b.debrisRows * b.cols)
        XCTAssertEqual(game.state.orders.count, b.orderSlots)
    }

    // MARK: - Слияние

    func testMergeEqualItems() {
        let game = emptyGame()
        game.testSet(0, .item(Item(chain: "garden", tier: 1)))
        game.testSet(1, .item(Item(chain: "garden", tier: 1)))
        let result = game.move(from: 0, to: 1)
        XCTAssertEqual(result, .merged(item: carrot, cleared: [], bubble: nil))
        XCTAssertNil(game.piece(at: 0))
        XCTAssertEqual(game.piece(at: 1), .item(carrot))
        XCTAssertEqual(game.state.mergesTotal, 1)
        XCTAssertEqual(game.state.bestTier["garden"], 2)
    }

    func testDifferentItemsSwap() {
        let game = emptyGame()
        let a = Item(chain: "garden", tier: 0), b = Item(chain: "forest", tier: 0)
        game.testSet(0, .item(a))
        game.testSet(1, .item(b))
        XCTAssertEqual(game.move(from: 0, to: 1), .swapped)
        XCTAssertEqual(game.piece(at: 0), .item(b))
        XCTAssertEqual(game.piece(at: 1), .item(a))
    }

    func testMaxTierItemsDoNotMerge() {
        let game = emptyGame()
        let top = Item(chain: "garden", tier: game.catalog.maxTier(of: "garden"))
        game.testSet(0, .item(top))
        game.testSet(1, .item(top))
        XCTAssertEqual(game.move(from: 0, to: 1), .swapped)
        XCTAssertEqual(game.piece(at: 0), .item(top))
        XCTAssertEqual(game.piece(at: 1), .item(top))
    }

    func testMoveToEmptyCell() {
        let game = emptyGame()
        game.testSet(0, .item(carrot))
        XCTAssertEqual(game.move(from: 0, to: 10), .moved)
        XCTAssertNil(game.piece(at: 0))
        XCTAssertEqual(game.piece(at: 10), .item(carrot))
    }

    func testCannotMoveOntoDebrisOrMoveDebris() {
        let game = emptyGame()
        game.testSet(0, .item(carrot))
        game.testSet(1, .debris(1))
        XCTAssertEqual(game.move(from: 0, to: 1), .invalid)
        XCTAssertEqual(game.move(from: 1, to: 2), .invalid)
        XCTAssertEqual(game.move(from: 5, to: 6), .invalid, "пустая клетка не двигается")
        XCTAssertEqual(game.move(from: 0, to: 0), .invalid)
    }

    func testMergeClearsAdjacentDebrisLayer() {
        let game = emptyGame()
        // клетка 8 (ряд 1, колонка 1): соседи 1, 15, 7, 9
        game.testSet(1, .debris(1))
        game.testSet(7, .debris(2))
        game.testSet(16, .debris(1)) // по диагонали, не снимается
        game.testSet(8, .item(Item(chain: "garden", tier: 0)))
        game.testSet(20, .item(Item(chain: "garden", tier: 0)))
        guard case .merged(_, let cleared, _) = game.move(from: 20, to: 8) else {
            return XCTFail("ожидали слияние")
        }
        XCTAssertEqual(Set(cleared), [1, 7])
        XCTAssertNil(game.piece(at: 1))
        XCTAssertEqual(game.piece(at: 7), .debris(1))
        XCTAssertEqual(game.piece(at: 16), .debris(1))
    }

    func testGeneratorsMergeUpToMaxTier() {
        let game = emptyGame()
        let g0 = GeneratorPiece(chain: "garden", tier: 0)
        game.testSet(0, .generator(g0))
        game.testSet(1, .generator(g0))
        XCTAssertEqual(game.move(from: 0, to: 1), .mergedGenerator(GeneratorPiece(chain: "garden", tier: 1)))
        let top = GeneratorPiece(chain: "garden", tier: game.catalog.chain("garden")!.generatorTiers - 1)
        game.testSet(2, .generator(top))
        game.testSet(3, .generator(top))
        XCTAssertEqual(game.move(from: 2, to: 3), .swapped)
    }

    // MARK: - Генераторы и энергия

    func testSpawnSpendsEnergyAndPlacesNearGenerator() {
        let game = emptyGame()
        let gen = 60
        game.testSet(gen, .generator(GeneratorPiece(chain: "forest", tier: 0)))
        let before = game.state.energy
        guard case .spawned(let index, let item) = game.spawn(from: gen) else { return XCTFail("ожидали предмет") }
        XCTAssertEqual(game.state.energy, before - 1)
        XCTAssertEqual(item.chain, "forest")
        XCTAssertTrue(game.neighbors(of: gen).contains(index), "предмет падает в соседнюю клетку")
        XCTAssertEqual(game.piece(at: index), .item(item))
    }

    func testSpawnFailsWithoutEnergy() {
        let game = emptyGame()
        game.testSet(0, .generator(GeneratorPiece(chain: "garden", tier: 0)))
        game.testSetEnergy(0)
        XCTAssertEqual(game.spawn(from: 0), .noEnergy)
        XCTAssertEqual(game.state.cells.compactMap { $0 }.count, 1, "ничего не появилось")
    }

    func testSpawnFailsOnFullBoard() {
        let game = emptyGame()
        for i in 0..<game.balance.cellCount { game.testSet(i, .debris(1)) }
        game.testSet(0, .generator(GeneratorPiece(chain: "garden", tier: 0)))
        let before = game.state.energy
        XCTAssertEqual(game.spawn(from: 0), .boardFull)
        XCTAssertEqual(game.state.energy, before, "энергия не тратится, если некуда положить")
        XCTAssertEqual(game.spawn(from: 5), .notGenerator)
    }

    func testEnergyRegeneratesAndCaps() {
        let game = emptyGame()
        let b = game.balance
        game.testSetEnergy(10)
        clock.advance(b.energyRegen * 3 + 5)
        game.refreshEnergy()
        XCTAssertEqual(game.state.energy, 13)
        XCTAssertEqual(game.nextEnergyIn ?? -1, b.energyRegen - 5, accuracy: 0.001)
        clock.advance(b.energyRegen * 1000)
        game.refreshEnergy()
        XCTAssertEqual(game.state.energy, b.energyMax)
        XCTAssertNil(game.nextEnergyIn)
    }

    func testFullEnergyRestartsTimerOnSpend() {
        let game = emptyGame()
        game.testSet(0, .generator(GeneratorPiece(chain: "garden", tier: 0)))
        clock.advance(10_000)
        _ = game.spawn(from: 0)
        XCTAssertEqual(game.state.energy, game.balance.energyMax - 1)
        XCTAssertEqual(game.nextEnergyIn ?? -1, game.balance.energyRegen, accuracy: 0.001,
                       "отсчет идет с момента траты, а не с момента, когда энергия стала полной")
    }

    func testClockMovedBackDoesNotFreezeEnergy() {
        let game = emptyGame()
        game.testSetEnergy(0)
        clock.advance(-3600)
        game.refreshEnergy()
        clock.advance(game.balance.energyRegen)
        game.refreshEnergy()
        XCTAssertEqual(game.state.energy, 1)
    }

    // MARK: - Пузыри

    func testBubbleAppearsAndExpires() {
        var b = Balance()
        b.bubbleChance = 1
        let game = emptyGame(balance: b)
        let item = Item(chain: "garden", tier: b.bubbleMinTier - 1)
        game.testSet(0, .item(item))
        game.testSet(1, .item(item))
        guard case .merged(let result, _, let bubbleCell?) = game.move(from: 0, to: 1) else {
            return XCTFail("ожидали слияние с пузырем")
        }
        guard case .bubble(let inside, _)? = game.piece(at: bubbleCell) else { return XCTFail("нет пузыря") }
        XCTAssertEqual(inside, result)
        XCTAssertEqual(game.expireBubbles(), [])
        clock.advance(b.bubbleLifetime + 1)
        XCTAssertEqual(game.expireBubbles(), [bubbleCell])
        XCTAssertNil(game.piece(at: bubbleCell))
    }

    func testNoBubbleBelowMinTier() {
        var b = Balance()
        b.bubbleChance = 1
        let game = emptyGame(balance: b)
        game.testSet(0, .item(Item(chain: "garden", tier: 0)))
        game.testSet(1, .item(Item(chain: "garden", tier: 0)))
        XCTAssertEqual(game.move(from: 0, to: 1), .merged(item: Item(chain: "garden", tier: 1), cleared: [], bubble: nil))
    }

    func testPopBubbleCostsGems() {
        let game = emptyGame()
        let b = game.balance
        game.testSet(4, .bubble(carrot, expiresAt: clock.date.addingTimeInterval(30)))
        XCTAssertTrue(game.popBubble(at: 4))
        XCTAssertEqual(game.state.gems, b.startGems - b.popCost(carrot))
        XCTAssertEqual(game.piece(at: 4), .item(carrot))
        game.testSet(5, .bubble(carrot, expiresAt: clock.date.addingTimeInterval(30)))
        game.testSetGems(0)
        XCTAssertFalse(game.popBubble(at: 5))
    }

    // MARK: - Продажа и корзина

    func testSellGivesCoins() {
        let game = emptyGame()
        game.testSet(3, .item(carrot))
        XCTAssertEqual(game.sell(at: 3), carrot.value)
        XCTAssertEqual(game.state.coins, carrot.value)
        XCTAssertNil(game.piece(at: 3))
        XCTAssertEqual(game.sell(at: 3), 0)
    }

    func testBasketStoreAndRetrieve() {
        let game = emptyGame()
        for i in 0..<(game.balance.basketSize + 1) { game.testSet(i, .item(carrot)) }
        for i in 0..<game.balance.basketSize { XCTAssertTrue(game.store(at: i)) }
        XCTAssertFalse(game.store(at: game.balance.basketSize), "корзина полная")
        XCTAssertEqual(game.state.basket.count, game.balance.basketSize)
        let cell = game.retrieve(basketIndex: 0)
        XCTAssertNotNil(cell)
        XCTAssertEqual(game.piece(at: cell!), .item(carrot))
        XCTAssertEqual(game.state.basket.count, game.balance.basketSize - 1)
    }

    // MARK: - Заказы

    func testDeliverOrder() {
        let game = emptyGame()
        let order = Order(id: 999, needs: [carrot, Item(chain: "forest", tier: 1)], coins: 30, stars: 2, xp: 6)
        game.testSetOrders([order])
        XCTAssertFalse(game.canDeliver(order))
        XCTAssertNil(game.deliver(orderId: 999))
        game.testSet(10, .item(carrot))
        game.testSet(11, .item(Item(chain: "forest", tier: 1)))
        game.testSet(12, .item(carrot))
        XCTAssertTrue(game.canDeliver(order))
        XCTAssertEqual(game.deliver(orderId: 999), order)
        XCTAssertNil(game.piece(at: 10))
        XCTAssertNil(game.piece(at: 11))
        XCTAssertEqual(game.piece(at: 12), .item(carrot), "забирается только нужное количество")
        XCTAssertEqual(game.state.coins, 30)
        XCTAssertEqual(game.state.stars, 2)
        XCTAssertEqual(game.state.xp, 6)
        XCTAssertEqual(game.state.ordersTotal, 1)
        XCTAssertEqual(game.state.orders.count, game.balance.orderSlots, "на место отданного пришли новые")
    }

    func testOrderNeedsTwoOfSameItem() {
        let game = emptyGame()
        let order = Order(id: 7, needs: [carrot, carrot], coins: 1, stars: 1, xp: 1)
        game.testSetOrders([order])
        game.testSet(0, .item(carrot))
        XCTAssertFalse(game.canDeliver(order))
        game.testSet(1, .item(carrot))
        XCTAssertTrue(game.canDeliver(order))
    }

    func testGeneratedOrdersAreReachable() {
        for seed in UInt64(0)..<50 {
            let game = makeGame(seed: seed)
            for _ in 0..<20 {
                for order in game.state.orders {
                    XCTAssertFalse(order.needs.isEmpty)
                    XCTAssertGreaterThanOrEqual(order.stars, 1)
                    for need in order.needs {
                        XCTAssertTrue(game.state.unlockedChains.contains(need.chain), "заказ только из открытых цепочек")
                        XCTAssertLessThanOrEqual(need.tier, game.catalog.maxTier(of: need.chain))
                        let best = game.state.bestTier[need.chain] ?? 1
                        XCTAssertLessThanOrEqual(need.tier, max(2, best + 1), "заказ не дальше одной ступени от лучшей")
                    }
                }
                let ids = game.state.orders.map(\.id)
                XCTAssertEqual(Set(ids).count, ids.count)
                game.testSetOrders([])
            }
        }
    }

    // MARK: - Сохранение

    func testStateRoundTripsThroughJSON() throws {
        let game = makeGame()
        game.testSet(30, .bubble(carrot, expiresAt: clock.date))
        _ = game.spawn(from: (game.balance.rows - 1) * game.balance.cols + 1)
        let data = try JSONEncoder().encode(game.state)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(decoded, game.state)
        let restored = Game(state: decoded, balance: game.balance, seed: 1, now: { [clock] in clock!.date })
        XCTAssertEqual(restored.state, game.state)
    }

    func testWrongSizedSaveStartsNewGame() {
        var state = makeGame().state
        state.cells = [nil, nil]
        let game = Game(state: state, seed: 1, now: { [clock] in clock!.date })
        XCTAssertEqual(game.state.cells.count, game.balance.cellCount)
    }

    func testSameSeedSameGame() {
        let a = makeGame(seed: 7), b = makeGame(seed: 7)
        XCTAssertEqual(a.state.orders, b.state.orders)
        let gen = (a.balance.rows - 1) * a.balance.cols + 1
        for _ in 0..<10 {
            XCTAssertEqual(a.spawn(from: gen), b.spawn(from: gen))
        }
    }
}
