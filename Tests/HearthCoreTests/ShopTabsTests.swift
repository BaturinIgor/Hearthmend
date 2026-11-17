import XCTest
@testable import HearthCore

final class ShopTabsTests: XCTestCase {
    func testShopGiftOncePerDayAndAlternates() {
        let clock = TestClock()
        let game = Game(seed: 1, now: { clock.date })
        XCTAssertTrue(game.shopGiftReady)
        let energy = game.state.energy, coins = game.state.coins
        let first = game.claimShopGift()
        XCTAssertNotNil(first)
        XCTAssertEqual(game.state.energy + game.state.coins, energy + coins + (first?.energy ?? 0) + (first?.coins ?? 0))
        XCTAssertFalse(game.shopGiftReady)
        XCTAssertNil(game.claimShopGift())
        clock.advance(86_400)
        XCTAssertTrue(game.shopGiftReady)
        let second = game.claimShopGift()
        XCTAssertNotEqual(first, second, "энергия и монеты чередуются")
    }

    func testShopGiftSurvivesSave() throws {
        let clock = TestClock()
        let game = Game(seed: 1, now: { clock.date })
        _ = game.claimShopGift()
        let decoded = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(game.state))
        let restored = Game(state: decoded, seed: 1, now: { clock.date })
        XCTAssertFalse(restored.shopGiftReady)
    }

    func testGemPacksGetBetterWithSize() {
        var last = -1
        for id in Products.gemPacks {
            let bonus = Products.gemBonus(id)
            XCTAssertGreaterThan(bonus, last, "крупный набор выгоднее: \(id)")
            last = bonus
        }
        XCTAssertEqual(Products.gemBonus(Products.gemsSmall), 0)
        XCTAssertLessThanOrEqual(Products.gemBonus(Products.gemsMega), 70)
    }

    func testShopGiftIsSmall() {
        // подарок лавки - повод заглянуть, а не источник энергии: меньше 10% дневного восстановления
        let perDay = 86_400 / Balance().energyRegen
        XCTAssertLessThan(Double(Balance.shopGiftEnergy), perDay * 0.1)
    }
}
