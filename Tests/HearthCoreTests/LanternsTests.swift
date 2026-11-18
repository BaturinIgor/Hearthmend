import XCTest
@testable import HearthCore

final class LanternsTests: XCTestCase {
    /// Понедельник недели, когда идет «Ночь фонарей».
    private func makeGame() -> (Game, TestClock) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let clock = TestClock()
        clock.date = cal.date(from: DateComponents(year: 2027, month: 1, day: 18, hour: 12))!
        let game = Game(seed: 8, now: { clock.date })
        game.state.level = 10
        while game.adventureSchedule(at: clock.date)?.kind != .lanterns { clock.advance(7 * 86_400) }
        XCTAssertNotNil(game.adventure?.lanterns)
        return (game, clock)
    }

    private let w = LanternsState.cols
    private var center: Int { (LanternsState.rows / 2) * w + w / 2 }

    /// Ночь без секретов: удобно считать очки.
    private func plain(_ game: Game) {
        for i in game.state.adventure!.lanterns!.cells.indices { game.state.adventure?.lanterns?.cells[i].secret = nil }
    }

    func testMapIsSharedAndHasSecrets() {
        let a = LanternsState.generate(seed: 9), b = LanternsState.generate(seed: 9)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, LanternsState.generate(seed: 9, nights: 1))
        XCTAssertEqual(a.darkLeft, LanternsState.size)
        XCTAssertEqual(a.cells.filter { $0.secret == .wish }.count, Lanterns.wishesPerNight)
        XCTAssertEqual(a.cells.filter { $0.secret == .fireflies }.count, Lanterns.firefliesPerNight)
    }

    func testAreaIsADiamondClippedByEdges() {
        XCTAssertEqual(LanternsState.area(center, radius: 0), [center])
        XCTAssertEqual(LanternsState.area(center, radius: 1).count, 5)
        XCTAssertEqual(LanternsState.area(center, radius: 2).count, 13)
        XCTAssertEqual(LanternsState.area(0, radius: 1).count, 3, "в углу меньше")
    }

    func testHangSpendsMoveAndLightsItsCell() {
        let (game, _) = makeGame()
        plain(game)
        let moves = game.adventure!.moves
        let r = game.hangLantern(center)!
        XCTAssertEqual(game.adventure!.moves, moves - 1)
        XCTAssertEqual(r.lit, [center])
        XCTAssertEqual(r.points, Lanterns.cellPoints)
        XCTAssertEqual(game.adventure!.lanterns!.cells[center].lantern, 0)
        XCTAssertNil(game.hangLantern(center), "на клетке уже висит фонарь")
        game.state.adventure?.moves = 0
        XCTAssertNil(game.hangLantern(center + 1))
    }

    func testMergeShinesFartherAtTarget() {
        let (game, _) = makeGame()
        plain(game)
        game.state.adventure?.moves = 10
        _ = game.hangLantern(center)
        _ = game.hangLantern(center + 2)
        XCTAssertTrue(game.canMergeLanterns(center, center + 2))
        let r = game.moveLantern(from: center, to: center + 2)!
        let cells = game.adventure!.lanterns!.cells
        XCTAssertNil(cells[center].lantern)
        XCTAssertEqual(cells[center + 2].lantern, 1)
        // радиус 1 вокруг цели: 5 клеток, одна уже была светлой
        XCTAssertEqual(r.lit.count, 4)
        XCTAssertTrue(cells[center].lit, "светлая клетка остается светлой")
    }

    func testOnlyMergingMovesLanterns() {
        let (game, _) = makeGame()
        game.state.adventure?.moves = 10
        _ = game.hangLantern(center)
        XCTAssertNil(game.moveLantern(from: center, to: center + 1), "на пустую клетку не переносят")
        game.state.adventure?.lanterns?.cells[0].lantern = 2
        XCTAssertFalse(game.canMergeLanterns(center, 0), "разные ступени не сливаются")
    }

    func testSecretsGiveWishesFirefliesAndChests() {
        let (game, _) = makeGame()
        plain(game)
        game.state.adventure?.lanterns?.cells[center].secret = .wish
        game.state.adventure?.lanterns?.cells[center + 1].secret = .fireflies
        game.state.adventure?.lanterns?.cells[center - 1].secret = .chest(Chest(kind: .coins, level: 0))
        game.state.adventure?.lanterns?.cells[center + w].lantern = 1
        game.state.adventure?.lanterns?.cells[center - w].lantern = 1
        let moves = game.adventure!.moves
        let r = game.moveLantern(from: center + w, to: center - w)!
        // радиус 2 вокруг center - w задевает center и его соседей
        XCTAssertEqual(r.wishes, [center])
        XCTAssertEqual(r.fireflies, [center + 1])
        XCTAssertEqual(r.chests, [center - 1])
        XCTAssertEqual(game.adventure!.moves, moves + Lanterns.fireflyMoves)
        XCTAssertEqual(r.points, r.lit.count * Lanterns.cellPoints + Lanterns.wishPoints)
        XCTAssertNil(game.adventure!.lanterns!.cells[center].secret)
    }

    func testBrightestLanternFliesAway() {
        let (game, _) = makeGame()
        plain(game)
        let top = Lanterns.maxTier - 1
        game.state.adventure?.lanterns?.cells[0].lantern = top
        game.state.adventure?.lanterns?.cells[center].lantern = top
        let r = game.moveLantern(from: 0, to: center)!
        XCTAssertTrue(r.sky)
        XCTAssertNil(game.adventure!.lanterns!.cells[center].lantern, "улетел в небо")
        XCTAssertGreaterThanOrEqual(r.points, Lanterns.skyPoints)
    }

    func testLastDarkCellStartsNewNight() {
        let (game, _) = makeGame()
        plain(game)
        for i in game.state.adventure!.lanterns!.cells.indices where i != center { game.state.adventure?.lanterns?.cells[i].lit = true }
        let chests = game.state.pendingChests.count + game.state.cells.filter { if case .chest? = $0 { return true } else { return false } }.count
        let r = game.hangLantern(center)!
        XCTAssertTrue(r.nightDone)
        XCTAssertTrue(r.prizes.contains(Lanterns.nightPrize))
        let after = game.state.pendingChests.count + game.state.cells.filter { if case .chest? = $0 { return true } else { return false } }.count
        XCTAssertGreaterThan(after, chests)
        let s = game.adventure!.lanterns!
        XCTAssertEqual(s.nights, 1)
        XCTAssertEqual(s.darkLeft, LanternsState.size)
        XCTAssertTrue(s.cells.allSatisfy { $0.lantern == nil })
    }

    func testLanternsSurviveSave() throws {
        let (game, clock) = makeGame()
        _ = game.hangLantern(3)
        let data = try JSONEncoder().encode(game.state)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        let restored = Game(state: decoded, seed: 1, now: { clock.date })
        XCTAssertEqual(restored.adventure?.lanterns, game.adventure?.lanterns)
    }

    /// Бот играет ночи фонарей за всю игру: дорожка заметно, но не целиком, без перекоса в экономике.
    func testLanternsBalance() {
        for seed in UInt64(1)...2 {
            var config = SimConfig()
            config.seed = seed
            let r = Simulator.run(config)
            let ls = zip(r.adventureKinds, r.adventureProgress).filter { $0.0 == .lanterns }.map(\.1)
            let avg = ls.reduce(0, +) / Double(max(1, ls.count))
            let pts = zip(r.adventureKinds, r.adventurePoints).filter { $0.0 == .lanterns }.map(\.1)
            print("Фонари \(seed): событий \(ls.count), дорожка \(Int(avg * 100))%, очки \(pts), ночей \(r.lanternNights), в небо \(r.lanternSky), светлячков \(r.lanternFireflies), ценность \(Int(r.adventureValue)) из энергии \(r.energySpent), дней \(String(format: "%.1f", r.days))")
            XCTAssertGreaterThanOrEqual(ls.count, 1)
            XCTAssertGreaterThan(avg, 0.4)
            XCTAssertLessThan(avg, 1.0)
            XCTAssertLessThan(Double(r.adventureValue), Double(r.energySpent) * 0.15)
        }
    }
}
