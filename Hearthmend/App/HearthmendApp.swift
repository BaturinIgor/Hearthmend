import SwiftUI
import UIKit

@main
struct HearthmendApp: App {
    @StateObject private var store = GameStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.light)
        }
    }
}

enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
