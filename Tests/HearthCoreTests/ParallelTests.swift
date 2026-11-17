import XCTest
@testable import HearthCore

/// Параллельные линии: дружба с жителями, странствующий торговец и достижения.
final class ParallelTests: XCTestCase {
    private var clock: TestClock!

    override func setUp() {
        super.setUp()
        clock = TestClock()
    }

    private func makeGame() -> Game {
        let clock = self.clock!
        return Game(seed: 3, now: { clock.date })
    }

    /// Ставит предметы на свободные клетки поля.
    private func put(_ items: [Item], in game: Game) {
        var free = game.state.cells.indices.filter { game.state.cells[$0] == nil }
        for item in items {
            let i = free.removeFirst()
            game.testSet(i, .item(item))
        }
    }

    // MARK: - Дружба

    func testEveryChainHasAResident() {
        let g = makeGame()
        for chain in g.catalog.chains {
            XCTAssertNotNil(Friends.byChain[chain.id], chain.id)
        }
        XCTAssertEqual(Set(Friends.byChain.values), Set(Friends.all))
    }

    func testDeliveryAddsHeartToRequester() {
        let g = makeGame()
        let item = Item(chain: "forest", tier: 1)
        g.testSetOrders([Order(id: 900, needs: [item], coins: 6, stars: 1, xp: 2)])
        put([item], in: g)
        XCTAssertNotNil(g.deliver(orderId: 900))
        XCTAssertEqual(g.friendHearts("jack"), 1)
        XCTAssertEqual(g.friendHearts("tim"), 0)
    }

    func testFriendLevelsAndGiftsInOrder() {
        let g = makeGame()
        XCTAssertEqual(g.friendLevel("tim"), 0)
        XCTAssertNil(g.claimFriend("tim"))
        g.state.friendHearts["tim"] = 10
        XCTAssertEqual(g.friendLevel("tim"), 2)
        XCTAssertEqual(g.friendsClaimable, 2)
        let coins = g.state.coins
        XCTAssertEqual(g.claimFriend("tim")?.coins, 150)
        XCTAssertEqual(g.state.coins, coins + 150)
        XCTAssertEqual(g.claimFriend("tim")?.energy, 25)
        XCTAssertNil(g.claimFriend("tim"))
        XCTAssertEqual(g.friendsClaimable, 0)
        XCTAssertEqual(g.friendProgress("tim")?.have, 0)
        XCTAssertEqual(g.friendProgress("tim")?.need, 15)
    }

    func testBestFriendGivesPersonalDecor() {
        let g = makeGame()
        g.state.friendHearts["mila"] = 100
        for _ in 1...4 { XCTAssertNotNil(g.claimFriend("mila")) }
        let last = g.claimFriend("mila")
        XCTAssertEqual(last?.decor, "decor_friend_mila")
        XCTAssertEqual(g.state.decorOwned["decor_friend_mila"], 1)
        XCTAssertNil(g.friendProgress("mila"))
        XCTAssertEqual(g.bestFriends, 1)
    }

    func testFriendGiftsAreSmall() {
        // все подарки всех жителей вместе: кристаллов меньше, чем стоит один большой набор
        var gems = 0, energy = 0
        for r in Friends.all {
            for level in 1...Friends.maxLevel {
                gems += Friends.reward(level: level, resident: r).gems
                energy += Friends.reward(level: level, resident: r).energy
            }
        }
        XCTAssertLessThanOrEqual(gems, 250)
        XCTAssertLessThanOrEqual(energy, 600)
    }

    // MARK: - Торговец

    func testMerchantComesOnlyFromItsLevel() {
        let g = makeGame()
        g.testSetLevel(Balance.merchantLevel - 1)
        XCTAssertFalse(g.updateMerchant())
        XCTAssertNil(g.state.merchant)
        g.testSetLevel(Balance.merchantLevel)
        XCTAssertTrue(g.updateMerchant())
        let visit = g.state.merchant
        XCTAssertEqual(visit?.needs.count, 3)
        XCTAssertEqual(visit?.leavesAt, clock.date.addingTimeInterval(Balance.merchantStay))
    }

    func testMerchantNeedsAreReachable() {
        let g = makeGame()
        g.testSetLevel(Balance.merchantLevel)
        g.updateMerchant()
        for need in g.state.merchant!.needs {
            XCTAssertTrue(g.state.unlockedChains.contains(need.chain))
            XCTAssertGreaterThanOrEqual(need.tier, 1)
            XCTAssertLessThanOrEqual(need.tier, max(2, g.state.bestTier[need.chain] ?? 1))
        }
    }

