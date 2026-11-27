import FirebaseAnalytics
import FirebaseCore
import Foundation
import HearthCore
import StoreKit
import SwiftUI

/// Анонимная статистика через Google Analytics for Firebase (схема как в ZenHab, см. tools/analytics/README.md).
///
/// - Прогресс игры (шаги обучения, уровни, постройки, районы, новые цепочки) уходит из `track(from:to:)`:
///   GameStore вызывает его на каждое сохранение, поэтому ядро игры про статистику ничего не знает.
/// - Экраны уходят как `screen_view`, покупки - стандартным `purchase` с ценой и валютой.
/// - Раз в день `daily_state`: уровень, звезды, монеты, кристаллы, район, всего заказов и слияний.
/// - user property `build_type` (debug / testflight / appstore): в GA4 смотреть только appstore.
///
/// Личного нет: только номера, счетчики и id игровых данных (задачи, районы, товары). IDFA не собирается
/// (FirebaseAnalyticsCore без AdSupport), IDFV и рекламные сигналы выключены в project.yml.
/// Без GoogleService-Info.plist (SideStore, локальная сборка), в Debug, на симуляторе и в демо для снимков
/// ничего не отправляется. В отладке сбор включает аргумент -AnalyticsDebug (с -FIRDebugEnabled видно в DebugView).
@MainActor
final class Analytics {
    static let shared = Analytics()

    /// Выключатель в настройках: true - выключено, нет значения - игрок не выбирал (тогда enabledByDefault).
    static let optOutKey = "analyticsOptOut"
    /// Opt-out, как в ZenHab: собираем, пока игрок не выключит. Firebase сам ничего не собирает
    /// (FIREBASE_ANALYTICS_COLLECTION_ENABLED = false), сбор включает только start().
    static let enabledByDefault = true

    private let defaults = UserDefaults.standard
    private(set) var configured = false
    private var screenStack: [String] = []
    /// Обучение пропустили кнопкой: шаг сразу прыгает в done, и это не прохождение шагов.
    private var skippingTutorial = false

    private enum Key {
        static let installSent = "analytics.installSent"
        static let firstSeen = "analytics.firstSeen"
        static let stateDay = "analytics.stateDay"
    }

    private init() {}

