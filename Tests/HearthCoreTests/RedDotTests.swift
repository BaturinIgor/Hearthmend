import XCTest
@testable import HearthCore

/// Красные точки: новое украшение помечается, пока игрок не заглянул в запас деревни.
final class RedDotTests: XCTestCase {
    func testNewDecorLightsDotUntilSeen() throws {
        let game = Game(seed: 3)
        XCTAssertFalse(game.state.newDecor)
        game.grantAdventurePrize(.decor("decor_lily"))
        XCTAssertTrue(game.state.newDecor)
        XCTAssertEqual(game.state.decorOwned["decor_lily"], 1)
        // переживает сохранение
        let data = try JSONEncoder().encode(game.state)
        XCTAssertTrue(try JSONDecoder().decode(GameState.self, from: data).newDecor)
        game.seeNewDecor()
        XCTAssertFalse(game.state.newDecor)
    }

    func testStoringPlacedDecorDoesNotLightDot() {
        let game = Game(seed: 3)
        game.grantAdventurePrize(.decor("decor_lily"))
        game.seeNewDecor()
        guard let placed = game.placeDecor("decor_lily", x: 0.5, y: 0.5) else { return XCTFail() }
        game.storeDecor(id: placed.id)
        XCTAssertFalse(game.state.newDecor, "убрал сам - ничего нового")
        XCTAssertEqual(game.state.decorOwned["decor_lily"], 1)
    }

    func testOldSavesDecodeWithoutDot() throws {
        let game = Game(seed: 3)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(game.state)) as! [String: Any]
        json.removeValue(forKey: "newDecor")
        let data = try JSONSerialization.data(withJSONObject: json)
        XCTAssertFalse(try JSONDecoder().decode(GameState.self, from: data).newDecor)
    }
}

/// Кадры событий для проверки интерфейса: демо-часы попадают в нужное событие, бот делает ходы.
final class AdventureDemoTests: XCTestCase {
    func testDemoClockLandsOnEveryEvent() {
        for kind in AdventureKind.rotation {
            let game = Game.demo(now: Game.demoClock(adventure: kind))
            game.state.level = max(game.state.level, Balance.adventureLevel)
            XCTAssertEqual(game.adventure?.kind, kind)
            Simulator.demoAdventure(game)
            XCTAssertEqual(game.adventure?.moves, 12, "\(kind)")
            let a = game.adventure!
            let touched = a.points > 0 || a.greenhouse?.beds.contains { $0 != nil } == true
            XCTAssertTrue(touched, "\(kind): на экране есть ходы бота")
        }
    }
}