    func testMerchantLeavesAndComesBack() {
        let g = makeGame()
        g.testSetLevel(Balance.merchantLevel)
        g.updateMerchant()
        clock.advance(Balance.merchantStay + 1)
        XCTAssertFalse(g.updateMerchant())
        XCTAssertNil(g.state.merchant)
        XCTAssertNotNil(g.merchantArrivesIn)
        clock.advance(Balance.merchantGap)
        XCTAssertTrue(g.updateMerchant())
        XCTAssertNotNil(g.state.merchant)
    }

    func testServingMerchantPaysAndTakesItems() {
        let g = makeGame()
        g.testSetLevel(Balance.merchantLevel)
        g.updateMerchant()
        let visit = g.state.merchant!
        XCTAssertFalse(g.canDeliverMerchant())
        XCTAssertNil(g.deliverMerchant())
        put(visit.needs, in: g)
        let gems = g.state.gems, coins = g.state.coins, stars = g.state.stars
        XCTAssertTrue(g.canDeliverMerchant())
        XCTAssertNotNil(g.deliverMerchant())
        XCTAssertEqual(g.state.gems, gems + visit.gems)
        XCTAssertEqual(g.state.coins, coins + visit.coins)
        XCTAssertEqual(g.state.stars, stars, "торговец не платит звездами")
        XCTAssertEqual(g.state.merchantsServed, 1)
        XCTAssertNil(g.state.merchant)
        for need in visit.needs { XCTAssertFalse(g.state.cells.contains { $0?.item == need }) }
    }

    func testEveryThirdMerchantBringsDecor() {
        let g = makeGame()
        g.testSetLevel(Balance.merchantLevel)
        var decor: [String] = []
        for _ in 0..<6 {
            clock.advance(Balance.merchantGap + 1)
            g.updateMerchant()
            let visit = g.state.merchant!
            put(visit.needs, in: g)
            XCTAssertNotNil(g.deliverMerchant())
            if let d = visit.decor { decor.append(d) }
        }
        XCTAssertEqual(decor, Array(Merchant.decor.prefix(2)))
    }

    func testMerchantCannotBeServedAfterLeaving() {
        let g = makeGame()
        g.testSetLevel(Balance.merchantLevel)
        g.updateMerchant()
        put(g.state.merchant!.needs, in: g)
        clock.advance(Balance.merchantStay + 1)
        XCTAssertNil(g.deliverMerchant())
    }

    func testMerchantSurvivesSaveAndLoad() throws {
        let g = makeGame()
        g.testSetLevel(Balance.merchantLevel)
        g.updateMerchant()
        g.state.friendHearts["fin"] = 7
        g.state.achievementsClaimed["orders"] = 1
        let data = try JSONEncoder().encode(g.state)
        let back = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(back.merchant, g.state.merchant)
        XCTAssertEqual(back.friendHearts["fin"], 7)
        XCTAssertEqual(back.achievementsClaimed["orders"], 1)
    }

    // MARK: - Достижения

    func testAchievementTiersAndClaims() {
        let g = makeGame()
        XCTAssertEqual(g.achievementTier(.orders), 0)
        XCTAssertNil(g.claimAchievement(.orders))
        g.state.ordersTotal = 450
        XCTAssertEqual(g.achievementTier(.orders), 2)
        let gems = g.state.gems
        XCTAssertEqual(g.claimAchievement(.orders)?.gems, Achievements.tierGems[0])
        XCTAssertEqual(g.claimAchievement(.orders)?.gems, Achievements.tierGems[1])
        XCTAssertNil(g.claimAchievement(.orders))
        XCTAssertEqual(g.state.gems, gems + Achievements.tierGems[0] + Achievements.tierGems[1])
    }

    func testAchievementGoalsGrow() {
        let g = makeGame()
        for kind in AchievementKind.allCases {
            let goals = g.achievementGoals(kind)
            XCTAssertEqual(goals.count, 3, kind.rawValue)
            XCTAssertEqual(goals, goals.sorted(), kind.rawValue)
            XCTAssertEqual(Set(goals).count, 3, kind.rawValue)
        }
    }

    func testOldSaveGetsAchievementsItEarned() throws {
        var state = makeGame().state
        state.mergesTotal = 1200
        let data = try JSONEncoder().encode(state)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for key in ["friendHearts", "friendClaimed", "merchant", "merchantNextAt", "merchantsServed", "achievementsClaimed"] {
            json.removeValue(forKey: key)
        }
        let old = try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: json))
        let g = Game(state: old, seed: 3, now: { self.clock.date })
        XCTAssertEqual(g.achievementTier(.merges), 2)
        XCTAssertEqual(g.achievementsClaimable, 2)
        XCTAssertNil(g.state.merchant)
    }
}
