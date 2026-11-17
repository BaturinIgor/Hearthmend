import XCTest
@testable import HearthCore

final class DepthsTests: XCTestCase {
    /// Понедельник, полдень по времени игрока: событие идет.
    private func monday() -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        return cal.date(from: DateComponents(year: 2027, month: 1, day: 18, hour: 12))!
    }

    private func makeGame(level: Int = 10) -> (Game, TestClock) {
        let clock = TestClock()
        clock.date = monday()
        let game = Game(seed: 4, now: { clock.date })
        game.state.level = level
        return (game, clock)
    }

    func testScheduleMondayToThursday() {
        let (game, _) = makeGame()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let mon = monday()
        for day in 0..<7 {
            let date = cal.date(byAdding: .day, value: day, to: mon)!
            let s = game.adventureSchedule(at: date)
            if day < 4 { XCTAssertNotNil(s, "день \(day)") } else { XCTAssertNil(s, "день \(day)") }
        }
        // ярмарка выходных и большое событие не пересекаются
        for day in 0..<7 {
            let date = cal.date(byAdding: .day, value: day, to: mon)!
            XCTAssertFalse(game.adventureSchedule(at: date) != nil && game.eventSchedule(at: date) != nil)
        }
    }

    func testLockedBeforeLevel() {
        let (game, _) = makeGame(level: Balance.adventureLevel - 1)
        XCTAssertNil(game.adventure)
        game.state.level = Balance.adventureLevel
        XCTAssertNotNil(game.adventure)
        XCTAssertEqual(game.adventure?.moves, Balance.adventureStartMoves)
    }

    func testMapIsTheSameForEveryoneAndPassable() {
        let a = DepthsState.generate(seed: Game.seed(of: "2027-3-depths"))
        let b = DepthsState.generate(seed: Game.seed(of: "2027-3-depths"))
        XCTAssertEqual(a, b)
        let w = DepthsState.width
        for r in 0..<DepthsState.depth {
            let rocks = (0..<w).filter { a.cells[r * w + $0].isRock }.count
            XCTAssertLessThanOrEqual(rocks, 1, "ряд \(r) не перекрыт")
        }
        for row in Depths.treasureRows {
            XCTAssertTrue((0..<w).contains { if case .treasure? = a.cells[row * w + $0].content { return true } else { return false } })
        }
    }

    func testDigOnlyNextToOpenCells() {
        let (game, _) = makeGame()
        XCTAssertNotNil(game.adventure)
        let w = DepthsState.width
        XCTAssertFalse(game.canDig(w * 3), "глубоко без прохода")
        let first = (0..<w).first { game.canDig($0) }!
        let moves = game.adventure!.moves
        var result = game.dig(first)
        while case .chipped = result { result = game.dig(first) }
        guard case .opened = result else { return XCTFail("\(result)") }
        XCTAssertLessThan(game.adventure!.moves, moves)
        if game.adventure!.depths!.cells[first + w].hardness > 0 {
            XCTAssertTrue(game.canDig(first + w), "под открытой можно")
        }
    }

    func testNoMovesNoDigging() {
        let (game, _) = makeGame()
        game.state.adventure?.moves = 0
        let first = (0..<DepthsState.width).first { game.canDig($0) }!
        XCTAssertEqual(game.dig(first), .noMoves)
    }

    func testMergingFindsBeatsDeliveringSingles() {
        for c in Depths.chains {
            for t in 1...Depths.maxTier {
                let merged = Depths.points(Item(chain: c, tier: t))
                let singles = Depths.points(Item(chain: c, tier: t - 1)) * 2
                XCTAssertGreaterThan(merged, singles, "\(c) \(t)")
            }
        }
        let (game, _) = makeGame()
        _ = game.adventure
        let ore = Item(chain: Depths.chains[0], tier: 0)
        game.state.adventure?.depths?.board[0] = ore
        game.state.adventure?.depths?.board[1] = ore
        XCTAssertTrue(game.moveFind(from: 0, to: 1))
        XCTAssertEqual(game.adventure?.depths?.board[1], Item(chain: ore.chain, tier: 1))
        let points = game.adventure!.points
        XCTAssertEqual(game.deliverFind(1)?.points, Depths.points(Item(chain: ore.chain, tier: 1)))
        XCTAssertEqual(game.adventure!.points, points + 3)
    }

    func testPrizesLandOnMainBoard() {
        let (game, _) = makeGame()
        _ = game.adventure
        let pending = game.state.pendingChests.count + game.state.cells.filter { if case .chest? = $0 { return true } else { return false } }.count
        let prizes = game.addAdventurePoints(Depths.track[1].points)
        XCTAssertEqual(prizes.count, 2)
        XCTAssertEqual(game.adventure?.claimed, 2)
        let after = game.state.pendingChests.count + game.state.cells.filter { if case .chest? = $0 { return true } else { return false } }.count
        XCTAssertEqual(after, pending + 2, "ресурсы встают на главное поле или ждут места")
    }

    func testOrdersGiveMovesAndDailyGift() {
        let (game, clock) = makeGame()
        _ = game.adventure
        XCTAssertTrue(game.adventureDailyReady)
        XCTAssertTrue(game.adventureNeedsAttention)
        XCTAssertEqual(game.claimAdventureDaily(), Balance.adventureDailyMoves)
        XCTAssertFalse(game.adventureDailyReady)
        clock.advance(86_400)
        XCTAssertTrue(game.adventureDailyReady)
        for stars in [1, 2, 5, 9, 20] {
            let order = Order(id: 1, needs: [], coins: 0, stars: stars, xp: 0)
            XCTAssertTrue((1...5).contains(Game.adventureMoves(for: order)))
        }
    }

    func testNewWeekStartsFresh() {
        let (game, clock) = makeGame()
        game.state.adventure?.points = 0
        _ = game.addAdventurePoints(50)
        XCTAssertGreaterThan(game.adventure!.claimed, 0)
        clock.advance(7 * 86_400)
        XCTAssertEqual(game.adventure?.claimed, 0)
        XCTAssertEqual(game.adventure?.points, 0)
    }

    func testAdventureSurvivesSave() throws {
        let (game, clock) = makeGame()
        let first = (0..<DepthsState.width).first { game.canDig($0) }!
        _ = game.dig(first)
        let data = try JSONEncoder().encode(game.state)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(decoded.adventure, game.state.adventure)
        let restored = Game(state: decoded, seed: 1, now: { clock.date })
        XCTAssertEqual(restored.adventure?.depths, game.adventure?.depths)
    }

    /// Бот играет все события за игру: дорожка проходится не целиком, но заметно,
    /// а награды - приятная добавка, а не вторая экономика.
    func testDepthsBalance() {
        for seed in UInt64(1)...3 {
            var config = SimConfig()
            config.seed = seed
            let r = Simulator.run(config)
            let events = r.adventureProgress.count
            let avg = r.adventureProgress.reduce(0, +) / Double(max(1, events))
            let depth = Double(r.adventureDepth.reduce(0, +)) / Double(max(1, r.adventureDepth.count))
            print("Бот \(seed): событий \(events), дорожка в среднем \(Int(avg * 100))%, глубина \(String(format: "%.1f", depth)), ценность \(Int(r.adventureValue)) из энергии \(r.energySpent), дней \(String(format: "%.1f", r.days))")
            XCTAssertGreaterThan(events, 5)
            XCTAssertGreaterThan(avg, 0.4, "дорожка проходится заметно")
            XCTAssertLessThan(Double(r.adventureValue), Double(r.energySpent) * 0.15, "без имбы")
            XCTAssertTrue(r.villageDone)
        }
    }
}
