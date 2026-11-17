import XCTest
@testable import HearthCore

final class QuestsTests: XCTestCase {
    private func game(at date: Date) -> (Game, SimClock) {
        let clock = SimClock(date)
        return (Game(seed: 7, now: { clock.date }), clock)
    }

    func testThreeDifferentQuestsPerDay() {
        let (g, _) = game(at: Date(timeIntervalSince1970: 1_800_000_000))
        let qs = g.ensureQuests()
        XCTAssertEqual(qs.count, 3)
        XCTAssertEqual(Set(qs.map(\.kind)).count, 3)
        XCTAssertTrue(qs.allSatisfy { $0.target > 0 && $0.progress == 0 })
    }

    func testQuestsResetNextDayAndStayWithinDay() {
        let (g, clock) = game(at: Date(timeIntervalSince1970: 1_800_000_000))
        g.ensureQuests()
        g.progressQuest(g.state.quests[0].kind, by: 2)
        clock.advance(3600)
        g.ensureQuests()
        XCTAssertEqual(g.state.quests[0].progress, 2, "в тот же день прогресс сохраняется")
        clock.advance(86_400)
        g.ensureQuests()
        XCTAssertTrue(g.state.quests.allSatisfy { $0.progress == 0 }, "новый день - новые задания")
    }

    func testClaimOnlyWhenDoneAndOnce() {
        let (g, _) = game(at: Date(timeIntervalSince1970: 1_800_000_000))
        g.ensureQuests()
        XCTAssertNil(g.claimQuest(0))
        let q = g.state.quests[0]
        g.progressQuest(q.kind, by: q.target + 50)
        XCTAssertEqual(g.state.quests[0].progress, q.target, "прогресс не выше цели")
        let gems = g.state.gems, coins = g.state.coins, energy = g.state.energy
        let r = g.claimQuest(0)
        XCTAssertNotNil(r)
        XCTAssertEqual(g.state.gems, gems + (r?.gems ?? 0))
        XCTAssertEqual(g.state.coins, coins + (r?.coins ?? 0))
        XCTAssertEqual(g.state.energy, energy + (r?.energy ?? 0))
        XCTAssertNil(g.claimQuest(0), "второй раз не дают")
    }

    func testChestNeedsAllThree() {
        let (g, _) = game(at: Date(timeIntervalSince1970: 1_800_000_000))
        g.ensureQuests()
        for (i, q) in g.state.quests.enumerated() {
            XCTAssertNil(g.claimQuestChest())
            g.progressQuest(q.kind, by: q.target)
            XCTAssertNotNil(g.claimQuest(i))
        }
        XCTAssertEqual(g.questsClaimable, 1)
        XCTAssertNotNil(g.claimQuestChest())
        XCTAssertNil(g.claimQuestChest())
        XCTAssertEqual(g.questsClaimable, 0)
    }

    func testSpawnAndMergeCountTowardQuests() {
        let (g, _) = game(at: Date(timeIntervalSince1970: 1_800_000_000))
        g.ensureQuests()
        g.testSetEnergy(50)
        let gen = g.state.cells.firstIndex { if case .generator? = $0 { return true } else { return false } }!
        guard case .spawned = g.spawn(from: gen) else { return XCTFail("генератор выдал предмет") }
        if let i = g.state.quests.firstIndex(where: { $0.kind == .spawn }) {
            XCTAssertEqual(g.state.quests[i].progress, 1)
        }
        let a = Item(chain: "garden", tier: 0)
        g.testSet(0, .item(a)); g.testSet(1, .item(a))
        _ = g.move(from: 0, to: 1)
        if let i = g.state.quests.firstIndex(where: { $0.kind == .merge }) {
            XCTAssertEqual(g.state.quests[i].progress, 1)
        }
    }

    func testCollectionDiscoversAndPaysOnce() {
        let (g, _) = game(at: Date(timeIntervalSince1970: 1_800_000_000))
        let top = Item(chain: "garden", tier: 4)
        XCTAssertFalse(g.isDiscovered(top))
        let a = Item(chain: "garden", tier: 3)
        g.testSet(0, .item(a)); g.testSet(1, .item(a))
        _ = g.move(from: 0, to: 1)
        XCTAssertTrue(g.isDiscovered(top))
        XCTAssertEqual(g.lastDiscovery, top)
        let gems = g.state.gems
        let r = g.claimDiscovery(top)
        XCTAssertEqual(r, g.balance.discoveryReward(top))
        XCTAssertEqual(g.state.gems, gems + (r?.gems ?? 0))
        XCTAssertNil(g.claimDiscovery(top))
    }

    func testOldSavesDoNotGetCollectionWindfall() {
        var state = Game(seed: 1).state
        state.bestTier = ["garden": 4, "forest": 2]
        state.discovered = []
        let g = Game(state: state, seed: 2)
        XCTAssertTrue(g.isDiscovered(Item(chain: "garden", tier: 4)))
        XCTAssertNil(g.claimDiscovery(Item(chain: "garden", tier: 4)), "уже собранное не оплачивается заново")
    }
}
