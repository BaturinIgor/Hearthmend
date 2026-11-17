import XCTest
@testable import HearthCore

/// Животные деревни: берутся за монеты в открытых районах и раз в день дарят подарок.
final class PetsTests: XCTestCase {
    private var clock: TestClock!

    override func setUp() {
        super.setUp()
        clock = TestClock()
    }

    private func makeGame() -> Game {
        let clock = self.clock!
        return Game(seed: 3, now: { clock.date })
    }

    private func openDistricts(_ g: Game, upTo id: String) {
        for d in g.village.districts {
            if d.id == id { break }
            for t in d.tasks where !g.state.completedTasks.contains(t.id) { g.state.completedTasks.append(t.id) }
        }
    }

    func testEveryPetLivesInARealDistrict() {
        let g = makeGame()
        let ids = Set(g.village.districts.map(\.id))
        for pet in Pets.all {
            XCTAssertTrue(ids.contains(pet.district), pet.id)
            XCTAssertGreaterThan(pet.cost, 0)
        }
        XCTAssertEqual(Set(Pets.all.map(\.id)).count, Pets.all.count)
        XCTAssertEqual(Pets.all.map(\.cost), Pets.all.map(\.cost).sorted(), "чем дальше, тем дороже")
    }

    func testPetNeedsOpenDistrictAndCoins() {
        let g = makeGame()
        g.state.coins = 100_000
        XCTAssertFalse(g.petAvailable("chicken"), "хутор еще закрыт")
        XCTAssertFalse(g.adoptPet("chicken"))
        openDistricts(g, upTo: "farmstead")
        XCTAssertTrue(g.petAvailable("chicken"))
        g.state.coins = 599
        XCTAssertFalse(g.adoptPet("chicken"))
        g.state.coins = 600
        XCTAssertTrue(g.adoptPet("chicken"))
        XCTAssertEqual(g.state.coins, 0)
        XCTAssertFalse(g.adoptPet("chicken"), "второй раз ту же курицу не взять")
        XCTAssertEqual(g.state.petsOwned, ["chicken"])
    }

    func testGiftOncePerDay() {
        let g = makeGame()
        openDistricts(g, upTo: "farmstead")
        g.state.coins = 600
        XCTAssertTrue(g.adoptPet("chicken"))
        XCTAssertEqual(g.petGiftsReady, 1, "в первый день подарок уже ждет")
        let energy = g.state.energy
        XCTAssertEqual(g.collectPet("chicken")?.energy, 4)
        XCTAssertEqual(g.state.energy, energy + 4)
        XCTAssertNil(g.collectPet("chicken"))
        clock.advance(86_400)
        XCTAssertTrue(g.petGiftReady("chicken"))
        XCTAssertNotNil(g.collectPet("chicken"))
    }

    func testPetsSurviveSaveAndCountForAchievements() throws {
        let g = makeGame()
        openDistricts(g, upTo: "farmstead")
        g.state.coins = 600
        g.adoptPet("chicken")
        let back = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(g.state))
        XCTAssertEqual(back.petsOwned, ["chicken"])
        XCTAssertEqual(g.achievementTier(.pets), 1)
    }

    func testDailyPetGiftsAreSmall() {
        // все животные вместе за день: меньше 6% дневной энергии и не больше 10 кристаллов
        let b = Balance()
        let energy = Pets.all.reduce(0) { $0 + $1.gift.energy }
        let gems = Pets.all.reduce(0) { $0 + $1.gift.gems }
        XCTAssertLessThan(Double(energy), 86_400 / b.energyRegen * 0.06)
        XCTAssertLessThanOrEqual(gems, 10)
    }
}
