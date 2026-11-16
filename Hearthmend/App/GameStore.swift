import Foundation
import HearthCore

/// Связывает ядро игры с UI: хранит Game, сохраняет прогресс после каждого действия
/// и раз в секунду обновляет энергию и пузыри.
@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var state: GameState
    @Published var selected: Int?
    @Published var toast: String?
    /// Праздник поверх экрана: новый уровень, новый житель, отстроенный район.
    @Published var celebration: Celebration?

    let game: Game
    private var timer: Timer?
    private var toastTask: Task<Void, Never>?

    /// Сцена перерисовывает поле после изменений, которые сделал не перетаскиванием.
    var onBoardChange: (() -> Void)?

    init() {
        game = Game(state: Persistence.load())
        state = game.state
        game.refreshEnergy()
        game.expireBubbles()
        commit()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    var catalog: Catalog { game.catalog }
    var balance: Balance { game.balance }

    private func tick() {
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
        Persistence.save(game.state)
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

    func tap(_ index: Int) {
        switch game.piece(at: index) {
        case .generator?:
            switch game.spawn(from: index) {
            case .spawned:
                Haptics.light()
            case .noEnergy:
                show(L10n.t("toast.no_energy"))
            case .boardFull:
                show(L10n.t("toast.board_full"))
            case .notGenerator:
                break
            }
            selected = nil
            commit()
            onBoardChange?()
        case .bubble?:
            if game.popBubble(at: index) {
                Haptics.success()
                commit()
                onBoardChange?()
            } else {
                show(L10n.t("toast.no_gems"))
            }
        case .item?:
            selected = selected == index ? nil : index
        case .debris?:
            show(L10n.t("toast.debris"))
        case nil:
            selected = nil
        }
    }

    @discardableResult
    func move(from: Int, to: Int) -> Game.MoveResult {
        let result = game.move(from: from, to: to)
        switch result {
        case .merged, .mergedGenerator:
            Haptics.success()
            selected = to
        case .moved, .swapped:
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
        commit()
        onBoardChange?()
    }

    func storeSelected() {
        guard let index = selected else { return }
        guard game.store(at: index) else {
            show(L10n.t("toast.basket_full"))
            return
        }
        selected = nil
        commit()
        onBoardChange?()
    }

    func retrieve(_ basketIndex: Int) {
        guard game.retrieve(basketIndex: basketIndex) != nil else {
            show(L10n.t("toast.board_full"))
            return
        }
        commit()
        onBoardChange?()
    }

    func deliver(_ order: Order) {
        guard game.deliver(orderId: order.id) != nil else { return }
        Haptics.success()
        selected = nil
        show(String(format: L10n.t("toast.order_done"), order.coins, order.stars))
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
            if let resident = task.resident, let chain = task.unlocksChain {
                celebrate(Celebration(icon: "🏡",
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

    /// Можно ли сейчас что-то построить: на кнопке деревни горит отметка.
    var canBuildSomething: Bool {
        game.availableTasks.contains { $0.cost <= state.stars }
    }

    private func celebrate(_ c: Celebration) {
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

    static func save(_ state: GameState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func reset() {
        try? FileManager.default.removeItem(at: url)
    }
}