    /// Есть GoogleService-Info.plist, и это не Debug, не симулятор и не демо для снимков.
    static var isAvailable: Bool {
        guard !GameStore.isDemo, !Shot.isActive,
              Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return false }
        return sendsFrom(isDebug: isDebugBuild, isSimulator: isSimulator,
                         forced: ProcessInfo.processInfo.arguments.contains("-AnalyticsDebug"))
    }

    static func sendsFrom(isDebug: Bool, isSimulator: Bool, forced: Bool) -> Bool {
        forced || (!isDebug && !isSimulator)
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    enum BuildType: String {
        case debug, testflight, appstore

        static func make(isDebug: Bool, isSimulator: Bool, isSandbox: Bool) -> BuildType {
            if isDebug || isSimulator { return .debug }
            return isSandbox ? .testflight : .appstore
        }
    }

    /// TestFlight или установка из Xcode. AppTransaction есть с iOS 16, на iOS 15 смотрим на имя чека.
    private static func isSandbox() async -> Bool {
        if #available(iOS 16, *) {
            guard let result = try? await AppTransaction.shared else { return false }
            switch result {
            case .verified(let t), .unverified(let t, _): return t.environment != .production
            }
        }
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    static func isUserEnabled(_ defaults: UserDefaults) -> Bool {
        (defaults.object(forKey: optOutKey) as? Bool).map { !$0 } ?? enabledByDefault
    }

    /// Firebase настроен и игрок не выключил статистику.
    var isActive: Bool { configured && Self.isUserEnabled(defaults) }

    /// При запуске приложения.
    func start(_ state: GameState) {
        guard Self.isAvailable, !configured,
              let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              // испорченный plist уронил бы приложение в configure(), а так просто нет статистики
              let options = FirebaseOptions(contentsOfFile: path) else { return }
        FirebaseApp.configure(options: options)
        configured = true
        if defaults.object(forKey: Key.firstSeen) == nil {
            defaults.set(Date(), forKey: Key.firstSeen)
        }
        let enabled = Self.isUserEnabled(defaults)
        FirebaseAnalytics.Analytics.setAnalyticsCollectionEnabled(enabled)
        if enabled { setUserProperties(state) }
    }

    private func setUserProperties(_ state: GameState) {
        if let first = defaults.object(forKey: Key.firstSeen) as? Date {
            FirebaseAnalytics.Analytics.setUserProperty(Self.weekKey(first), forName: "first_seen_week")
        }
        updateUser(state)
        Task {
            let type = BuildType.make(isDebug: Self.isDebugBuild, isSimulator: Self.isSimulator, isSandbox: await Self.isSandbox())
            FirebaseAnalytics.Analytics.setUserProperty(type.rawValue, forName: "build_type")
        }
    }

    private func updateUser(_ state: GameState) {
        guard isActive else { return }
        FirebaseAnalytics.Analytics.setUserProperty(String(state.level), forName: "level")
        FirebaseAnalytics.Analytics.setUserProperty((state.vipUntil ?? .distantPast) > Date() ? "1" : "0", forName: "is_vip")
        FirebaseAnalytics.Analytics.setUserProperty(state.grantedTransactions.isEmpty ? "0" : "1", forName: "is_payer")
    }

    /// Игрок выключил или включил статистику в настройках.
    func setEnabled(_ enabled: Bool, state: GameState) {
        defaults.set(!enabled, forKey: Self.optOutKey)
        guard configured else { return }
        FirebaseAnalytics.Analytics.setAnalyticsCollectionEnabled(enabled)
        if enabled {
            setUserProperties(state)
        } else {
            FirebaseAnalytics.Analytics.resetAnalyticsData()
        }
    }

    // MARK: Жизненный цикл

    /// Приложение стало активным: установка (один раз) и состояние игры (раз в день).
    func appBecameActive(_ game: Game) {
        guard isActive else { return }
        let state = game.state
        if !defaults.bool(forKey: Key.installSent) {
            defaults.set(true, forKey: Key.installSent)
            // у обновившихся с 1.1 уже есть заказы: это не новая установка
            log("app_installed", ["is_update": state.ordersTotal > 0])
        }
        updateUser(state)
        let today = Self.dayKey(Date())
        guard defaults.string(forKey: Key.stateDay) != today else { return }
        defaults.set(today, forKey: Key.stateDay)
        var payload = Self.snapshot(game)
        if let first = defaults.object(forKey: Key.firstSeen) as? Date {
            payload["days_since_first_seen"] = max(0, Calendar.current.dateComponents([.day], from: first, to: Date()).day ?? 0)
        }
        log("daily_state", payload)
    }

    /// Числа о состоянии игры для daily_state. Только счетчики и id игровых данных.
    static func snapshot(_ game: Game) -> [String: Any] {
        let s = game.state
        let districts = game.village.districts
        return [
            "level": s.level,
            "stars": s.stars,
            "coins": s.coins,
            "gems": s.gems,
            "energy": s.energy,
            "tasks_done": s.completedTasks.count,
            "district": game.currentDistrict?.id ?? "complete",
            "district_index": districts.firstIndex { $0.id == game.currentDistrict?.id } ?? districts.count,
            "orders_total": s.ordersTotal,
            "merges_total": s.mergesTotal,
            "chains": s.unlockedChains.count,
            "daily_streak": s.dailyStreak,
            "tutorial_step": s.tutorialStep,
            "is_vip": (s.vipUntil ?? .distantPast) > Date(),
            "purchases": s.grantedTransactions.count,
            "decor_placed": s.placedDecor.count,
        ]
    }

    // MARK: Прогресс игры

    /// Что изменилось между двумя сохранениями: шаг обучения, уровень, постройки, районы, цепочки.
    func track(from old: GameState, to new: GameState, game: Game) {
        let skipped = skippingTutorial
        skippingTutorial = false
        guard isActive else { return }
        for event in Self.progressEvents(from: old, to: new, game: game) {
            if skipped, event.name == "tutorial_step" || event.name == AnalyticsEventTutorialComplete { continue }
            log(event.name, event.params)
        }
        if new.level != old.level || new.grantedTransactions.count != old.grantedTransactions.count { updateUser(new) }
    }

    struct Event {
        let name: String
        let params: [String: Any]
    }

    /// События прогресса между двумя состояниями (отдельно от отправки, чтобы было видно, что уходит).
    static func progressEvents(from old: GameState, to new: GameState, game: Game) -> [Event] {
        var events: [Event] = []
        let done = TutorialStep.done.rawValue
        if new.tutorialStep > old.tutorialStep, old.tutorialStep < done {
            for step in (old.tutorialStep + 1)...min(new.tutorialStep, done) {
                let name = TutorialStep(rawValue: step).map { String(describing: $0) } ?? "\(step)"
                events.append(Event(name: "tutorial_step", params: ["step": step, "step_name": name]))
            }
            if new.tutorialStep >= done {
                events.append(Event(name: AnalyticsEventTutorialComplete, params: ["orders_total": new.ordersTotal]))
            }
        }
        if new.level > old.level {
            for level in (old.level + 1)...new.level {
                events.append(Event(name: AnalyticsEventLevelUp, params: [AnalyticsParameterLevel: level]))
            }
        }
        let districts = game.village.districts
        for task in new.completedTasks where !old.completedTasks.contains(task) {
            let district = districts.first { d in d.tasks.contains { $0.id == task } }
            events.append(Event(name: "task_built", params: ["task": task, "district": district?.id ?? "",
                                                             "tasks_done": new.completedTasks.count, "level": new.level]))
            if let district, district.tasks.allSatisfy({ new.completedTasks.contains($0.id) }),
               !district.tasks.allSatisfy({ old.completedTasks.contains($0.id) }) {
                let index = districts.firstIndex { $0.id == district.id } ?? -1
                events.append(Event(name: "district_done", params: ["district": district.id, "district_index": index,
                                                                    "level": new.level]))
            }
        }
        for chain in new.unlockedChains where !old.unlockedChains.contains(chain) {
            events.append(Event(name: "chain_unlocked", params: ["chain": chain, "level": new.level]))
        }
        return events
    }

    func tutorialSkipped(at step: Int) {
        skippingTutorial = true
        log("tutorial_skipped", ["step": step])
    }

    /// Не хватило энергии, кристаллов или монет: всплыло окно пополнения.
    func shortage(_ kind: String, need: Int) {
        log("shortage_shown", ["kind": kind, "need": need])
    }

    // MARK: Покупки

    func purchaseStarted(_ id: String) { log("purchase_started", ["purchase_product_id": id]) }
    func purchaseCancelled(_ id: String) { log("purchase_cancelled", ["purchase_product_id": id]) }
    func purchaseFailed(_ id: String) { log("purchase_failed", ["purchase_product_id": id]) }

    /// Покупка прошла: стандартное событие purchase, доход виден в отчетах GA4.
    func purchase(_ product: Product) {
        log(AnalyticsEventPurchase, [
            AnalyticsParameterValue: NSDecimalNumber(decimal: product.price).doubleValue,
            AnalyticsParameterCurrency: product.priceFormatStyle.currencyCode,
            AnalyticsParameterItemID: product.id,
            "purchase_product_id": product.id,
        ])
    }

    // MARK: Отзывы

    func reviewPromptShown(level: Int, days: Int) { log("review_prompt_shown", ["level": level, "days_played": days]) }
    func feedbackSent(kind: String, via: String) { log("feedback_sent", ["kind": kind, "via": via]) }

    // MARK: Экраны

    func screenAppeared(_ screen: String) {
        screenStack.removeAll { $0 == screen }
        screenStack.append(screen)
        logScreen(screen)
    }

    func screenDisappeared(_ screen: String) {
        let wasTop = screenStack.last == screen
        screenStack.removeAll { $0 == screen }
        if wasTop, let top = screenStack.last { logScreen(top) }
    }

    private func logScreen(_ screen: String) {
        guard isActive else { return }
        FirebaseAnalytics.Analytics.logEvent(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: screen,
            AnalyticsParameterScreenClass: screen,
        ])
    }

    // MARK: Отправка

    func log(_ name: String, _ payload: [String: Any] = [:]) {
        #if DEBUG
        print("[analytics]", name, payload)
        #endif
        guard isActive else { return }
        var payload = payload
        if let screen = screenStack.last { payload["screen"] = screen }
        FirebaseAnalytics.Analytics.logEvent(Self.firebaseName(name), parameters: Self.firebaseParameters(payload))
    }

    /// "taskBuilt" и "task.built" -> "task_built": Firebase разрешает только буквы, цифры и _, до 40 символов.
    static func firebaseName(_ name: String) -> String {
        var result = ""
        var previous: Character = "_"
        for char in name {
            defer { previous = char }
            if char == "." || char == "-" || char == " " {
                if !result.hasSuffix("_") { result.append("_") }
            } else if char.isUppercase {
                if !result.isEmpty && !result.hasSuffix("_") && (previous.isLowercase || previous.isNumber) { result.append("_") }
                result.append(contentsOf: char.lowercased())
            } else if char.isLetter || char.isNumber || char == "_" {
                result.append(char)
            }
        }
        while let first = result.first, !first.isLetter { result.removeFirst() }
        return String(result.prefix(40))
    }

    /// Параметры для Firebase: не больше 25, строки до 100 символов, флаги как 0/1.
    static func firebaseParameters(_ payload: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in payload.sorted(by: { $0.key < $1.key }).prefix(25) {
            let name = firebaseName(key)
            switch value {
            case let flag as Bool: result[name] = flag ? 1 : 0
            case let number as Int: result[name] = number
            case let number as Double: result[name] = number
            case let text as String: result[name] = String(text.prefix(100))
            // другие типы не отправляем: их текстовое описание могло бы унести лишнее
            default: continue
            }
        }
        return result
    }

    static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Неделя первого запуска вида 2026-W48: для когорт удержания.
    static func weekKey(_ date: Date) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
    }
}

extension View {
    /// Отмечает показ экрана (screen_view).
    func analyticsScreen(_ screen: String) -> some View {
        onAppear { Analytics.shared.screenAppeared(screen) }
            .onDisappear { Analytics.shared.screenDisappeared(screen) }
    }
}
