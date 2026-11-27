import SwiftUI
import UIKit

@main
struct HearthmendApp: App {
    @StateObject private var store = GameStore()
    @StateObject private var shop = StoreManager()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            Group {
                if Shot.isQA, let name = Shot.name {
                    QAScreen(name: name)
                } else if Shot.hasCaption, let name = Shot.name {
                    ShotFrame(name: name)
                } else {
                    ContentView()
                }
            }
                .environmentObject(store)
                .environmentObject(shop)
                .preferredColorScheme(.light)
                .font(Pixel.font(16))
                .onAppear {
                    Analytics.shared.start(store.state)
                    // первый переход в active мог случиться до onAppear: оба вызова считают раз в день
                    if !GameStore.isDemo {
                        ReviewPrompt.appBecameActive()
                        Analytics.shared.appBecameActive(store.game)
                    }
                    shop.attach(store)
                    Audio.shared.startMusic()
                }
        }
        .onChange(of: phase) { p in
            if p != .active { store.flush() }
            if p == .active, !GameStore.isDemo {
                ReviewPrompt.appBecameActive()
                Analytics.shared.appBecameActive(store.game)
            }
        }
    }
}

@MainActor
enum Haptics {
    private static var on: Bool { UserDefaults.standard.object(forKey: "hapticsOn") as? Bool ?? true }

    private static let impact = UIImpactFeedbackGenerator(style: .light)
    private static let notify = UINotificationFeedbackGenerator()

    static func light() {
        guard on else { return }
        impact.impactOccurred()
        impact.prepare()
    }

    static func success() {
        guard on else { return }
        notify.notificationOccurred(.success)
        notify.prepare()
    }

    static func warning() {
        guard on else { return }
        notify.notificationOccurred(.warning)
        notify.prepare()
    }
}

/// Строки интерфейса из Resources/Strings/<язык>.json, как в GameFarm и Sortelier.
/// Пока два языка, остальные 15 добавим вместе с текстами деревни.
enum L10n {
    private static let table: [String: String] = {
        let preferred = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en"
        return load(preferred) ?? load("en") ?? [:]
    }()

    private static let fallback: [String: String] = load("en") ?? [:]

    private static func load(_ lang: String) -> [String: String]? {
        guard let url = Bundle.main.url(forResource: lang, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    static func t(_ key: String) -> String {
        table[key] ?? fallback[key] ?? key
    }
}
