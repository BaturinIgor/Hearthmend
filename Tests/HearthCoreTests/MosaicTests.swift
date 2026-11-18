import XCTest
@testable import HearthCore

final class MosaicTests: XCTestCase {
    /// Понедельник недели, когда идет «Витраж».
    private func makeGame() -> (Game, TestClock) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let clock = TestClock()
        clock.date = cal.date(from: DateComponents(year: 2027, month: 1, day: 18, hour: 12))!
        let game = Game(seed: 7, now: { clock.date })
        game.state.level = 10
        while game.adventureSchedule(at: clock.date)?.kind != .mosaic { clock.advance(7 * 86_400) }
        XCTAssertNotNil(game.adventure?.mosaic)
        return (game, clock)
    }

    private func glass(_ color: Int, _ tier: Int = 0) -> Item { Item(chain: Mosaic.chains[color], tier: tier) }

    func testBiggerPieceCoversMoreThanTwoSmaller() {
        for t in 1...Mosaic.maxTier {
            XCTAssertGreaterThan(Mosaic.cover[t], Mosaic.cover[t - 1] * 2)
        }
    }

    func testEveryTrackGrows() {
        let (game, _) = makeGame()
        for kind in AdventureKind.rotation {
            let track = game.adventureTrack(kind)
            XCTAssertEqual(track.count, 12, "\(kind)")
            XCTAssertEqual(track.map(\.points), track.map(\.points).sorted(), "\(kind)")
            XCTAssertEqual(Set(track.map(\.points)).count, track.count, "\(kind)")
        }
    }

    func testWindowIsSharedAndEveryRegionIsOneColor() {
        let a = MosaicState.generate(seed: 42), b = MosaicState.generate(seed: 42)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a.colors, MosaicState.generate(seed: 42, windows: 1).colors, "следующее окно другое")
        XCTAssertEqual(Set(a.regions).count, MosaicState.regionCount)
        for region in Set(a.regions) {
            let colors = Set(a.regions.indices.filter { a.regions[$0] == region }.map { a.colors[$0] })
            XCTAssertEqual(colors.count, 1)
        }
        XCTAssertGreaterThan(Set(a.colors).count, 1)
        XCTAssertEqual(a.emptyCells, MosaicState.size)
    }

    func testCutSpendsGlassAndNeedsRoom() {
        let (game, _) = makeGame()
        let moves = game.adventure!.moves
        guard case .cut(let slot, let item) = game.cutGlass() else { return XCTFail() }
        XCTAssertEqual(game.adventure!.moves, moves - 1)
        XCTAssertEqual(game.adventure!.mosaic!.bench[slot], item)
        game.state.adventure?.moves = 100
        while game.adventure!.mosaic!.freeSlots.count > 0 { _ = game.cutGlass() }
        XCTAssertEqual(game.cutGlass(), .noRoom)
        XCTAssertTrue(game.shatterGlass(0))
        game.state.adventure?.moves = 0
        XCTAssertEqual(game.cutGlass(), .noMoves)
    }

    func testMergeAndSwapOnBench() {
        let (game, _) = makeGame()
        game.state.adventure?.mosaic?.bench = [glass(0), glass(0), glass(1), nil, nil, nil]
        XCTAssertTrue(game.canMergeGlass(0, 1))
        XCTAssertFalse(game.canMergeGlass(0, 2))
        XCTAssertTrue(game.moveGlass(from: 0, to: 1))
        XCTAssertEqual(game.adventure!.mosaic!.bench[1], glass(0, 1))
        XCTAssertNil(game.adventure!.mosaic!.bench[0])
        XCTAssertTrue(game.moveGlass(from: 2, to: 4))
        XCTAssertEqual(game.adventure!.mosaic!.bench[4], glass(1))
        XCTAssertFalse(game.moveGlass(from: 3, to: 5), "с пустой ячейки нечего переносить")
        game.state.adventure?.mosaic?.bench = [glass(2, Mosaic.maxTier), glass(2, Mosaic.maxTier), nil, nil, nil, nil]
        XCTAssertFalse(game.canMergeGlass(0, 1), "больше последней ступени не бывает")
    }

    func testPieceFillsOnlyItsColorAndRegion() {
        let (game, _) = makeGame()
        let m = game.adventure!.mosaic!
        let cell = 0, color = m.colors[0], region = m.regions[0]
        let other = (color + 1) % Mosaic.colorCount
        game.state.adventure?.mosaic?.bench = [glass(other), glass(color, 1), nil, nil, nil, nil]
        XCTAssertFalse(game.canSetGlass(slot: 0, cell: cell), "чужой цвет не ложится")
        XCTAssertNil(game.setGlass(slot: 0, cell: cell))
        let size = m.regionSize(region)
        let r = game.setGlass(slot: 1, cell: cell)!
        XCTAssertEqual(r.cells.count, min(size, Mosaic.cover[1]))
        XCTAssertTrue(r.cells.contains(cell), "ближайшая клетка - та, куда положили")
        XCTAssertTrue(r.cells.allSatisfy { m.regions[$0] == region })
        XCTAssertEqual(r.regionDone, size <= Mosaic.cover[1])
        XCTAssertGreaterThan(game.adventure!.points, 0)
        XCTAssertNil(game.adventure!.mosaic!.bench[1])
        XCTAssertFalse(game.canSetGlass(slot: 0, cell: cell), "на занятую клетку не кладут")
    }

    func testFinishingRegionGivesBonusAndWasteIsCounted() {
        let (game, _) = makeGame()
        let m = game.adventure!.mosaic!
        // самая маленькая область, чтобы кусочек точно ее закрыл
        let region = Set(m.regions).min { (m.regionSize($0), $0) < (m.regionSize($1), $1) }!
        let size = m.regionSize(region), cell = m.regions.firstIndex(of: region)!
        XCTAssertLessThan(size, Mosaic.cover[Mosaic.maxTier])
        game.state.adventure?.mosaic?.bench = [glass(m.colors[cell], Mosaic.maxTier), nil, nil, nil, nil, nil]
        let r = game.setGlass(slot: 0, cell: cell)!
        XCTAssertTrue(r.regionDone)
        XCTAssertEqual(r.cells.count, size)
        XCTAssertEqual(r.wasted, Mosaic.cover[Mosaic.maxTier] - size)
        XCTAssertEqual(r.points, size * Mosaic.cellPoints + size * Mosaic.regionPoints)
    }

    func testFullWindowGivesChestAndNewWindowKeepsBench() {
        let (game, _) = makeGame()
        let m = game.adventure!.mosaic!
        // заполняет все, кроме одной клетки
        for i in 1..<MosaicState.size { game.state.adventure?.mosaic?.filled[i] = true }
        let keep = glass(3, 2)
        game.state.adventure?.mosaic?.bench = [glass(m.colors[0]), keep, nil, nil, nil, nil]
        let chests = game.state.pendingChests.count + game.state.cells.filter { if case .chest? = $0 { return true } else { return false } }.count
        let r = game.setGlass(slot: 0, cell: 0)!
        XCTAssertTrue(r.windowDone)
        XCTAssertTrue(r.prizes.contains(Mosaic.windowPrize))
        let after = game.state.pendingChests.count + game.state.cells.filter { if case .chest? = $0 { return true } else { return false } }.count
        XCTAssertGreaterThan(after, chests)
        let next = game.adventure!.mosaic!
        XCTAssertEqual(next.windows, 1)
        XCTAssertEqual(next.emptyCells, MosaicState.size)
        XCTAssertEqual(next.bench[1], keep)
        XCTAssertNil(next.bench[0])
    }

    func testCutPrefersColorsStillNeeded() {
        let (game, _) = makeGame()
        // остался пустым только один цвет
        let m = game.adventure!.mosaic!
        let color = m.colors[0]
        for i in m.filled.indices where m.colors[i] != color { game.state.adventure?.mosaic?.filled[i] = true }
        game.state.adventure?.moves = 400
        var hits = 0
        for _ in 0..<200 {
            if case .cut(let slot, let item) = game.cutGlass() {
                if MosaicState.color(of: item) == color { hits += 1 }
                game.shatterGlass(slot)
            }
        }
        XCTAssertGreaterThan(hits, 70, "нужный цвет выпадает заметно чаще четверти")
    }

    func testMosaicSurvivesSave() throws {
        let (game, clock) = makeGame()
        _ = game.cutGlass()
        let data = try JSONEncoder().encode(game.state)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        let restored = Game(state: decoded, seed: 1, now: { clock.date })
        XCTAssertEqual(restored.adventure?.mosaic, game.adventure?.mosaic)
    }

    /// Бот играет витражи за всю игру: дорожка проходится заметно, но не целиком, без перекоса в экономике.
    func testMosaicBalance() {
        for seed in UInt64(1)...2 {
            let r = SimRuns.standard(seed)
            let ms = zip(r.adventureKinds, r.adventureProgress).filter { $0.0 == .mosaic }.map(\.1)
            let avg = ms.reduce(0, +) / Double(max(1, ms.count))
            let pts = zip(r.adventureKinds, r.adventurePoints).filter { $0.0 == .mosaic }.map(\.1)
            print("Витраж \(seed): событий \(ms.count), дорожка \(Int(avg * 100))%, очки \(pts), окон \(r.mosaicWindows), потеряно клеток \(r.mosaicWasted), разбито \(r.mosaicShattered), ценность \(Int(r.adventureValue)) из энергии \(r.energySpent), дней \(String(format: "%.1f", r.days))")
            XCTAssertGreaterThanOrEqual(ms.count, 1)
            XCTAssertGreaterThan(avg, 0.4)
            XCTAssertLessThan(avg, 1.0)
            XCTAssertLessThan(Double(r.adventureValue), Double(r.energySpent) * 0.15)
        }
    }
}
