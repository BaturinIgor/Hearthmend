import XCTest
@testable import HearthCore

final class ShopTests: XCTestCase {
    private var clock: TestClock!

    override func setUp() {
        super.setUp()
        clock = TestClock()
    }

    private func makeGame() -> Game {
        let clock = self.clock!
        return Game(seed: 5, now: { clock.date })
    }

    // MARK: - App Store

    func testPurchaseGrantedOncePerTransaction() {
        let game = makeGame()
        let gems = game.state.gems
        XCTAssertTrue(game.grantPurchase(productId: Products.gemsSmall, transactionId: "t1"))
        XCTAssertFalse(game.grantPurchase(productId: Products.gemsSmall, transactionId: "t1"), "повтор той же транзакции")
        XCTAssertEqual(game.state.gems, gems + 80)
        XCTAssertTrue(game.grantPurchase(productId: Products.gemsSmall, transactionId: "t2"))
        XCTAssertEqual(game.state.gems, gems + 160)
    }

    func testUnknownProductIgnored() {
        let game = makeGame()
        XCTAssertFalse(game.grantPurchase(productId: "com.other.app.gems", transactionId: "x"))
    }

    func testStarterPackOnlyOnce() {
        let game = makeGame()
        XCTAssertTrue(game.grantPurchase(productId: Products.starter, transactionId: "s1"))
        XCTAssertTrue(game.hasBought(Products.starter))
        let energy = game.state.energy
        XCTAssertFalse(game.grantPurchase(productId: Products.starter, transactionId: "s2"))
        XCTAssertEqual(game.state.energy, energy)
    }

    func testVIPExpires() {
        let game = makeGame()
        XCTAssertFalse(game.isVIP)
        game.grantPurchase(productId: Products.vipMonthly, transactionId: "v1")
        XCTAssertTrue(game.isVIP)
        clock.advance(31 * 86400)
        XCTAssertFalse(game.isVIP)
    }

    func testVIPUsesStoreKitExpiry() {
        let game = makeGame()
        let expires = clock.date.addingTimeInterval(3 * 86400)
        game.grantPurchase(productId: Products.vipMonthly, transactionId: "v1", expires: expires)
        XCTAssertEqual(game.state.vipUntil, expires)
        game.updateVIP(expires: nil)
        XCTAssertFalse(game.isVIP, "подписку отменили")
    }

    func testBiggerPacksGiveMoreGemsPerDollar() {
        let prices: [(String, Double)] = [(Products.gemsSmall, 0.99), (Products.gemsMedium, 4.99),
                                          (Products.gemsLarge, 9.99), (Products.gemsChest, 19.99)]
        var last = 0.0
        for (id, price) in prices {
            let perDollar = Double(Products.rewards[id]!.gems) / price
            XCTAssertGreaterThan(perDollar, last, id)
            last = perDollar
        }
    }

    // MARK: - Магазин в игре

    func testEnergyForGemsAtFairRate() {
        let game = makeGame()
        game.testSetGems(game.energyPackGems - 1)
        XCTAssertFalse(game.buyEnergyWithGems())
        game.testSetGems(game.energyPackGems)
        let energy = game.state.energy
        XCTAssertTrue(game.buyEnergyWithGems())
        XCTAssertEqual(game.state.energy, energy + game.balance.energyPack)
        XCTAssertEqual(game.state.gems, 0)
        // не выгоднее, чем пузыри и кувшин: одна цена кристалла в энергии везде
        XCTAssertEqual(game.balance.energyPack / game.energyPackGems, game.balance.energyPerGem)
    }

    func testCoinEnergyGetsPricierAndResetsNextDay() {
        let game = makeGame()
        game.state.coins = 100_000
        var prices: [Int] = []
        while let price = game.coinEnergyPrice {
            prices.append(price)
            XCTAssertTrue(game.buyEnergyWithCoins())
        }
        XCTAssertEqual(prices.count, game.balance.coinEnergyPerDay)
        XCTAssertEqual(prices, prices.sorted())
        XCTAssertFalse(game.buyEnergyWithCoins())
        clock.advance(86400)
        XCTAssertEqual(game.coinEnergyPrice, prices[0])
    }

    /// Монеты за энергию из магазина не окупаются заказами: петли "купил энергию - сделал заказ - купил" нет.
    func testCoinEnergyIsNotALoop() {
        let b = Balance()
        // заказ платит 3 монеты за единицу ценности, а на единицу ценности уходит минимум 1/2 энергии
        let bestCoinsPerEnergy = 3.0 * 2
        let shopCoinsPerEnergy = Double(b.coinEnergyBasePrice) / Double(b.coinEnergyAmount)
        XCTAssertGreaterThan(shopCoinsPerEnergy, bestCoinsPerEnergy)
    }

    func testBasketSlots() {
        let game = makeGame()
        game.state.coins = 0
        XCTAssertFalse(game.buyBasketSlot())
        game.state.coins = 1_000_000
        let size = game.state.basketSize
        XCTAssertTrue(game.buyBasketSlot())
        XCTAssertEqual(game.state.basketSize, size + 1)
        while game.buyBasketSlot() {}
        XCTAssertEqual(game.state.basketSize, game.balance.basketMax)
        XCTAssertNil(game.basketSlotPrice)
    }

    func testOpenJarNowCostsGemsUnlessVIP() {
        let game = makeGame()
        game.testSetJar(20)
        game.testSetGems(100)
        XCTAssertEqual(game.jarOpenGems, 10)
        XCTAssertEqual(game.openJarNow(), 20)
        XCTAssertEqual(game.state.gems, 90)
        game.grantPurchase(productId: Products.vipMonthly, transactionId: "v")
        game.testSetJar(20)
        XCTAssertEqual(game.jarOpenGems, 0)
        XCTAssertEqual(game.openJarNow(), 20)
        XCTAssertEqual(game.state.gems, 90)
    }

    // MARK: - Ежедневная награда

    func testDailyRewardOncePerDayAndStreak() {
        let game = makeGame()
        XCTAssertTrue(game.dailyRewardReady)
        XCTAssertEqual(game.claimDaily(), Balance.dailyRewards[0])
        XCTAssertNil(game.claimDaily())
        clock.advance(86400)
        XCTAssertEqual(game.dailyStreakNext, 1)
        XCTAssertEqual(game.claimDaily(), Balance.dailyRewards[1])
        clock.advance(3 * 86400)
        XCTAssertEqual(game.dailyStreakNext, 0, "пропустил день - серия заново")
    }

    func testDailyStreakWrapsAround() {
        let game = makeGame()
        for _ in 0..<Balance.dailyRewards.count {
            XCTAssertNotNil(game.claimDaily())
            clock.advance(86400)
        }
        XCTAssertEqual(game.claimDaily(), Balance.dailyRewards[0])
    }

    func testShopStateSurvivesOldSave() throws {
        let game = makeGame()
        let data = try JSONEncoder().encode(game.state)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["vipUntil", "purchasedOneTime", "grantedTransactions", "coinEnergyDay", "coinEnergyBought",
                    "dailyClaimedAt", "dailyStreak", "jarEnergy", "jarOpenedAt"] {
            json.removeValue(forKey: key)
        }
        let state = try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(state.dailyStreak, 0)
        XCTAssertNil(state.vipUntil)
    }
}
