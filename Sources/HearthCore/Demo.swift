import Foundation

extension Game {
    /// Красивое состояние для скриншотов App Store: площадь отстроена, хутор в работе,
    /// на поле цепочки разных ступеней, есть украшения и прогресс события.
    /// late: деревня отстроена до Сада, для скриншота северных районов.
    public static func demo(late: Bool = false, now: @escaping () -> Date = Date.init) -> Game {
        var b = Balance()
        b.debrisRows = 1
        let game = Game(balance: b, seed: 2026, now: now)
        game.state.stars = 100_000
        let districts = game.village.districts
        let built = late
            ? districts.prefix(3).flatMap(\.tasks) + districts[3].tasks.prefix(4)
            : districts[0].tasks + districts[1].tasks.prefix(3)
        for task in built {
            _ = game.complete(taskId: task.id)
        }
        game.state.stars = 27
        game.state.coins = 2_480
        game.state.gems = 145
        game.state.level = 9
        game.state.xp = game.xpToNextLevel * 2 / 3
        game.state.energy = 86
        game.state.jarEnergy = 38
        game.state.tutorialStep = TutorialStep.done.rawValue
        game.state.dailyClaimedAt = now()
        game.state.decorOwned = ["decor_torch": 1]
        game.state.placedDecor = [
            PlacedDecor(id: 1, key: "decor_garland", x: 11, y: 66.5),
            PlacedDecor(id: 2, key: "decor_flowers_purple", x: 7, y: 77),
            PlacedDecor(id: 3, key: "decor_scarecrow", x: 18.5, y: 87),
        ]
        game.state.nextDecorId = 4
        // поле: генераторы внизу, над ними пары и цепочки разных ступеней
        let layout: [(Int, Piece)] = [
            (0, .debris(1)), (1, .debris(2)), (2, .debris(1)), (3, .debris(1)), (4, .debris(2)), (5, .debris(1)), (6, .debris(1)),
            (15, .item(Item(chain: "garden", tier: 3))), (16, .item(Item(chain: "garden", tier: 3))),
            (18, .item(Item(chain: "apiary", tier: 2))), (19, .item(Item(chain: "quarry", tier: 4))),
            (22, .item(Item(chain: "forest", tier: 2))), (23, .item(Item(chain: "forest", tier: 2))),
            (24, .item(Item(chain: "farm", tier: 1))), (26, .item(Item(chain: "garden", tier: 5))),
            (29, .item(Item(chain: "quarry", tier: 1))), (30, .item(Item(chain: "quarry", tier: 1))), (31, .item(Item(chain: "apiary", tier: 3))),
            (33, .item(Item(chain: "forest", tier: 4))), (36, .item(Item(chain: "garden", tier: 1))),
            (38, .item(Item(chain: "farm", tier: 2))), (40, .item(Item(chain: "garden", tier: 2))), (41, .item(Item(chain: "garden", tier: 2))),
            (44, .item(Item(chain: "apiary", tier: 0))), (45, .item(Item(chain: "forest", tier: 0))), (46, .item(Item(chain: "quarry", tier: 0))),
            (49, .generator(GeneratorPiece(chain: "apiary", tier: 0))),
            (57, .generator(GeneratorPiece(chain: "garden", tier: 1))), (59, .generator(GeneratorPiece(chain: "forest", tier: 1))),
            (61, .generator(GeneratorPiece(chain: "quarry", tier: 0))), (55, .generator(GeneratorPiece(chain: "farm", tier: 0))),
        ]
        for i in game.state.cells.indices { game.state.cells[i] = nil }
        for (i, piece) in layout where i < game.state.cells.count { game.state.cells[i] = piece }
        game.state.orders = [
            Order(id: 9001, needs: [Item(chain: "garden", tier: 3)], coins: 24, stars: 1, xp: 8),
            Order(id: 9002, needs: [Item(chain: "quarry", tier: 4), Item(chain: "forest", tier: 2)], coins: 60, stars: 2, xp: 20),
            Order(id: 9003, needs: [Item(chain: "apiary", tier: 3)], coins: 24, stars: 1, xp: 8),
            Order(id: 9004, needs: [Item(chain: "farm", tier: 2)], coins: 12, stars: 1, xp: 4),
        ]
        game.state.nextOrderId = 9005
        game.state.postcardPieces = 6
        if game.activeEvent != nil { game.state.eventTokens = 64; _ = game.claimEventMilestones() }
        // альбом: все на поле найдено, две свежие находки ждут награды
        for case .item(let item)? in game.state.cells { game.discover(item) }
        let fresh = ["garden#5", "quarry#4"]
        game.state.collectionClaimed = game.state.discovered.filter { !fresh.contains($0) }
        // задания: одно готово к награде, одно в процессе, одно забрано
        let quests = game.ensureQuests()
        game.progressQuest(quests[0].kind, by: quests[0].target)
        game.progressQuest(quests[1].kind, by: quests[1].target / 2)
        game.progressQuest(quests[2].kind, by: quests[2].target)
        game.state.quests[2].claimed = true
        game.lastDiscovery = nil
        return game
    }

    /// Часы демо: идут как обычно, но сдвинуты на субботу 16.01.2027, 12:00 UTC,
    /// чтобы на скриншотах всегда шел праздник выходных.
    public static func demoClock(start: Date = Date()) -> () -> Date {
        let saturday = Date(timeIntervalSince1970: 1_800_100_800)
        let shift = saturday.timeIntervalSince(start)
        return { Date().addingTimeInterval(shift) }
    }
}
