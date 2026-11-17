import XCTest
@testable import HearthCore

final class GeneratorLevelTests: XCTestCase {
    func testOddsAreSaneAtEveryLevel() {
        XCTAssertEqual(Balance.generatorOdds.count, Balance.generatorCost.count)
        var last = 0.0
        for (level, odds) in Balance.generatorOdds.enumerated() {
            XCTAssertEqual(odds.reduce(0, +), 1, accuracy: 0.0001, "уровень \(level + 1)")
            XCTAssertGreaterThanOrEqual(odds[0], 0.08, "младшая ступень выпадает всегда: \(level + 1)")
            let v = Balance.generatorValuePerEnergy(level: level)
            XCTAssertGreaterThanOrEqual(v, last * 0.95, "уровень выше не хуже по выгоде: \(level + 1)")
            XCTAssertLessThanOrEqual(v, 1.7, "без имбы: \(level + 1)")
            last = v
        }
        for chain in Catalog.bundled.chains {
            XCTAssertEqual(chain.generatorTiers, Balance.generatorOdds.count, chain.id)
            XCTAssertGreaterThanOrEqual(chain.items.count, 9, "\(chain.id): длинная цепочка")
        }
    }

    func testHighLevelGeneratorCostsMoreAndGivesHigherTiers() {
        let clock = TestClock()
        var b = Balance()
        b.thicketOpen = 0
        b.debrisRows = 0
        let game = Game(balance: b, seed: 3, now: { clock.date })
        for i in 0..<b.cellCount { game.testSet(i, nil) }
        game.testSet(0, .generator(GeneratorPiece(chain: "garden", tier: 5)))
        XCTAssertEqual(game.spawnCost(GeneratorPiece(chain: "garden", tier: 5)), 5)
        var tiers: [Int] = []
        for _ in 0..<40 {
            game.testSetEnergy(100)
            guard case .spawned(let cell, let item) = game.spawn(from: 0) else { return XCTFail() }
            XCTAssertEqual(game.state.energy, 95)
            tiers.append(item.tier)
            game.testSet(cell, nil)
        }
        XCTAssertGreaterThan(Double(tiers.reduce(0, +)) / Double(tiers.count), 1.5)
        XCTAssertLessThanOrEqual(tiers.max() ?? 0, 5)
    }

    func testGeneratorsMergeUpToSix() {
        let clock = TestClock()
        var b = Balance()
        b.thicketOpen = 0
        b.debrisRows = 0
        let game = Game(balance: b, seed: 3, now: { clock.date })
        for i in 0..<b.cellCount { game.testSet(i, nil) }
        for level in 0..<5 {
            game.testSet(0, .generator(GeneratorPiece(chain: "forest", tier: level)))
            game.testSet(1, .generator(GeneratorPiece(chain: "forest", tier: level)))
            XCTAssertEqual(game.move(from: 0, to: 1), .mergedGenerator(GeneratorPiece(chain: "forest", tier: level + 1)))
        }
        game.testSet(0, .generator(GeneratorPiece(chain: "forest", tier: 5)))
        XCTAssertEqual(game.move(from: 0, to: 1), .swapped)
    }

    func testOrdersNeverAskForTopTiers() {
        for seed in UInt64(0)..<20 {
            let game = Game(seed: seed)
            for chain in game.catalog.chains { game.state.bestTier[chain.id] = chain.maxTier }
            game.state.unlockedChains = game.catalog.chains.map(\.id)
            for _ in 0..<30 {
                game.testSetOrders([])
                for order in game.state.orders {
                    for need in order.needs {
                        XCTAssertLessThanOrEqual(need.tier, game.catalog.orderTop(of: need.chain), need.chain)
                    }
                }
            }
        }
    }

    func testBotReachesHigherGeneratorsWithoutBreakingPace() {
        for seed in UInt64(1)...3 {
            var config = SimConfig()
            config.seed = seed
            let r = Simulator.run(config)
            print("Бот \(seed): дней \(String(format: "%.1f", r.days)), генератор до ур. \(r.bestGeneratorLevel + 1), генераторов из слияний \(r.generatorsDropped)")
            XCTAssertTrue(r.villageDone)
            XCTAssertGreaterThanOrEqual(r.bestGeneratorLevel, 2, "генераторы растут")
            XCTAssertGreaterThan(r.days, 45, "не слишком быстро")
            XCTAssertLessThan(r.days, 90, "и проходимо")
        }
    }
}
