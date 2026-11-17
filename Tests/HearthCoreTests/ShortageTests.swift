import XCTest
@testable import HearthCore

/// Обмен кристаллов на монеты для окна «не хватает монет».
final class ShortageTests: XCTestCase {
    func testCoinPackExchanges() {
        let g = Game(seed: 3)
        g.testSetGems(200)
        let coins = g.state.coins
        XCTAssertTrue(g.buyCoins(Balance.coinPacks[0]))
        XCTAssertEqual(g.state.gems, 160)
        XCTAssertEqual(g.state.coins, coins + 1_000)
        XCTAssertFalse(g.buyCoins(CoinPack(gems: 1, coins: 1_000_000)), "только наборы из списка")
        g.testSetGems(10)
        XCTAssertFalse(g.buyCoins(Balance.coinPacks[0]))
    }

    func testEnergyThroughCoinsIsNotCheaperThanDirect() {
        // самая дешевая энергия за монеты - первая покупка дня
        let b = Balance()
        let coinsPerEnergy = Double(b.coinEnergyBasePrice) / Double(b.coinEnergyAmount)
        let directEnergyPerGem = Double(b.energyPerGem)
        for pack in Balance.coinPacks {
            let energyPerGem = Double(pack.coins) / coinsPerEnergy / Double(pack.gems)
            XCTAssertLessThanOrEqual(energyPerGem, directEnergyPerGem * 1.1, "\(pack)")
        }
    }
}
