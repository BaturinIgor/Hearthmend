import XCTest
@testable import HearthCore

final class EventTests: XCTestCase {
    private var clock: TestClock!

    override func setUp() {
        super.setUp()
        clock = TestClock() // 15.01.2027 08:00 UTC, пятница
    }

    private func makeGame() -> Game {
        let clock = self.clock!
        return Game(seed: 9, now: { clock.date })
    }

    func testEventsDataIsConsistent() {
        for def in EventsDef.bundled.events {
            XCTAssertEqual(def.choices.count, 2, def.id)
            let tokens = def.milestones.map(\.tokens)
            XCTAssertEqual(tokens, tokens.sorted(), "\(def.id): ступени по возрастанию")
            XCTAssertEqual(Set(tokens).count, tokens.count)
            XCTAssertEqual(def.milestones.filter { $0.choiceDecor == true }.count, 1, def.id)
        }
    }

    func testEventRunsFridayToSunday() {
        let game = makeGame()
        XCTAssertNotNil(game.activeEvent, "пятница")
        clock.advance(2 * 86400)
        XCTAssertNotNil(game.activeEvent, "воскресенье")
        clock.advance(86400)
        XCTAssertNil(game.activeEvent, "понедельник")
        clock.advance(3 * 86400)
        XCTAssertNil(game.activeEvent, "четверг")
        clock.advance(86400)
        XCTAssertNotNil(game.activeEvent, "снова пятница")
    }

    func testEventEndsAtMidnightAfterSunday() throws {
        let game = makeGame()
        let ends = try XCTUnwrap(game.eventEndsAt)
        let cal = Game.eventCalendar
        XCTAssertEqual(cal.component(.weekday, from: ends), 2, "кончается в начале понедельника")
        XCTAssertEqual(cal.component(.hour, from: ends), 0)
    }

    func testNextWeekIsNewEventWithReset() {
        let game = makeGame()
        let first = game.activeEvent!.id
        game.addEventTokens(30)
        clock.advance(7 * 86400)
        let second = game.activeEvent!.id
        XCTAssertNotEqual(first, second, "события чередуются")
        XCTAssertEqual(game.state.eventTokens, 0)
        XCTAssertEqual(game.state.eventClaimed, 0)
    }

    func testTokensFromOrdersOnlyDuringEvent() {
        let game = makeGame()
        let item = Item(chain: "garden", tier: 1)
        game.testSet(0, .item(item))
        game.testSetOrders([Order(id: 900, needs: [item], coins: 6, stars: 3, xp: 1)])
        game.deliver(orderId: 900)
        XCTAssertEqual(game.state.eventTokens, 3)
        clock.advance(4 * 86400) // вторник
        game.testSet(0, .item(item))
        game.testSetOrders([Order(id: 901, needs: [item], coins: 6, stars: 3, xp: 1)])
        game.deliver(orderId: 901)
        XCTAssertNil(game.activeEvent)
        XCTAssertEqual(game.state.eventTokens, 3, "ленточки не копятся вне события")
    }

    func testMilestonesGiveRewardsInOrder() {
        let game = makeGame()
        let def = game.activeEvent!
        let gems = game.state.gems, energy = game.state.energy, coins = game.state.coins
        let rewards = game.addEventTokens(def.milestones[2].tokens)
        XCTAssertEqual(rewards.count, 3)
        XCTAssertEqual(game.state.eventClaimed, 3)
        let sum = def.milestones.prefix(3)
        XCTAssertEqual(game.state.gems, gems + sum.reduce(0) { $0 + ($1.gems ?? 0) })
        XCTAssertEqual(game.state.energy, energy + sum.reduce(0) { $0 + ($1.energy ?? 0) })
        XCTAssertEqual(game.state.coins, coins + sum.reduce(0) { $0 + ($1.coins ?? 0) })
    }

    func testChoiceMilestoneWaitsForChoice() {
        let game = makeGame()
        let def = game.activeEvent!
        let choiceIndex = def.milestones.firstIndex { $0.choiceDecor == true }!
        game.addEventTokens(def.maxTokens)
        XCTAssertEqual(game.state.eventClaimed, choiceIndex, "дальше без выбора не идет")
        XCTAssertTrue(game.eventNeedsChoice)
        XCTAssertTrue(game.chooseEvent("nobody").isEmpty)
        let rewards = game.chooseEvent(def.choices[1].id)
        XCTAssertEqual(rewards.first?.decor, def.choices[1].decor)
        XCTAssertEqual(game.state.eventClaimed, def.milestones.count)
        XCTAssertFalse(game.eventNeedsChoice)
        XCTAssertTrue(game.chooseEvent(def.choices[0].id).isEmpty, "выбор один раз")
        XCTAssertEqual(game.state.decorOwned[def.choices[1].decor], 1 + (def.milestones.contains { $0.decor == def.choices[1].decor } ? 1 : 0))
    }

    func testTokensCappedAtTrackEnd() {
        let game = makeGame()
        let def = game.activeEvent!
        game.chooseEvent(def.choices[0].id)
        game.addEventTokens(def.maxTokens * 5)
        XCTAssertEqual(game.state.eventTokens, def.maxTokens)
        XCTAssertTrue(game.addEventTokens(10).isEmpty, "награды не выдаются второй раз")
    }

    func testDecorPlacementMoveAndStore() {
        let game = makeGame()
        game.state.decorOwned["decor_torch"] = 1
        XCTAssertNil(game.placeDecor("decor_bench", x: 3, y: 3), "нет в запасе")
        let placed = game.placeDecor("decor_torch", x: 100, y: -5)!
        XCTAssertEqual(placed.x, Game.mapSize.width - 0.5, "не за краем карты")
        XCTAssertEqual(placed.y, 1)
        XCTAssertNil(game.state.decorOwned["decor_torch"])
        game.moveDecor(id: placed.id, x: 10, y: 20)
        XCTAssertEqual(game.state.placedDecor.first?.x, 10)
        game.storeDecor(id: placed.id)
        XCTAssertTrue(game.state.placedDecor.isEmpty)
        XCTAssertEqual(game.state.decorOwned["decor_torch"], 1)
    }

    func testEventStateSurvivesSave() throws {
        let game = makeGame()
        game.addEventTokens(12)
        game.state.decorOwned["decor_torch"] = 1
        game.placeDecor("decor_torch", x: 5, y: 6)
        let state = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(game.state))
        XCTAssertEqual(state.eventTokens, 12)
        XCTAssertEqual(state.placedDecor, game.state.placedDecor)
        XCTAssertEqual(state.nextDecorId, game.state.nextDecorId)
    }
}
