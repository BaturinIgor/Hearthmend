import XCTest
@testable import HearthCore

final class StampsTests: XCTestCase {
    private func makeGame() -> Game {
        let clock = TestClock()
        return Game(seed: 5, now: { clock.date })
    }

    func testEveryPurchaseStampsAndFullCardRewards() {
        let game = makeGame()
        let b = game.balance
        let gems = game.state.gems
        for i in 0..<(b.stampsPerCard - 1) {
            XCTAssertTrue(game.grantPurchase(productId: Products.gemsSmall, transactionId: "t\(i)"))
            XCTAssertEqual(game.lastStamp, StampReward(stamps: i + 1, of: b.stampsPerCard))
        }
        let decor = game.stampDecor
        game.grantPurchase(productId: Products.gemsSmall, transactionId: "last")
        XCTAssertEqual(game.lastStamp?.completed, true)
        XCTAssertEqual(game.state.stamps, 0, "новая карточка")
        XCTAssertEqual(game.state.stampCards, 1)
        XCTAssertEqual(game.state.gems, gems + 80 * b.stampsPerCard + b.stampCardGems)
        XCTAssertEqual(game.state.decorOwned[decor], 1)
        XCTAssertNotEqual(game.stampDecor, decor, "украшения по кругу")
    }

    func testRepeatedTransactionDoesNotStamp() {
        let game = makeGame()
        game.grantPurchase(productId: Products.gemsSmall, transactionId: "same")
        game.grantPurchase(productId: Products.gemsSmall, transactionId: "same")
        XCTAssertEqual(game.state.stamps, 1)
        game.grantPurchase(productId: "unknown", transactionId: "x")
        XCTAssertEqual(game.state.stamps, 1, "неизвестный товар не считается")
    }

    /// Карточка не делает мелкие паки выгоднее самого крупного: кристаллов за доллар не больше, чем у мега-пака.
    func testStampsDoNotBreakGemPricing() {
        let b = Balance()
        let small = Double(80 * b.stampsPerCard + b.stampCardGems) / (0.99 * Double(b.stampsPerCard))
        let mega = 13000.0 / 99.99
        XCTAssertLessThan(small, mega)
        let medium = Double(450 * b.stampsPerCard + b.stampCardGems) / (4.99 * Double(b.stampsPerCard))
        XCTAssertLessThan(medium, mega)
    }

    func testStampsSurviveSave() throws {
        let game = makeGame()
        game.grantPurchase(productId: Products.gemsMedium, transactionId: "a")
        let state = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(game.state))
        XCTAssertEqual(state.stamps, 1)
        XCTAssertEqual(state.stampCards, 0)
    }
}
