import XCTest
@testable import HearthCore

final class IslandTests: XCTestCase {
    /// Понедельник недели, когда идет «Остров».
    private func makeGame() -> (Game, TestClock) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let clock = TestClock()
        let game = Game(seed: 5, now: { clock.date })
        game.state.level = 10
        var date = cal.date(from: DateComponents(year: 2027, month: 1, day: 18, hour: 12))!
        while game.adventureSchedule(at: date)?.kind != .island {
            date = cal.date(byAdding: .day, value: 7, to: date)!
        }
        clock.date = date
        XCTAssertEqual(game.adventure?.kind, .island)
        return (game, clock)
    }

    private let w = IslandState.cols
    private var center: Int { (IslandState.rows / 2) * w + w / 2 }

    /// Чистый берег без предметов: удобно раскладывать руками.
    private func clean(_ game: Game) {
        for i in game.state.adventure!.island!.cells.indices { game.state.adventure?.island?.cells[i].item = nil }
    }

    func testMergeCounts() {
        XCTAssertEqual(Island.mergeCounts(2).made, 0)
        XCTAssertEqual(Island.mergeCounts(3).made, 1)
        XCTAssertEqual(Island.mergeCounts(4).used, 3)
        XCTAssertEqual(Island.mergeCounts(5).made, 2)
        XCTAssertEqual(Island.mergeCounts(5).used, 5)
        XCTAssertEqual(Island.mergeCounts(8).made, 3)
        XCTAssertEqual(Island.mergeCounts(10).made, 4)
        // пять в два выгоднее, чем дважды по три
        XCTAssertGreaterThan(Double(Island.mergeCounts(5).made) / 5, Double(Island.mergeCounts(3).made) / 3)
    }

    func testRotationAlternates() {
        let (game, clock) = makeGame()
        XCTAssertEqual(game.adventure?.kind, .island)
        var seen: [AdventureKind] = []
        for _ in AdventureKind.rotation {
            clock.advance(7 * 86_400)
            seen.append(game.adventure!.kind)
        }
        XCTAssertEqual(Set(seen), Set(AdventureKind.rotation), "за круг идут все события")
        XCTAssertEqual(seen.last, .island)
        XCTAssertNotNil(game.adventure?.island)
    }

    func testMapIsSharedAndHasShore() {
        let a = IslandState.generate(seed: 42), b = IslandState.generate(seed: 42)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.cells.filter { !$0.fog }.count, 13)
        XCTAssertEqual(a.cells.compactMap(\.item).count, 3)
        for n in 0..<3 { XCTAssertTrue(a.cells.contains { $0.fog && $0.secret == .treasure(n) }) }
    }

    func testThreeMergeIntoOneAndClearFog() {
        let (game, _) = makeGame()
        clean(game)
        let flower = Item(chain: Island.chains[0], tier: 0)
        // ряд над центром у самого тумана: center-2w, справа и слева
        let top = center - 2 * w
        game.state.adventure?.island?.cells[top].item = flower
        game.state.adventure?.island?.cells[top + w].item = flower
        game.state.adventure?.island?.cells[center + 1].item = flower
        let fogBefore = game.adventure!.island!.fogLeft
        let r = game.moveOnIsland(from: center + 1, to: center)!
        XCTAssertEqual(r.merges.count, 1)
        XCTAssertEqual(r.merges[0].made, 1)
        let items = game.adventure!.island!.cells.compactMap(\.item)
        XCTAssertEqual(items.filter { $0 == Item(chain: flower.chain, tier: 1) }.count, 1)
        XCTAssertFalse([top, top + w, center, center + 1].contains { game.adventure!.island!.cells[$0].item == flower })
        XCTAssertEqual(game.adventure!.island!.cells[center].item, Item(chain: flower.chain, tier: 1), "новый встает куда положили")
        XCTAssertFalse(r.cleared.isEmpty, "слияние у края очищает туман")
        XCTAssertLessThan(game.adventure!.island!.fogLeft, fogBefore)
        XCTAssertGreaterThan(game.adventure!.points, 0)
    }

    func testFiveMergeIntoTwo() {
        let (game, _) = makeGame()
        clean(game)
        let gem = Item(chain: Island.chains[1], tier: 0)
        // две пары по бокам от центра и пятый предмет, который их соединит
        for i in [center - 2, center - 1, center + 1, center + 2, center + w] {
            game.state.adventure?.island?.cells[i].item = gem
        }
        let r = game.moveOnIsland(from: center + w, to: center)!
        XCTAssertEqual(r.merges.first?.made, 2)
        // из тумана могли выйти подарки, считаем только то, что получилось из самоцветов
        let items = game.adventure!.island!.cells.compactMap(\.item)
        XCTAssertEqual(items.filter { $0 == Item(chain: gem.chain, tier: 1) }.count, 2)
        let spots = [center - 2, center - 1, center, center + 1, center + 2, center + w]
        XCTAssertFalse(spots.contains { game.adventure!.island!.cells[$0].item == gem })
    }

    func testCascadeAndTopTierBecomesPoints() {
        let (game, _) = makeGame()
        clean(game)
        let top = Item(chain: Island.chains[2], tier: Island.maxTier - 1)
        game.state.adventure?.island?.cells[center - 1].item = top
        game.state.adventure?.island?.cells[center + 1].item = top
        game.state.adventure?.island?.cells[center + w].item = top
        let before = game.adventure!.points
        let r = game.moveOnIsland(from: center + w, to: center)!
        XCTAssertEqual(r.merges.last?.item.tier, Island.maxTier)
        XCTAssertFalse(game.adventure!.island!.cells.contains { $0.item?.tier ?? 0 >= Island.maxTier }, "последняя ступень не занимает место")
        XCTAssertFalse(game.adventure!.island!.cells.contains { $0.item == top })
        XCTAssertGreaterThanOrEqual(game.adventure!.points - before, Island.tierPoints[Island.maxTier])
    }

    func testMovingWithoutMergeOnlyMovesOrSwaps() {
        let (game, _) = makeGame()
        clean(game)
        let a = Item(chain: Island.chains[0], tier: 0), b = Item(chain: Island.chains[1], tier: 0)
        game.state.adventure?.island?.cells[center].item = a
        game.state.adventure?.island?.cells[center + 1].item = b
        let r = game.moveOnIsland(from: center, to: center + 1)!
        XCTAssertTrue(r.merges.isEmpty)
        XCTAssertEqual(game.adventure!.island!.cells[center].item, b)
        XCTAssertEqual(game.adventure!.island!.cells[center + 1].item, a)
        XCTAssertFalse(game.canMoveOnIsland(from: center, to: 0), "в туман нельзя")
        XCTAssertNil(game.moveOnIsland(from: center + 2, to: center), "пустую клетку не двигают")
    }

    func testTideSpendsShellsAndNeedsRoom() {
        let (game, _) = makeGame()
        let moves = game.adventure!.moves
        guard case .placed(let i, let item) = game.tide() else { return XCTFail() }
        XCTAssertEqual(game.adventure!.moves, moves - 1)
        XCTAssertEqual(game.adventure!.island!.cells[i].item, item)
        XCTAssertFalse(game.adventure!.island!.cells[i].fog)
        for j in game.adventure!.island!.freeCells { game.state.adventure?.island?.cells[j].item = Item(chain: "island_gem", tier: 3) }
        XCTAssertEqual(game.tide(), .noRoom)
        XCTAssertTrue(game.washAway(center))
        game.state.adventure?.moves = 0
        XCTAssertEqual(game.tide(), .noMoves)
    }

    func testIslandSurvivesSave() throws {
        let (game, clock) = makeGame()
        _ = game.tide()
        let data = try JSONEncoder().encode(game.state)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(decoded.adventure, game.state.adventure)
        let restored = Game(state: decoded, seed: 1, now: { clock.date })
        XCTAssertEqual(restored.adventure?.island, game.adventure?.island)
    }

    /// Бот играет острова за всю игру: туман заметно расчищается, дорожка проходится не целиком.
    func testIslandBalance() {
        for seed in UInt64(1)...2 {
            let r = SimRuns.standard(seed)
            let island = zip(r.adventureKinds, r.adventureProgress).filter { $0.0 == .island }.map(\.1)
            let depths = zip(r.adventureKinds, r.adventureProgress).filter { $0.0 == .depths }.map(\.1)
            let avg = island.reduce(0, +) / Double(max(1, island.count))
            let fog = Double(r.islandFogLeft.reduce(0, +)) / Double(max(1, r.islandFogLeft.count))
            print("Остров \(seed): событий \(island.count) (глубин \(depths.count)), дорожка \(Int(avg * 100))%, тумана осталось \(String(format: "%.1f", fog)) из 50, слияний \(r.islandMerges), смыто \(r.islandWashed), дней \(String(format: "%.1f", r.days))")
            XCTAssertGreaterThanOrEqual(island.count, 1)
            XCTAssertGreaterThan(avg, 0.4, "дорожка проходится заметно")
            XCTAssertLessThan(avg, 1.0, "но не вся без усилий")
            XCTAssertLessThan(Double(r.adventureValue), Double(r.energySpent) * 0.15, "без имбы")
        }
    }
}
