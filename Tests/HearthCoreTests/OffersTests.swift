import XCTest
@testable import HearthCore

/// Копилка, пропуск события, набор выходных, крупные паки и набор строителя.
final class OffersTests: XCTestCase {
    private var clock: TestClock!

    override func setUp() {
        super.setUp()
        clock = TestClock() // пятница: событие идет
    }

    private func makeGame() -> Game {
        let clock = self.clock!
        return Game(seed: 7, now: { clock.date })
    }

    private func deliverOrder(_ game: Game, id: Int, stars: Int = 1) {
        let item = Item(chain: "garden", tier: 1)
        game.testSet(0, .item(item))
        game.testSetOrders([Order(id: id, needs: [item], coins: 5, stars: stars, xp: 1)])
        XCTAssertNotNil(game.deliver(orderId: id))
    }

    // MARK: - Копилка

    func testPiggyFillsFromOrdersAndCaps() {
        let game = makeGame()
        let b = game.balance
        deliverOrder(game, id: 1000)
        XCTAssertEqual(game.state.piggyGems, b.piggyPerOrder)
        for i in 0..<(b.piggyMax / b.piggyPerOrder + 10) { deliverOrder(game, id: 1001 + i) }
        XCTAssertEqual(game.state.piggyGems, b.piggyMax, "не больше потолка")
        XCTAssertTrue(game.piggyFull)
    }

    func testPiggyOfferedOnlyFromThreshold() {
        let game = makeGame()
        XCTAssertFalse(game.canOffer(Products.piggy))
        game.state.piggyGems = game.balance.piggyMin
        XCTAssertTrue(game.canOffer(Products.piggy))
    }

    func testBreakingPiggyGivesSavedGems() {
        let game = makeGame()
        game.state.piggyGems = 250
        let gems = game.state.gems
        XCTAssertTrue(game.grantPurchase(productId: Products.piggy, transactionId: "p1"))
        XCTAssertEqual(game.state.gems, gems + 250)
        XCTAssertEqual(game.state.piggyGems, 0)
        XCTAssertFalse(game.grantPurchase(productId: Products.piggy, transactionId: "p1"), "одна транзакция один раз")
    }

    /// Полная копилка выгоднее маленького пака, но не выгоднее большого: это бонус, а не дыра.
    func testPiggyValueIsSane() {
        let b = Balance()
        let perDollarSmall = Double(Products.rewards[Products.gemsSmall]!.gems) / 0.99
        let perDollarMega = Double(Products.rewards[Products.gemsMega]!.gems) / 99.99
        let perDollarPiggy = Double(b.piggyMax) / 2.99
        XCTAssertGreaterThan(perDollarPiggy, perDollarSmall)
        XCTAssertLessThan(perDollarPiggy, perDollarMega)
    }

    // MARK: - Пакеты кристаллов

    func testBiggerPacksGiveMoreGemsPerDollar() {
        let prices: [(String, Double)] = [(Products.gemsSmall, 0.99), (Products.gemsMedium, 4.99), (Products.gemsLarge, 9.99),
                                          (Products.gemsChest, 19.99), (Products.gemsHuge, 49.99), (Products.gemsMega, 99.99)]
        let rates = prices.map { Double(Products.rewards[$0.0]!.gems) / $0.1 }
        for i in 1..<rates.count {
            XCTAssertGreaterThan(rates[i], rates[i - 1], "\(prices[i].0) не выгоднее предыдущего")
        }
        // и при этом не в разы: самый большой не больше чем вдвое выгоднее самого маленького
        XCTAssertLessThan(rates.last!, rates.first! * 2)
    }

    // MARK: - Пропуск события

    func testEventPassGivesPremiumTrackRetroactively() {
        let game = makeGame()
        let def = game.activeEvent!
        game.addEventTokens(def.milestones[2].tokens)
        XCTAssertTrue(game.canOffer(Products.eventPass))
        let gems = game.state.gems, energy = game.state.energy
        XCTAssertTrue(game.grantPurchase(productId: Products.eventPass, transactionId: "e1"))
        XCTAssertTrue(game.hasEventPass)
        XCTAssertFalse(game.canOffer(Products.eventPass), "второй раз не продаем")
        let first3 = Products.eventPassRewards.prefix(3)
        XCTAssertEqual(game.state.gems, gems + first3.reduce(0) { $0 + $1.gems })
        XCTAssertEqual(game.state.energy, energy + first3.reduce(0) { $0 + $1.energy })
        XCTAssertEqual(game.state.eventPassClaimed, 3)

        // дальше вторая дорожка идет вместе с первой
        let rewards = game.addEventTokens(def.milestones[3].tokens - game.state.eventTokens)
        XCTAssertEqual(rewards.count, 2, "обычная ступень и ступень пропуска")
        XCTAssertEqual(game.state.eventPassClaimed, 4)
    }

