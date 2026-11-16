import XCTest
@testable import HearthCore

/// Ускорение x2, отмена продажи, подсказки, открытки.
final class HelpersTests: XCTestCase {
    private var clock: TestClock!

    override func setUp() {
        super.setUp()
        clock = TestClock()
    }

    private func makeGame() -> Game {
        let clock = self.clock!
        return Game(seed: 3, now: { clock.date })
    }

    private func firstGenerator(_ game: Game) -> Int {
        game.state.cells.firstIndex { if case .generator? = $0 { return true } else { return false } }!
    }

    // MARK: - Ускорение

    func testBoostLockedUntilLevel() {
        let game = makeGame()
        game.setBoost(true)
        XCTAssertFalse(game.boostActive, "до уровня \(game.balance.boostLevel) закрыто")
        game.testSetLevel(game.balance.boostLevel)
        game.setBoost(true)
        XCTAssertTrue(game.boostActive)
    }

    func testBoostCostsDoubleForTierUp() {
        let game = makeGame()
        game.testSetLevel(game.balance.boostLevel)
        game.setBoost(true)
        let gen = firstGenerator(game)
        var spent = 0, value = 0
        for _ in 0..<40 {
            game.refreshEnergy()
            let before = game.state.energy
            guard case .spawned(let cell, let item) = game.spawn(from: gen) else { break }
            spent += before - game.state.energy
            value += item.value
            XCTAssertGreaterThanOrEqual(item.tier, 1, "с ускорением не бывает первой ступени")
            game.testSet(cell, nil)
        }
        XCTAssertGreaterThan(spent, 0)
        // ценность за энергию такая же, как без ускорения (там 1 энергия ~ 1 предмет 0-й ступени со случайными апгрейдами)
        let perEnergy = Double(value) / Double(spent)
        XCTAssertLessThan(perEnergy, 1.6, "ускорение не делает энергию выгоднее")
    }

    func testBoostFallsBackWhenOneEnergyLeft() {
        let game = makeGame()
        game.testSetLevel(game.balance.boostLevel)
        game.setBoost(true)
        game.testSetEnergy(1)
        guard case .spawned(_, let item) = game.spawn(from: firstGenerator(game)) else { return XCTFail("не появилось") }
        XCTAssertLessThanOrEqual(item.tier, 2)
        XCTAssertEqual(game.state.energy, 0)
    }

    /// Бот с ускорением проходит деревню не намного быстрее: ускорение экономит тапы, а не энергию.
    func testBoostIsNotOverpowered() {
        var plain = SimConfig(), boosted = SimConfig()
        plain.seed = 21
        boosted.seed = 21
        boosted.useBoost = true
        let a = Simulator.run(plain), b = Simulator.run(boosted)
        print("без ускорения:\n\(a)\nс ускорением:\n\(b)")
        XCTAssertTrue(b.villageDone)
        XCTAssertGreaterThan(b.days, a.days * 0.85, "ускорение сокращает прохождение больше чем на 15%")
    }

    // MARK: - Отмена продажи

    func testUndoSaleRestoresItemAndCoins() {
        let game = makeGame()
        let item = Item(chain: "forest", tier: 3)
        game.testSet(10, .item(item))
        let coins = game.state.coins
        let price = game.sell(at: 10)
        XCTAssertTrue(game.canUndoSale)
        XCTAssertEqual(game.undoSale(), 10)
        XCTAssertEqual(game.piece(at: 10)?.item, item)
        XCTAssertEqual(game.state.coins, coins)
        XCTAssertGreaterThan(price, 0)
        XCTAssertFalse(game.canUndoSale, "отмена одна")
    }

    func testUndoSaleNeedsFreeCellAndCoins() {
        let game = makeGame()
        game.testSet(10, .item(Item(chain: "forest", tier: 3)))
        game.sell(at: 10)
        game.testSet(10, .item(Item(chain: "garden", tier: 0)))
        XCTAssertFalse(game.canUndoSale, "клетку заняли")
        XCTAssertNil(game.undoSale())
    }

    // MARK: - Подсказки

    func testMergeHintFindsLowestPair() {
        let game = makeGame()
        for i in game.state.cells.indices where game.state.cells[i]?.item != nil { game.testSet(i, nil) }
        game.testSet(20, .item(Item(chain: "garden", tier: 3)))
        game.testSet(30, .item(Item(chain: "garden", tier: 3)))
        game.testSet(25, .item(Item(chain: "forest", tier: 1)))
        XCTAssertEqual(game.mergeHint().map { [$0.0, $0.1] }, [20, 30])
        game.testSet(40, .item(Item(chain: "forest", tier: 1)))
        XCTAssertEqual(game.mergeHint().map { [$0.0, $0.1] }, [25, 40], "сначала младшая ступень")
    }

    func testCellsForOrder() {
        let game = makeGame()
        for i in game.state.cells.indices where game.state.cells[i]?.item != nil { game.testSet(i, nil) }
        let a = Item(chain: "garden", tier: 2)
        game.testSet(5, .item(a))
        game.testSet(6, .item(a))
        let order = Order(id: 1, needs: [a, a, Item(chain: "farm", tier: 4)], coins: 1, stars: 1, xp: 1)
        XCTAssertEqual(Set(game.cells(for: order)), [5, 6])
    }

    // MARK: - Открытки

    func testPostcardCompletesAfterPieces() {
        let game = makeGame()
        let b = game.balance
        let gems = game.state.gems
        var last: PostcardReward?
        for _ in 0..<b.postcardPieces { last = game.addPostcardPiece() }
        XCTAssertEqual(last?.completed, Postcards.views[0])
        XCTAssertEqual(game.state.postcardIndex, 1)
        XCTAssertEqual(game.state.postcardPieces, 0)
        XCTAssertEqual(game.state.gems, gems + b.postcardGems)
        XCTAssertEqual(game.state.decorOwned[Postcards.decor[0]], 1)
        XCTAssertEqual(game.postcardView, Postcards.views[1])
    }

    func testPostcardPieceFromOrder() {
        let game = makeGame()
        let item = Item(chain: "garden", tier: 1)
        game.testSet(0, .item(item))
        game.testSetOrders([Order(id: 77, needs: [item], coins: 1, stars: 1, xp: 1)])
        game.deliver(orderId: 77)
        XCTAssertEqual(game.state.postcardPieces, 1)
        XCTAssertEqual(game.lastPostcard?.piece, 1)
    }

    /// Открытки - приятная мелочь: кристаллов с них меньше, чем дает один маленький пак за 30 заказов.
    func testPostcardRewardIsModest() {
        let b = Balance()
        XCTAssertLessThan(b.postcardGems * 30 / b.postcardPieces, Products.rewards[Products.gemsSmall]!.gems)
    }

    func testHelpersStateSurvivesSave() throws {
        let game = makeGame()
        game.testSetLevel(game.balance.boostLevel)
        game.setBoost(true)
        game.addPostcardPiece()
        let back = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(game.state))
        XCTAssertTrue(back.boostOn)
        XCTAssertEqual(back.postcardPieces, 1)
    }
}
