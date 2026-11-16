import XCTest
@testable import HearthCore

/// Кувшин светлячков: энергия сверх максимума не сгорает, а медленно копится.
final class JarTests: XCTestCase {
    private var clock: TestClock!

    override func setUp() {
        super.setUp()
        clock = TestClock()
    }

    private func makeGame() -> Game {
        let clock = self.clock!
        return Game(seed: 3, now: { clock.date })
    }

    func testOverflowGoesToJarAtSlowerRate() {
        let game = makeGame()
        let b = game.balance
        game.testSetEnergy(b.energyMax - 2)
        // 2 единицы до полной и еще 3 шага кувшина
        clock.advance(b.energyRegen * 2 + b.energyRegen * b.jarSlowdown * 3 + 1)
        game.refreshEnergy()
        XCTAssertEqual(game.state.energy, b.energyMax)
        XCTAssertEqual(game.state.jarEnergy, 3)
    }

    func testJarStopsAtCapacity() {
        let game = makeGame()
        game.testSetEnergy(game.balance.energyMax)
        clock.advance(100 * 24 * 3600)
        game.refreshEnergy()
        XCTAssertEqual(game.state.jarEnergy, game.balance.jarCapacity)
    }

    func testRefreshIsIdempotentInSmallSteps() {
        // много коротких обновлений дают то же, что одно длинное: время не теряется
        let a = makeGame(), b = makeGame()
        a.testSetEnergy(a.balance.energyMax - 5)
        b.testSetEnergy(b.balance.energyMax - 5)
        for _ in 0..<500 {
            clock.advance(37)
            a.refreshEnergy()
        }
        b.refreshEnergy()
        XCTAssertEqual(a.state.energy, b.state.energy)
        XCTAssertEqual(a.state.jarEnergy, b.state.jarEnergy)
    }

    func testFreeOpenHasCooldown() {
        let game = makeGame()
        game.testSetEnergy(10)
        game.testSetJar(25)
        XCTAssertNil(game.jarFreeIn)
        XCTAssertEqual(game.openJar(), 25)
        XCTAssertEqual(game.state.energy, 35)
        XCTAssertEqual(game.state.jarEnergy, 0)
        game.testSetJar(10)
        XCTAssertEqual(game.openJar(), 0, "второй раз бесплатно нельзя")
        XCTAssertNotNil(game.jarFreeIn)
        XCTAssertEqual(game.openJar(paid: true), 10, "за рекламу или VIP можно сразу")
        clock.advance(game.balance.jarCooldown + 1)
        game.refreshEnergy()
        game.testSetJar(4)
        XCTAssertEqual(game.openJar(), 4)
    }

    func testJarCanExceedEnergyMax() {
        let game = makeGame()
        game.testSetEnergy(game.balance.energyMax)
        game.testSetJar(30)
        game.openJar()
        XCTAssertEqual(game.state.energy, game.balance.energyMax + 30)
    }

    func testEmptyJarDoesNotStartCooldown() {
        let game = makeGame()
        game.testSetEnergy(10)
        XCTAssertEqual(game.openJar(), 0)
        XCTAssertNil(game.jarFreeIn)
    }

    func testJarSurvivesSave() throws {
        let game = makeGame()
        game.testSetJar(12)
        game.testSetEnergy(10)
        game.openJar()
        let data = try JSONEncoder().encode(game.state)
        let state = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(state.jarOpenedAt, game.state.jarOpenedAt)
        XCTAssertEqual(state.jarEnergy, 0)
    }
}
