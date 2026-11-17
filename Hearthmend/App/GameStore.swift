import Foundation
import HearthCore

/// Связывает ядро игры с UI: хранит Game, сохраняет прогресс после каждого действия
/// и раз в секунду обновляет энергию и пузыри.
@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var state: GameState
    @Published var selected: Int?
    @Published var toast: String?
    /// Чего не хватило игроку: всплывает окно с быстрым способом пополнить.
    @Published var shortage: Shortage?
    /// Последний открытый ящик: сцена поля проигрывает по нему анимацию.
    private var selectedAt = Date.distantPast
    var lastOpenedChest: (index: Int, chest: Chest, reward: ChestReward)?
    /// Праздник поверх экрана: новый уровень, новый житель, отстроенный район.
    @Published var celebration: Celebration?
    /// Свежие награды события: баннер события их показывает.
    @Published var eventRewards: [EventReward] = []

    let game: Game
    private var timer: Timer?
    private var toastTask: Task<Void, Never>?

    /// Сцена перерисовывает поле после изменений, которые сделал не перетаскиванием.
    var onBoardChange: (() -> Void)?
    var onHighlight: (([Int]) -> Void)?
    @Published var canUndo = false
    private var undoTask: Task<Void, Never>?

    /// Демо для скриншотов App Store: запуск с аргументом -demo, прогресс не сохраняется.
    static let isDemo = CommandLine.arguments.contains("-demo")

    init() {
        game = Self.isDemo ? Game.demo(late: Shot.isLate, far: Shot.isFar, now: Game.demoClock()) : Game(state: Persistence.load())
        state = game.state
        game.refreshEnergy()
        game.expireBubbles()
        if !Self.isDemo { game.updateMerchant() }
        commit()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    var catalog: Catalog { game.catalog }
    /// Время года для карты. На скриншотах всегда лето: они висят в App Store круглый год.
    var season: Season { Shot.name != nil ? .summer : game.season }
    var balance: Balance { game.balance }

    private func tick() {
        let adventureKey = game.state.adventure?.key
        if game.adventure?.key != adventureKey { commit() }
        if game.state.questDay != game.questDay {
            game.ensureQuests()
            commit()
        }
        if !Self.isDemo, game.updateMerchant() || (game.state.merchant == nil) != (state.merchant == nil) {
            if game.state.merchant != nil { show(L10n.t("merchant.arrived")) }
            commit()
        }
        let energy = game.state.energy
        game.refreshEnergy()
        let removed = game.expireBubbles()
        if !removed.isEmpty || energy != game.state.energy {
            commit()
            if !removed.isEmpty { onBoardChange?() }
        } else {
            // таймер энергии в шапке
            objectWillChange.send()
        }
    }

    private func commit() {
        state = game.state
        if !Self.isDemo { Persistence.save(game.state) }
    }

    /// Сразу записать сохранение (при уходе приложения в фон).
    func flush() {
        if !Self.isDemo { Persistence.flush() }
    }

    func show(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: - Действия

    /// Тап по клетке. Для генератора возвращает результат, чтобы сцена показала полет предмета.
    @discardableResult
    func tap(_ index: Int) -> Game.SpawnResult? {
        switch game.piece(at: index) {
        case .generator?:
            // первый тап выбирает генератор, следующие тапы по выбранному дают предметы:
            // случайное касание не тратит энергию
            guard selected == index else {
                Haptics.light()
                selected = index
                return nil
            }
            let result = game.spawn(from: index)
            switch result {
            case .spawned:
                Haptics.light()
                Audio.shared.play(.spawn)
            case .noEnergy:
                Audio.shared.play(.nope)
                shortage = .energy
            case .boardFull:
                show(L10n.t("toast.board_full"))
            case .notGenerator:
                break
            }
            commit()
            return result
        case .bubble?:
            if game.popBubble(at: index) {
                Haptics.success()
                Audio.shared.play(.sparkle)
                commit()
                onBoardChange?()
            } else if case .bubble(let item, _)? = game.piece(at: index) {
                shortage = .gems(need: balance.popCost(item) - state.gems)
            }
        case .item?:
            selected = selected == index ? nil : index
        case .debris?:
            show(L10n.t("toast.debris"))
        case .chest(let chest)?:
            // как генератор: первый тап выбирает, второй открывает. Слишком быстрый второй тап
            // по ресурсу не считается: случайный двойной тап не заберет то, что копили для слияния
            guard selected == index else {
                Haptics.light()
                selected = index
                selectedAt = Date()
                return nil
            }
            if chest.kind != .items, Date().timeIntervalSince(selectedAt) < 0.35 { return nil }
            switch game.openChest(at: index) {
            case .opened(let reward):
                Haptics.success()
                Audio.shared.play(reward.coins > 0 || reward.gems > 0 ? .coins : .sparkle)
                lastOpenedChest = (index, chest, reward)
                // из начатого ящика можно сразу тапать дальше
                if case .chest? = game.piece(at: index) {} else { selected = nil }
                commit()
                onBoardChange?()
            case .needSpace:
                Audio.shared.play(.nope)
                show(L10n.t("chest.need_space"))
            case .notChest:
                break
            }
        case .thicket(let item)?:
            Haptics.light()
            selected = nil
            if game.isRevealed(index) {
                show(String(format: L10n.t("thicket.hint"), catalog.emoji(for: item), item.tier + 1))
            } else {
                show(L10n.t("thicket.hidden"))
            }
        case nil:
            selected = nil
        }
        return nil
    }

    @discardableResult
    func move(from: Int, to: Int) -> Game.MoveResult {
        let result = game.move(from: from, to: to)
        switch result {
        case .merged, .mergedGenerator, .mergedChest, .unlocked:
            Haptics.success()
            Audio.shared.play(game.lastLuckyEnergy > 0 ? .coins : .merge)
            selected = to
        case .moved, .swapped:
            Audio.shared.play(.drop)
            if selected == from { selected = to }
        case .invalid:
            break
        }
        commit()
        return result
    }

    func sellSelected() {
        guard let index = selected else { return }
        let coins = game.sell(at: index)
        guard coins > 0 else { return }
        selected = nil
        show(String(format: L10n.t("toast.sold"), coins))
        canUndo = true
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.canUndo = false }
        }
        commit()
        onBoardChange?()
    }

    /// Вернуть проданный предмет (кнопка живет 5 секунд после продажи).
    func undoSale() {
        canUndo = false
        guard game.undoSale() != nil else { return }
        Haptics.light()
        Audio.shared.play(.drop)
        commit()
        onBoardChange?()
    }

    func toggleBoost() {
        game.setBoost(!state.boostOn)
        Haptics.light()
        show(L10n.t(state.boostOn ? "boost.off" : "boost.on"))
        commit()
    }

    /// Подсветить на поле предметы, нужные заказу.
    func highlight(_ order: Order) {
        onHighlight?(game.cells(for: order))
    }

    func storeSelected() {
        guard let index = selected else { return }
        if storeItem(at: index) { onBoardChange?() }
    }

    /// Убрать предмет в корзину (кнопкой или перетаскиванием вниз под поле).
    @discardableResult
    func storeItem(at index: Int) -> Bool {
        guard game.store(at: index) else {
            Audio.shared.play(.nope)
            show(L10n.t(state.basket.count >= state.basketSize ? "toast.basket_full" : "toast.basket_only_items"))
            return false
        }
        Haptics.light()
        Audio.shared.play(.drop)
        if selected == index { selected = nil }
        commit()
        return true
    }

    func retrieve(_ basketIndex: Int) {
        guard game.retrieve(basketIndex: basketIndex) != nil else {
            show(L10n.t("toast.board_full"))
            return
        }
        Haptics.light()
        Audio.shared.play(.drop)
        commit()
        onBoardChange?()
    }

    func deliver(_ order: Order) {
        let piggyBefore = state.piggyGems
        let movesBefore = game.adventure?.moves
        guard game.deliver(orderId: order.id) != nil else { return }
        let movesGot = (game.adventure?.moves ?? 0) - (movesBefore ?? 0)
        Haptics.success()
        Audio.shared.play(.coins)
        selected = nil
        if piggyBefore < balance.piggyMin && state.piggyGems >= balance.piggyMin {
            show(L10n.t("shop.piggy_ready"))
        } else if piggyBefore < balance.piggyMax && game.piggyFull {
            show(L10n.t("shop.piggy_full"))
        } else {
            let moveIcon = AdventureArt.emoji(game.adventure?.kind ?? .depths)
            show(String(format: L10n.t("toast.order_done"), order.coins, order.stars) + (movesBefore != nil && movesGot > 0 ? "  \(moveIcon)\(movesGot)" : ""))
        }
        if let up = game.lastFriendLevelUp {
            show(String(format: L10n.t("friends.level_up"), L10n.t("resident.\(up.resident)"), up.level))
        }
        if !game.lastEventRewards.isEmpty {
            eventRewards = game.lastEventRewards
        }
        if let card = game.lastPostcard, let view = card.completed {
            celebrate(Celebration(icon: "🖼️",
                                  title: String(format: L10n.t("postcard.done"), L10n.t("district.\(view)")),
                                  subtitle: "💎 \(card.gems)   🪙 \(card.coins)   🪴"))
        }
        if let level = game.lastLevelUps.last {
            celebrate(Celebration(icon: "🎉",
                                  title: String(format: L10n.t("level.up"), level),
                                  subtitle: String(format: L10n.t("level.reward"),
                                                   balance.levelUpEnergy * game.lastLevelUps.count,
                                                   balance.levelUpGems * game.lastLevelUps.count)))
        }
        commit()
        onBoardChange?()
    }

    /// Строит задачу деревни. Возвращает true, если построено.
    @discardableResult
    func completeTask(_ id: String) -> Bool {
        let districtBefore = game.currentDistrict
        switch game.complete(taskId: id) {
        case .done(let task):
            Haptics.success()
            Audio.shared.play(.build)
            if let resident = task.resident, let chain = task.unlocksChain {
                celebrate(Celebration(icon: "npc:\(resident)",
                                      title: String(format: L10n.t("resident.arrived"), L10n.t("resident.\(resident)")),
                                      subtitle: String(format: L10n.t("resident.chain"), L10n.t("chain.\(chain)"))))
            } else if let district = districtBefore, game.currentDistrict?.id != district.id {
                celebrate(Celebration(icon: "🎊",
                                      title: String(format: L10n.t("district.done"), L10n.t("district.\(district.id)")),
                                      subtitle: game.currentDistrict.map { String(format: L10n.t("district.next"), L10n.t("district.\($0.id)")) }
                                          ?? L10n.t("village.done")))
            } else if let gems = task.gems {
                show(String(format: L10n.t("task.gems"), gems))
            }
            commit()
            onBoardChange?()
            return true
        case .notEnoughStars:
            show(L10n.t("toast.no_stars"))
            return false
        case .locked:
            return false
        }
    }

    // MARK: - Покупки, магазин, кувшин, ежедневная награда

    func grantPurchase(productId: String, transactionId: String, expires: Date?) {
        guard game.grantPurchase(productId: productId, transactionId: transactionId, expires: expires) else { return }
        Haptics.success()
        if let stamp = game.lastStamp, stamp.completed {
            celebrate(Celebration(icon: "🏵️", title: L10n.t("shop.stamps_done"), subtitle: "💎 \(stamp.gems)   🪴"))
        } else if let stamp = game.lastStamp {
            show(L10n.t("shop.thanks") + "\n" + String(format: L10n.t("shop.stamp_added"), stamp.stamps, stamp.of))
        } else {
            show(L10n.t("shop.thanks"))
        }
        commit()
    }

    func updateVIP(expires: Date?) {
        game.updateVIP(expires: expires)
        commit()
    }

    func buyEnergyWithGems() {
        if game.buyEnergyWithGems() {
            Haptics.success()
            show(String(format: L10n.t("shop.energy_added"), balance.energyPack))
            commit()
        } else {
            shortage = .gems(need: game.energyPackGems - state.gems)
        }
    }

    func buyEnergyWithCoins() {
        if game.buyEnergyWithCoins() {
            Haptics.success()
            show(String(format: L10n.t("shop.energy_added"), balance.coinEnergyAmount))
            commit()
        } else if let price = game.coinEnergyPrice {
            shortage = .coins(need: price - state.coins)
        }
    }

    func buyBasketSlot() {
        if game.buyBasketSlot() {
            Haptics.success()
            commit()
        } else if let price = game.basketSlotPrice {
            shortage = .coins(need: price - state.coins)
        }
    }

    /// Бесплатное открытие кувшина или, если рано, за кристаллы (с VIP бесплатно).
    func openJar(paid: Bool) {
        let amount = paid ? game.openJarNow() : game.openJar()
        if amount > 0 {
            Haptics.success()
            Audio.shared.play(.sparkle)
            show(String(format: L10n.t("jar.opened"), amount))
            commit()
        } else if paid {
            shortage = .gems(need: game.jarOpenGems - state.gems)
        }
    }

    func claimDaily() -> ProductReward? {
        let reward = game.claimDaily()
        if reward != nil {
            Haptics.success()
            commit()
        }
        return reward
    }

    // MARK: - Задания дня и альбом

    var quests: [Quest] { game.state.questDay == game.questDay ? game.state.quests : game.ensureQuests() }

    func claimQuest(_ index: Int) {
        guard let r = game.claimQuest(index) else { return }
        rewarded(r)
    }

    func claimQuestChest() {
        guard let r = game.claimQuestChest() else { return }
        Audio.shared.play(.levelup)
        rewarded(r)
    }

    func claimDiscovery(_ item: Item) {
        guard let r = game.claimDiscovery(item) else { return }
        Haptics.success()
        Audio.shared.play(.coins)
        show(ShopRewardText.short(ProductReward(gems: r.gems, coins: r.coins)))
        commit()
    }

    func claimChain(_ chain: String) {
        guard let gems = game.claimChain(chain) else { return }
        Haptics.success()
        Audio.shared.play(.levelup)
        show(ShopRewardText.short(ProductReward(gems: gems)))
        commit()
    }

    // MARK: - Дружба, торговец, достижения

    func claimFriend(_ resident: String) {
        guard let r = game.claimFriend(resident) else { return }
        if r.decor != nil {
            Audio.shared.play(.levelup)
            celebrate(Celebration(icon: "npc:\(resident)",
                                  title: String(format: L10n.t("friends.best"), L10n.t("resident.\(resident)")),
                                  subtitle: ShopRewardText.short(r) + "   🪴"))
            Haptics.success()
            commit()
        } else {
            rewarded(r)
        }
    }

    func claimAchievement(_ kind: AchievementKind) {
        guard let r = game.claimAchievement(kind) else { return }
        Audio.shared.play(.levelup)
        rewarded(r)
    }

    func deliverMerchant() {
        guard let visit = game.deliverMerchant() else { return }
        Haptics.success()
        Audio.shared.play(.coins)
        selected = nil
        var parts = ShopRewardText.short(ProductReward(gems: visit.gems, energy: visit.energy, coins: visit.coins))
        if visit.decor != nil { parts += "   🪴" }
        celebrate(Celebration(icon: "🛒", title: L10n.t("merchant.thanks"), subtitle: parts))
        commit()
        onBoardChange?()
    }

    var canDeliverMerchant: Bool { game.canDeliverMerchant() }

    func claimShopGift() {
        guard let gift = game.claimShopGift() else { return }
        Haptics.success()
        Audio.shared.play(.coins)
        show(ShopRewardText.short(gift))
        commit()
    }

    func buyCoins(_ pack: CoinPack) {
        if game.buyCoins(pack) {
            Haptics.success()
            Audio.shared.play(.coins)
            show("🪙 +\(pack.coins)")
            shortage = nil
            commit()
        } else {
            shortage = .gems(need: pack.gems - state.gems)
        }
    }

    // MARK: - Животные

    func adoptPet(_ id: String) {
        guard game.adoptPet(id) else {
            if let pet = Pets.def(id), game.petAvailable(id), state.coins < pet.cost {
                shortage = .coins(need: pet.cost - state.coins)
            }
            return
        }
        Haptics.success()
        Audio.shared.play(.levelup)
        show(String(format: L10n.t("pets.adopted"), L10n.t("pet.\(id)")))
        commit()
    }

    @discardableResult
    func collectPet(_ id: String) -> Bool {
        guard let r = game.collectPet(id) else { return false }
        rewarded(r)
        return true
    }

    private func rewarded(_ r: ProductReward) {
        Haptics.success()
        Audio.shared.play(.coins)
        show(ShopRewardText.short(r))
        commit()
    }

    func skipTutorial() {
        game.skipTutorial()
        commit()
        onBoardChange?()
    }

    // MARK: - События и украшения

    func chooseEvent(_ id: String) {
        let rewards = game.chooseEvent(id)
        Haptics.success()
        if !rewards.isEmpty { eventRewards = rewards }
        commit()
    }

    // MARK: - Большое событие

    /// Копает клетку шахты. Возвращает результат, чтобы экран проиграл анимацию.
    @discardableResult
    func dig(_ index: Int) -> Game.DigResult {
        let result = game.dig(index)
        switch result {
        case .invalid:
            Haptics.light()
        case .noMoves:
            Audio.shared.play(.nope)
            show(L10n.t("adv.no_moves"))
        case .chipped:
            Haptics.light()
            Audio.shared.play(.drop)
        case .opened(let found, let prizes, let opened):
            Haptics.success()
            Audio.shared.play(opened.count > 1 || !prizes.isEmpty ? .sparkle : .spawn)
            if !prizes.isEmpty {
                show(String(format: L10n.t("adv.prize"), prizes.map(Self.describe).joined(separator: " ")))
            } else if found.isEmpty, opened.count == 1, case .find? = game.adventure?.depths?.cells[index].content {
                show(L10n.t("adv.board_full"))
            }
            onBoardChange?()
        }
        commit()
        return result
    }

    /// Тап по открытой клетке, где ждет находка.
    func collectDepth(_ index: Int) {
        if game.collectDepth(index) != nil {
            Haptics.light()
            Audio.shared.play(.spawn)
        } else {
            show(L10n.t("adv.board_full"))
        }
        commit()
    }

    /// Перенос находки на поле события. true - если находки слились.
    @discardableResult
    func moveFind(from: Int, to: Int) -> Bool {
        let a = game.state.adventure?.depths?.board[from] ?? nil
        let b = game.state.adventure?.depths?.board[to] ?? nil
        guard game.moveFind(from: from, to: to) else { return false }
        let merged = a != nil && a == b && (game.state.adventure?.depths?.board[from] ?? nil) == nil
        if merged {
            Haptics.success()
            Audio.shared.play(.merge)
        } else {
            Haptics.light()
        }
        commit()
        return merged
    }

    func deliverFind(_ slot: Int) {
        guard let r = game.deliverFind(slot) else { return }
        Haptics.success()
        Audio.shared.play(.coins)
        if r.prizes.isEmpty {
            show(String(format: L10n.t("adv.points"), r.points))
        } else {
            show(String(format: L10n.t("adv.prize"), r.prizes.map(Self.describe).joined(separator: " ")))
            onBoardChange?()
        }
        commit()
    }

    func claimAdventureDaily(icon: String = "ui_pickaxe") {
        let n = game.claimAdventureDaily()
        guard n > 0 else { return }
        Haptics.success()
        Audio.shared.play(.coins)
        show(AdventureArt.emoji(game.adventure?.kind ?? .depths) + " +\(n)")
        commit()
    }

    // MARK: - Остров

    @discardableResult
    func tide() -> Game.TideResult {
        let r = game.tide()
        switch r {
        case .noMoves:
            Audio.shared.play(.nope)
            show(L10n.t("adv.no_shells"))
        case .noRoom:
            Audio.shared.play(.nope)
            show(L10n.t("adv.island.full"))
        case .placed:
            Haptics.light()
            Audio.shared.play(.spawn)
        }
        commit()
        return r
    }

    @discardableResult
    func moveOnIsland(from: Int, to: Int) -> Game.IslandMove? {
        guard let r = game.moveOnIsland(from: from, to: to) else { return nil }
        if r.merges.isEmpty {
            Haptics.light()
            Audio.shared.play(.drop)
        } else {
            Haptics.success()
            Audio.shared.play(r.merges.count > 1 || r.merges.contains { $0.made > 1 } ? .sparkle : .merge)
            if !r.prizes.isEmpty {
                show(String(format: L10n.t("adv.prize"), r.prizes.map(Self.describe).joined(separator: " ")))
                onBoardChange?()
            } else if r.points > 0 {
                show(String(format: L10n.t("adv.points"), r.points))
            }
        }
        commit()
        return r
    }

    func washAway(_ index: Int) {
        guard game.washAway(index) else { return }
        Haptics.light()
        Audio.shared.play(.drop)
        commit()
    }

    // MARK: - Теплица

    @discardableResult
    func plantSeed(at bed: Int? = nil) -> Game.PlantResult {
        let r = game.plantSeed(at: bed)
        switch r {
        case .noMoves:
            Audio.shared.play(.nope)
            show(L10n.t("adv.no_seeds"))
        case .noRoom:
            Audio.shared.play(.nope)
            show(L10n.t("adv.greenhouse.full"))
        case .planted:
            Haptics.light()
            Audio.shared.play(.spawn)
        }
        commit()
        return r
    }

    /// Перенос растения. true - если растения слились.
    @discardableResult
    func movePlant(from: Int, to: Int) -> Bool {
        let merge = game.canMergePlants(from, to)
        guard game.movePlant(from: from, to: to) else { return false }
        Haptics.light()
        Audio.shared.play(merge ? .merge : .drop)
        commit()
        return merge
    }

    func harvest(_ bed: Int) {
        guard let r = game.harvest(bed) else { return }
        Haptics.success()
        Audio.shared.play(.coins)
        if r.prizes.isEmpty {
            show(String(format: L10n.t("adv.points"), r.points))
        } else {
            show(String(format: L10n.t("adv.prize"), r.prizes.map(Self.describe).joined(separator: " ")))
            onBoardChange?()
        }
        commit()
    }

    func water() {
        guard game.water() else { return }
        Haptics.success()
        Audio.shared.play(.sparkle)
        show(L10n.t("adv.greenhouse.watered"))
        commit()
    }

    // MARK: - Витраж

    @discardableResult
    func cutGlass() -> Game.CutResult {
        let r = game.cutGlass()
        switch r {
        case .noMoves:
            Audio.shared.play(.nope)
            show(L10n.t("adv.no_glass"))
        case .noRoom:
            Audio.shared.play(.nope)
            show(L10n.t("adv.mosaic.full"))
        case .cut:
            Haptics.light()
            Audio.shared.play(.spawn)
        }
        commit()
        return r
    }

    /// Перенос на верстаке. true - если кусочки слились.
    @discardableResult
    func moveGlass(from: Int, to: Int) -> Bool {
        let merge = game.canMergeGlass(from, to)
        guard game.moveGlass(from: from, to: to) else { return false }
        Haptics.light()
        Audio.shared.play(merge ? .merge : .drop)
        commit()
        return merge
    }

    @discardableResult
    func setGlass(slot: Int, cell: Int) -> Game.MosaicSet? {
        guard let r = game.setGlass(slot: slot, cell: cell) else {
            Audio.shared.play(.nope)
            show(L10n.t("adv.mosaic.wrong"))
            return nil
        }
        if r.windowDone || r.regionDone {
            Haptics.success()
            Audio.shared.play(.sparkle)
        } else {
            Haptics.light()
            Audio.shared.play(.drop)
        }
        if r.windowDone {
            show(L10n.t("adv.mosaic.done") + " " + r.prizes.map(Self.describe).joined(separator: " "))
            onBoardChange?()
        } else if !r.prizes.isEmpty {
            show(String(format: L10n.t("adv.prize"), r.prizes.map(Self.describe).joined(separator: " ")))
            onBoardChange?()
        } else {
            show(String(format: L10n.t("adv.points"), r.points))
        }
        commit()
        return r
    }

    func shatterGlass(_ slot: Int) {
        guard game.shatterGlass(slot) else { return }
        Haptics.light()
        Audio.shared.play(.drop)
        commit()
    }

    /// Награда события одной строкой: ящики и ресурсы значками, генератор, украшение.
    static func describe(_ prize: AdventurePrize) -> String {
        switch prize {
        case .chest(let c):
            switch c.kind {
            case .coins: return "🪙\(c.amount)"
            case .energy: return "⚡️\(c.amount)"
            case .gems: return "💎\(c.amount)"
            case .items: return "🧰"
            }
        case .generator: return "🛠"
        case .decor: return "🪴"
        }
    }

    func placeDecor(_ key: String, x: Double, y: Double) {
        guard game.placeDecor(key, x: x, y: y) != nil else { return }
        Haptics.light()
        commit()
    }

    func moveDecor(id: Int, x: Double, y: Double) {
        game.moveDecor(id: id, x: x, y: y)
        commit()
    }

    func moveBuilding(_ id: String, x: Double, y: Double) {
        guard game.moveBuilding(id, x: x, y: y) else { return }
        Haptics.light()
        commit()
    }

    func resetBuilding(_ id: String) {
        game.resetBuilding(id)
        Haptics.light()
        commit()
    }

    /// Сцена истории, которую пора показать (если игрок не в обучении).
    var pendingStory: String? {
        game.tutorial == .done ? game.pendingStory : nil
    }

    func storySeen(_ id: String) {
        game.markStorySeen(id)
        commit()
    }

    func storeDecor(id: Int) {
        game.storeDecor(id: id)
        Haptics.light()
        commit()
    }

    /// Можно ли сейчас что-то построить: на кнопке деревни горит отметка.
    var canBuildSomething: Bool {
        game.availableTasks.contains { $0.cost <= state.stars }
    }

    private func celebrate(_ c: Celebration) {
        Audio.shared.play(.levelup)
        celebration = c
    }

    func canDeliver(_ order: Order) -> Bool { game.canDeliver(order) }

    var nextEnergyIn: TimeInterval? { game.nextEnergyIn }

    #if DEBUG
    func debugReset() {
        Persistence.reset()
        exit(0)
    }
    #endif
}

enum Shortage: Equatable {
    case energy
    case coins(need: Int)
    case gems(need: Int)

    var isGems: Bool { if case .gems = self { return true } else { return false } }
}

struct Celebration: Equatable, Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
}

/// Сохранение в Application Support/save.json.
enum Persistence {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("save.json")
    }

    static func load() -> GameState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(GameState.self, from: data)
    }

    private static let queue = DispatchQueue(label: "hearthmend.save", qos: .utility)
    private static var pending: GameState?
    private static var scheduled = false
    private static let lock = NSLock()

    /// Сохранение не чаще раза в полсекунды и не на главном потоке: быстрые тапы не тормозят.
    static func save(_ state: GameState) {
        lock.lock()
        pending = state
        let start = !scheduled
        scheduled = true
        lock.unlock()
        if start { queue.asyncAfter(deadline: .now() + 0.5) { write() } }
    }

    static func flush() {
        queue.sync { write() }
    }

    private static func write() {
        lock.lock()
        let state = pending
        pending = nil
        scheduled = false
        lock.unlock()
        guard let state, let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func reset() {
        try? FileManager.default.removeItem(at: url)
    }
}
