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
        // сводка в аннотации CI: сколько дней и уровень на выходе
        let districts = r.districtDoneDay.sorted { $0.value < $1.value }.map { "\($0.key) \(String(format: "%.1f", $0.value))" }.joined(separator: ", ")
        print("::notice title=Бот \(seed)::дней \(String(format: "%.1f", r.days)), уровень \(r.level), заказов \(r.orders); \(districts)")
        Self.cache[seed] = r
        return r
    }

    private let seeds: [UInt64] = [1, 2, 3, 4, 5]

    func testVillageIsCompletableInReasonableTime() {
        for seed in seeds {
            let r = report(seed: seed)
            XCTAssertTrue(r.villageDone, "зерно \(seed): деревня отстроена за \(SimConfig().maxDays) дней")
            // семь районов: игры хватает на месяц-другой, но конец виден
            XCTAssertGreaterThan(r.days, 40, "зерно \(seed): слишком быстро")
            XCTAssertLessThan(r.days, 85, "зерно \(seed): слишком долго")
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

    /// Северный берег: сад и холм тоже проходятся, и каждый следующий район не короче предыдущего.
    func testNorthDistrictsAreReachable() {
        for seed in seeds {
            let r = report(seed: seed)
            guard let c = r.districtDoneDay["riverside"], let d = r.districtDoneDay["orchard"],
                  let e = r.districtDoneDay["hilltop"] else { return XCTFail("зерно \(seed): сад или холм не пройдены") }
            XCTAssertGreaterThan(d - c, 2, "зерно \(seed): сад пролетается слишком быстро")
            XCTAssertLessThan(d - c, e - d + 1, "зерно \(seed): холм не длиннее сада")
        }
    }

    /// Шахта и ярмарка проходятся, и каждая дольше холма: поздние районы - главная часть игры.
    func testFarDistrictsAreReachableAndLonger() {
        for seed in seeds {
            let r = report(seed: seed)
            guard let e = r.districtDoneDay["hilltop"], let m = r.districtDoneDay["mine"], let f = r.districtDoneDay["fair"],
                  let d = r.districtDoneDay["orchard"] else { return XCTFail("зерно \(seed): шахта или ярмарка не пройдены") }
            XCTAssertGreaterThan(m - e, (e - d) * 0.8, "зерно \(seed): шахта пролетается")
            XCTAssertGreaterThan(f - m, (m - e) * 0.8, "зерно \(seed): ярмарка короче шахты")
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

    /// Кувшин заметно помогает тем, кто заходит редко, но не удваивает энергию.
    func testJarIsHelpfulButNotDominant() {
        for seed in seeds {
            let r = report(seed: seed)
            XCTAssertGreaterThan(r.energyFromJar, 0, "зерно \(seed): кувшин работает")
            XCTAssertLessThanOrEqual(Double(r.energyFromJar), Double(r.energySpent) * 0.3, "зерно \(seed)")
        }
    }

    /// События радуют, но энергия с них - небольшая добавка.
    func testEventsGiveSmallEnergyShare() {
        for seed in seeds {
            let r = report(seed: seed)
            XCTAssertGreaterThan(r.eventMilestones, 0, "зерно \(seed): события работают")
            XCTAssertLessThanOrEqual(Double(r.energyFromEvents), Double(r.energySpent) * 0.1, "зерно \(seed)")
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

    /// Задания дня - заметная, но небольшая добавка энергии; кристаллов с них меньше пачки за 0.99 в неделю.
    func testQuestsAreABonusNotTheEconomy() {
        for seed in seeds {
            let r = report(seed: seed)
            XCTAssertGreaterThan(r.energyFromQuests, 0, "зерно \(seed): задания выполняются")
            XCTAssertLessThanOrEqual(Double(r.energyFromQuests), Double(r.energySpent) * 0.15, "зерно \(seed)")
            let weeks = max(1, r.days / 7)
            XCTAssertLessThan(Double(r.gemsFromQuests) / weeks, 200, "зерно \(seed): кристаллов с заданий за неделю")
        }
    }

    /// Альбом: награды разовые и ограниченные.
    func testCollectionRewardsAreBounded() {
        for seed in seeds {
            let r = report(seed: seed)
            XCTAssertGreaterThan(r.coinsFromCollection, 0, "зерно \(seed): находки оплачиваются")
            XCTAssertLessThan(r.gemsFromCollection, 250, "зерно \(seed)")
            XCTAssertLessThan(r.coinsFromCollection, r.coinsFromOrders / 5, "зерно \(seed): альбом не заменяет заказы")
        }
    }
}
