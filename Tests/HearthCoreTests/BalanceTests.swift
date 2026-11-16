import XCTest
@testable import HearthCore

/// Баланс проверяет бот: играет как разумный игрок 4 раза в день и смотрит, нет ли застреваний,
/// слишком быстрого или медленного прохождения и выгодных петель.
final class BalanceTests: XCTestCase {
    private static var cache: [UInt64: SimReport] = [:]

    private func report(seed: UInt64) -> SimReport {
        if let r = Self.cache[seed] { return r }
        var config = SimConfig()
        config.seed = seed
        let r = Simulator.run(config)
        print("Бот, зерно \(seed):\n\(r)")
        Self.cache[seed] = r
        return r
    }

    private let seeds: [UInt64] = [1, 2, 3, 4, 5]

    func testVillageIsCompletableInReasonableTime() {
        for seed in seeds {
            let r = report(seed: seed)
            XCTAssertTrue(r.villageDone, "зерно \(seed): деревня отстроена за \(SimConfig().maxDays) дней")
            // не пролетается за пару дней, но и не тянется месяцами
            XCTAssertGreaterThan(r.days, 10, "зерно \(seed): слишком быстро")
            XCTAssertLessThan(r.days, 40, "зерно \(seed): слишком долго")
        }
    }

    func testFirstDistrictFeelsQuick() {
        for seed in seeds {
            let r = report(seed: seed)
            let day = r.districtDoneDay["square"] ?? .infinity
            XCTAssertLessThan(day, 4, "зерно \(seed): первый район должен закрываться за первые дни")
        }
    }

    func testDistrictsGetLonger() {
        for seed in seeds {
            let r = report(seed: seed)
            guard let a = r.districtDoneDay["square"], let b = r.districtDoneDay["farmstead"],
                  let c = r.districtDoneDay["riverside"] else { return XCTFail("зерно \(seed): не все районы") }
            XCTAssertLessThan(a, b - a + 0.5, "зерно \(seed): второй район не короче первого")
            XCTAssertLessThan(b - a, c - b + 0.5, "зерно \(seed): третий район не короче второго")
        }
    }

    func testBoardDoesNotStall() {
        for seed in seeds {
            let r = report(seed: seed)
            XCTAssertLessThanOrEqual(Double(r.stalledSessions), Double(r.sessions) * 0.05,
                                     "зерно \(seed): поле забивается и энергию некуда деть")
        }
    }

    /// Продажа - запасной выход, а не способ зарабатывать: заказы должны давать сильно больше монет.
    func testOrdersPayMuchMoreThanSelling() {
        for seed in seeds {
            let r = report(seed: seed)
            XCTAssertGreaterThan(r.orders, 0)
            XCTAssertLessThan(Double(r.coinsFromSelling), Double(r.coinsFromOrders) * 0.2, "зерно \(seed)")
        }
    }

    /// Энергия с уровней - приятный бонус, но не вечный двигатель.
    func testLevelUpEnergyIsSmallShare() {
        for seed in seeds {
            let r = report(seed: seed)
            XCTAssertLessThanOrEqual(Double(r.energyFromLevels), Double(r.energySpent) * 0.25, "зерно \(seed)")
        }
    }

    /// Пузырь не дешевле энергии, которую стоит сам предмет, на любой ступени любой цепочки.
    func testBubblesAreNeverCheaperThanEnergy() {
        let b = Balance()
        for chain in Catalog.bundled.chains {
            for tier in 0...chain.maxTier {
                let item = Item(chain: chain.id, tier: tier)
                XCTAssertGreaterThanOrEqual(b.popCost(item) * b.energyPerGem, item.value, "\(chain.id) \(tier)")
            }
        }
    }

    /// Продажа предмета не окупает энергию на него с запасом: иначе генератор превращается в станок монет.
    /// С учетом шанса сразу получить вторую ступень ожидаемая цена продажи за 1 энергию не выше 2 монет.
    func testSellingIsNotAMoneyPrinter() {
        let b = Balance()
        let maxGenTier = Catalog.bundled.chains.map(\.generatorTiers).max() ?? 1
        let upgrade = min(1, b.generatorUpgradeChance * Double(maxGenTier))
        let expectedCoinsPerEnergy = (1 - upgrade) * 1 + upgrade * 2
        XCTAssertLessThanOrEqual(expectedCoinsPerEnergy, 2)
        // а заказы платят втрое больше ценности
        let item = Item(chain: "garden", tier: 3)
        let game = Game(seed: 1)
        XCTAssertLessThan(game.sellPrice(item) * 2, item.value * 3)
    }

    func testSimulatorIsDeterministic() {
        var config = SimConfig()
        config.seed = 11
        config.maxDays = 3
        let a = Simulator.run(config)
        let b = Simulator.run(config)
        XCTAssertEqual(a.description, b.description)
    }
}
