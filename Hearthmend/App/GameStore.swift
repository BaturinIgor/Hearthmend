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
            // как генератор: первый тап выбирает, второй открывает
            guard selected == index else {
                Haptics.light()
                selected = index
                return nil
            }
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
        guard game.deliver(orderId: order.id) != nil else { return }
        Haptics.success()
        Audio.shared.play(.coins)
        selected = nil
        if piggyBefore < balance.piggyMin && state.piggyGems >= balance.piggyMin {
            show(L10n.t("shop.piggy_ready"))
        } else if piggyBefore < balance.piggyMax && game.piggyFull {
            show(L10n.t("shop.piggy_full"))
        } else {
            show(String(format: L10n.t("toast.order_done"), order.coins, order.stars))
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
