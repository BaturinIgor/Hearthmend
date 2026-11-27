import Foundation
import HearthCore
import StoreKit
import UIKit

/// Системный запрос оценки в App Store. Просим в удачный момент: игрок только что закрыл праздник
/// (новый уровень, житель, отстроенный район), обучение пройдено, он играет хотя бы второй день
/// и дошел до 4-го уровня. Не чаще раза на версию и раз в 60 дней; сам Apple показывает окно не больше 3 раз в год.
@MainActor
enum ReviewPrompt {
    static let minLevel = 4
    static let minDays = 2
    static let minGapDays = 60

    private enum Key {
        static let days = "review.daysPlayed"
        static let lastDay = "review.lastDay"
        static let version = "review.promptedVersion"
        static let date = "review.promptedAt"
    }

    private static let defaults = UserDefaults.standard
    private static var pending = false

    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    /// Разные дни, в которые игрок открывал игру.
    static var daysPlayed: Int { defaults.integer(forKey: Key.days) }

    static func appBecameActive() {
        let today = Analytics.dayKey(Date())
        guard defaults.string(forKey: Key.lastDay) != today else { return }
        defaults.set(today, forKey: Key.lastDay)
        defaults.set(daysPlayed + 1, forKey: Key.days)
    }

    /// Можно ли сейчас просить оценку (без побочных эффектов).
    static func allowed(level: Int, tutorialDone: Bool, days: Int, promptedVersion: String?, currentVersion: String,
                        lastPrompt: Date?, now: Date = Date()) -> Bool {
        guard tutorialDone, level >= minLevel, days >= minDays, promptedVersion != currentVersion else { return false }
        if let lastPrompt, now.timeIntervalSince(lastPrompt) < Double(minGapDays) * 86_400 { return false }
        return true
    }

    static func celebrationClosed(_ game: Game) {
        guard !GameStore.isDemo, !Shot.isActive, !pending,
              allowed(level: game.state.level, tutorialDone: game.tutorial == .done, days: daysPlayed,
                      promptedVersion: defaults.string(forKey: Key.version), currentVersion: version,
                      lastPrompt: defaults.object(forKey: Key.date) as? Date) else { return }
        pending = true
        let level = game.state.level
        // после анимации закрытия праздника, чтобы окно не наложилось на него
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            pending = false
            guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
            defaults.set(version, forKey: Key.version)
            defaults.set(Date(), forKey: Key.date)
            SKStoreReviewController.requestReview(in: scene)
            Analytics.shared.reviewPromptShown(level: level, days: daysPlayed)
        }
    }
}
