import XCTest
@testable import HearthCore

final class SeasonTests: XCTestCase {
    func testSeasonsByMonth() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let expected: [Season] = [.winter, .winter, .spring, .spring, .spring, .summer,
                                  .summer, .summer, .autumn, .autumn, .autumn, .winter]
        for (i, season) in expected.enumerated() {
            let date = cal.date(from: DateComponents(year: 2027, month: i + 1, day: 15))!
            XCTAssertEqual(Season.of(date, calendar: cal), season, "месяц \(i + 1)")
        }
    }

    func testGameSeasonFollowsClock() {
        let clock = TestClock() // 15.01.2027
        let game = Game(seed: 1, now: { clock.date })
        XCTAssertEqual(game.season, .winter)
        clock.advance(120 * 86400)
        XCTAssertEqual(game.season, .spring)
        XCTAssertEqual(Set(Season.allCases.map(\.icon)).count, 4)
    }

    func testFogCoversLockedDistrictsOnly() throws {
        let clock = TestClock()
        let game = Game(seed: 1, now: { clock.date })
        let d = game.village.districts
        XCTAssertEqual(game.nextLockedDistrict?.id, d[1].id)
        let squareTop = try XCTUnwrap(d[0].tasks.map(\.y).min())
        XCTAssertEqual(game.fogRow, Double(squareTop) - 7)
        game.state.stars = 1_000_000
        for _ in 0..<5 { for task in d.flatMap(\.tasks) { _ = game.complete(taskId: task.id) } }
        XCTAssertNil(game.nextLockedDistrict)
        XCTAssertNil(game.fogRow, "все открыто - тумана нет")
    }
}
