import XCTest
@testable import HearthCore

final class BarterTests: XCTestCase {
    /// Пятница: идут выходные.
    private func makeGame(level: Int = 10) -> (Game, TestClock) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let clock = TestClock()
        clock.date = cal.date(from: DateComponents(year: 2027, month: 1, day: 22, hour: 12))!
        let game = Game(seed: 11, now: { clock.date })
        game.state.level = level
        game.state.unlockedChains = ["garden", "forest", "quarry", "apiary"]
        for c in game.state.unlockedChains { game.state.bestTier[c] = 4 }
        return (game, clock)
    }

    /// Кладет на поле то, что просит обмен.
    private func supply(_ game: Game, _ index: Int) {
        let need = game.barter!.offers[index].needs
        let free = game.state.cells.firstIndex { $0 == nil }!
        game.state.cells[free] = .item(need)
    }

    func testOnlyOnWeekendsAndFromLevel() {
        let (game, clock) = makeGame(level: Balance.barterLevel - 1)
        XCTAssertNil(game.barter, "еще рано по уровню")
        game.state.level = Balance.barterLevel
        let b = game.barter!
        XCTAssertEqual(b.good, Barter.start)
        XCTAssertEqual(b.offers.count, 3)
        XCTAssertEqual(b.offers.map(\.level), [0, 1, 2])
        clock.advance(3 * 86_400) // понедельник
        XCTAssertNil(game.barter)
    }

    func testGenerousOfferAsksMoreAndGivesMore() {
        let (game, _) = makeGame()
        for _ in 0..<20 {
            let o = game.makeBarterOffers(step: 3)
            XCTAssertLessThanOrEqual(o[0].needs.tier, o[2].needs.tier)
            XCTAssertLessThanOrEqual(o[0].coins, o[2].coins)
            XCTAssertEqual(Set(o.map(\.friend)).count, 3, "трое разных жителей")
            for offer in o {
                XCTAssertEqual(Friends.chain(of: offer.friend), offer.needs.chain, "житель просит предмет своей цепочки")
            }
        }
    }

    func testTradeTakesItemAndMovesOn() {
        let (game, _) = makeGame()
        XCTAssertFalse(game.canBarter(0), "на поле нет нужного")
        XCTAssertFalse(game.barterReady)
        supply(game, 1)
        XCTAssertTrue(game.barterReady)
        let offer = game.barter!.offers[1]
        let coins = game.state.coins
        let t = game.barter(1)!
        XCTAssertEqual(t.offer, offer)
        XCTAssertFalse(game.state.cells.contains { $0 == .item(offer.needs) })
        XCTAssertEqual(game.state.coins, coins + offer.coins)
        let b = game.barter!
        XCTAssertEqual(b.step, 1)
        XCTAssertEqual(b.good, offer.gives)
        XCTAssertEqual(b.trail, [Barter.start, offer.gives])
        XCTAssertEqual(b.value, 2)
        XCTAssertEqual(b.offers.count, 3)
    }

    func testLastTradeGivesStallOfThatFriendAndTentForGenerosity() {
        let (game, _) = makeGame()
        let gems = game.state.gems
        var last: Game.BarterTrade?
        for _ in 0..<Barter.steps {
            supply(game, 2)
            last = game.barter(2)
        }
        let t = last!
        XCTAssertTrue(t.finished)
        XCTAssertEqual(t.stall, Barter.stallOf[t.offer.friend])
        XCTAssertTrue(t.tent)
        XCTAssertEqual(t.gems, Barter.steps * 3)
        XCTAssertEqual(game.state.gems, gems + t.gems)
        XCTAssertEqual(game.state.decorOwned[t.stall!], 1)
        XCTAssertEqual(game.state.decorOwned[Barter.tent], 1)
        XCTAssertTrue(game.state.newDecor)
        XCTAssertTrue(game.barter!.finished)
        XCTAssertTrue(game.barter!.offers.isEmpty)
        XCTAssertFalse(game.barterReady)
        XCTAssertNil(game.barter(0))
    }

    func testEasyPathGetsStallButNoTent() {
        let (game, _) = makeGame()
        var last: Game.BarterTrade?
        for _ in 0..<Barter.steps {
            supply(game, 0)
            last = game.barter(0)
        }
        XCTAssertTrue(last!.finished)
        XCTAssertNotNil(last!.stall)
        XCTAssertFalse(last!.tent)
        XCTAssertNil(game.state.decorOwned[Barter.tent])
    }

    func testEveryFriendHasAStall() {
        for f in Friends.all { XCTAssertNotNil(Barter.stallOf[f], f) }
        XCTAssertEqual(Barter.goods.count, Barter.steps - 1)
    }

    func testNewWeekendStartsOver() {
        let (game, clock) = makeGame()
        supply(game, 0)
        game.barter(0)
        XCTAssertEqual(game.barter!.step, 1)
        clock.advance(7 * 86_400)
        XCTAssertEqual(game.barter!.step, 0)
        XCTAssertEqual(game.barter!.good, Barter.start)
    }

    func testBarterSurvivesSave() throws {
        let (game, clock) = makeGame()
        supply(game, 0)
        game.barter(0)
        let data = try JSONEncoder().encode(game.state)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        let restored = Game(state: decoded, seed: 1, now: { clock.date })
        XCTAssertEqual(restored.barter, game.barter)
    }

    /// Бот меняется по выходным: прилавок получается чаще, чем через раз, но не всегда, и кристаллов немного.
    func testBarterBalance() {
        for seed in UInt64(1)...2 {
            let r = SimRuns.standard(seed)
            print("Обмен \(seed): выходных \(r.barterWeekends), обменов \(r.barterTrades), прилавков \(r.barterFinished), палаток \(r.barterTents), кр \(r.gemsFromBarter), мон \(r.coinsFromBarter), энергия \(r.energyFromBarter), дней \(String(format: "%.1f", r.days))")
            XCTAssertGreaterThanOrEqual(r.barterWeekends, 4)
            XCTAssertGreaterThan(Double(r.barterFinished), Double(r.barterWeekends) * 0.5)
            XCTAssertLessThan(r.barterTents, r.barterFinished, "палатка не каждый раз")
            XCTAssertLessThan(r.gemsFromBarter, r.barterWeekends * 20)
            XCTAssertLessThan(r.energyFromBarter, r.energySpent / 20)
        }
    }
}
