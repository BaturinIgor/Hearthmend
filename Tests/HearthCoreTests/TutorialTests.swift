import XCTest
@testable import HearthCore

final class TutorialTests: XCTestCase {
    func testStepsAdvanceInOrder() {
        let clock = TestClock()
        var b = Balance()
        b.debrisRows = 0
        let game = Game(balance: b, seed: 4, now: { clock.date })
        XCTAssertEqual(game.tutorial, .spawn)

        // слияние до тапа по генератору шаг не двигает
        for i in 0..<b.cellCount { game.testSet(i, nil) }
        game.testSet(0, .item(Item(chain: "garden", tier: 0)))
        game.testSet(1, .item(Item(chain: "garden", tier: 0)))
        _ = game.move(from: 0, to: 1)
        XCTAssertEqual(game.tutorial, .spawn)

        game.testSet(10, .generator(GeneratorPiece(chain: "garden", tier: 0)))
        guard case .spawned = game.spawn(from: 10) else { return XCTFail() }
        XCTAssertEqual(game.tutorial, .merge)

        game.testSet(20, .item(Item(chain: "forest", tier: 0)))
        game.testSet(21, .item(Item(chain: "forest", tier: 0)))
        _ = game.move(from: 20, to: 21)
        XCTAssertEqual(game.tutorial, .deliver)

        let item = Item(chain: "quarry", tier: 1)
        game.testSet(30, .item(item))
        game.testSetOrders([Order(id: 777, needs: [item], coins: 6, stars: 50, xp: 1)])
        XCTAssertNotNil(game.deliver(orderId: 777))
        XCTAssertEqual(game.tutorial, .build)

        guard case .done = game.complete(taskId: "square_clear") else { return XCTFail() }
        XCTAssertEqual(game.tutorial, .done)
    }

    func testSkip() {
        let game = Game(seed: 1)
        game.skipTutorial()
        XCTAssertEqual(game.tutorial, .done)
    }

    func testOldSaveWithOrdersSkipsTutorial() throws {
        let game = Game(seed: 1)
        game.state.ordersTotal = 3
        let data = try JSONEncoder().encode(game.state)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "tutorialStep")
        let state = try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(state.tutorialStep, TutorialStep.done.rawValue)
    }
}

final class DemoTests: XCTestCase {
    func testDemoStateIsValid() {
        let clock = TestClock()
        let game = Game.demo(now: { clock.date })
        XCTAssertEqual(game.state.cells.count, game.balance.cellCount)
        XCTAssertEqual(game.tutorial, .done)
        XCTAssertTrue(game.state.unlockedChains.contains("apiary"))
        XCTAssertTrue(game.state.unlockedChains.contains("farm"))
        XCTAssertTrue(game.state.orders.contains { game.canDeliver($0) }, "на скриншоте есть готовый заказ")
        for case .item(let item)? in game.state.cells {
            XCTAssertLessThanOrEqual(item.tier, game.catalog.maxTier(of: item.chain))
        }
    }
}