    func testEventPassTrackMatchesMilestones() {
        for def in EventsDef.bundled.events {
            XCTAssertEqual(def.milestones.count, Products.eventPassRewards.count, def.id)
        }
        XCTAssertTrue(Products.eventPassRewards.contains { $0.decor != nil }, "в пропуске есть свое украшение")
    }

    func testEventPassResetsWithNextEvent() {
        let game = makeGame()
        game.grantPurchase(productId: Products.eventPass, transactionId: "e1")
        XCTAssertTrue(game.hasEventPass)
        clock.advance(7 * 86400)
        XCTAssertNotNil(game.activeEvent)
        XCTAssertFalse(game.hasEventPass, "пропуск только на свои выходные")
        XCTAssertTrue(game.canOffer(Products.eventPass))
    }

    func testEventPassOutsideEventGivesGems() {
        let game = makeGame()
        clock.advance(4 * 86400) // вторник
        XCTAssertFalse(game.canOffer(Products.eventPass))
        let gems = game.state.gems
        XCTAssertTrue(game.grantPurchase(productId: Products.eventPass, transactionId: "e2"))
        XCTAssertEqual(game.state.gems, gems + Products.eventPassFallbackGems, "деньги не пропадают")
    }

    // MARK: - Наборы

    func testWeekendBundleOncePerEvent() {
        let game = makeGame()
        XCTAssertTrue(game.canOffer(Products.weekendBundle))
        XCTAssertTrue(game.grantPurchase(productId: Products.weekendBundle, transactionId: "w1"))
        XCTAssertEqual(game.state.decorOwned["decor_pond"], 1)
        XCTAssertFalse(game.canOffer(Products.weekendBundle))
        clock.advance(4 * 86400)
        XCTAssertFalse(game.canOffer(Products.weekendBundle), "в будни не продается")
        clock.advance(3 * 86400)
        XCTAssertTrue(game.canOffer(Products.weekendBundle), "на следующих выходных снова")
    }

    func testBuilderPackOnceWithStarsAndDecor() {
        let game = makeGame()
        let stars = game.state.stars
        XCTAssertTrue(game.grantPurchase(productId: Products.builder, transactionId: "b1"))
        XCTAssertEqual(game.state.stars, stars + 60)
        XCTAssertEqual(game.state.decorOwned["decor_lamp_double"], 1)
        XCTAssertFalse(game.canOffer(Products.builder))
        XCTAssertFalse(game.grantPurchase(productId: Products.builder, transactionId: "b2"))
    }

    /// Звезды из набора строителя не открывают больше одного-двух зданий: это ускорение, а не пропуск района.
    func testBuilderStarsAreModest() {
        let village = VillageDef.bundled
        let total = village.districts.reduce(0) { $0 + $1.totalCost }
        XCTAssertLessThan(Products.rewards[Products.builder]!.stars * 20, total)
    }

    func testAllOfferDecorHasSprites() {
        // ключи украшений должны совпадать с tools/village_map.py (DECOR)
        let keys = Products.rewards.values.compactMap(\.decor) + Products.eventPassRewards.compactMap(\.decor)
        for key in keys { XCTAssertTrue(key.hasPrefix("decor_"), key) }
    }

    func testOffersStateSurvivesSave() throws {
        let game = makeGame()
        game.state.piggyGems = 77
        game.grantPurchase(productId: Products.eventPass, transactionId: "e1")
        let data = try JSONEncoder().encode(game.state)
        let back = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(back.piggyGems, 77)
        XCTAssertEqual(back.eventPassKey, game.state.eventPassKey)
        XCTAssertEqual(back.eventPassClaimed, game.state.eventPassClaimed)
    }
}
