import SwiftUI
import UIKit
import HearthCore

/// Адрес поддержки и ссылка mailto (как в ZenHab).
enum Support {
    static let email = "dawnwell.app+hearthmend@gmail.com"

    static func mailtoURL(subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        // URLComponents не кодирует «+», а почтовые клиенты читают его как пробел: письмо ушло бы не туда
        components.percentEncodedPath = email.replacingOccurrences(of: "+", with: "%2B")
        components.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    /// Модель устройства вида iPhone15,2.
    static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// Техническая часть письма: без личного, только версия, устройство и прогресс.
    @MainActor
    static func details(_ store: GameStore) -> String {
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
        let s = store.state
        return """
        Hearthmend \(version)
        iOS \(UIDevice.current.systemVersion), \(deviceModel)
        \(Locale.preferredLanguages.first ?? "")
        Level \(s.level), tasks \(s.completedTasks.count), district \(store.game.currentDistrict?.id ?? "complete")
        """
    }
}

/// «Написать разработчику»: что случилось, текст, отправка в Telegram-бот, а без бота - письмом.
struct FeedbackView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    enum Kind: String, CaseIterable, Identifiable {
        case bug, idea, other
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .bug: return "🐞"
            case .idea: return "💡"
            case .other: return "💬"
            }
        }
    }

    @State private var kind: Kind = .idea
    @State private var text = ""
    @State private var sending = false
    @State private var error: String?

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        PixelSheet(L10n.t("feedback.title")) {
            ScrollView {
                VStack(spacing: 12) {
                    Text(L10n.t("feedback.intro"))
                        .font(Pixel.font(14))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        ForEach(Kind.allCases) { k in
                            Button { kind = k } label: {
                                Text("\(k.icon) \(L10n.t("feedback.kind.\(k.rawValue)"))")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PixelButtonStyle(kind: kind == k ? .green : .wood, size: 13, compact: true))
                            .accessibilityAddTraits(kind == k ? .isSelected : [])
                        }
                    }
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $text)
                            .font(Pixel.font(15))
                            .frame(minHeight: 160)
                            .accessibilityLabel(L10n.t("feedback.placeholder"))
                        if text.isEmpty {
                            Text(L10n.t("feedback.placeholder"))
                                .font(Pixel.font(15))
                                .opacity(0.45)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
                    .paperPanel(padding: 8)
                    Text(L10n.t("feedback.details"))
                        .font(Pixel.font(12))
                        .opacity(0.6)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if let error {
                        Text(error).font(Pixel.font(13)).foregroundColor(Theme.accent)
                    }
                    Button(sending ? L10n.t("feedback.sending") : L10n.t("feedback.send")) { send() }
                        .buttonStyle(PixelButtonStyle(kind: .green, size: 17))
                        .disabled(trimmed.isEmpty || sending)
                        .opacity(trimmed.isEmpty ? 0.6 : 1)
                }
                .padding(16)
            }
        }
        .analyticsScreen("Feedback")
    }

    private var subject: String { "Hearthmend: \(L10n.t("feedback.kind.\(kind.rawValue)"))" }

    private func send() {
        let message = "[\(kind.rawValue)] \(trimmed)\n\n\(Support.details(store))"
        guard TelegramFeedback.isConfigured else {
            sendByMail(message)
            return
        }
        sending = true
        error = nil
        Task {
            do {
                try await TelegramFeedback.send(text: message, screenshot: nil)
                Analytics.shared.feedbackSent(kind: kind.rawValue, via: "telegram")
                store.show(L10n.t("feedback.thanks"))
                dismiss()
            } catch {
                // бот недоступен (нет сети, Telegram закрыт): предлагаем почту
                sending = false
                sendByMail(message)
            }
        }
    }

    private func sendByMail(_ message: String) {
        guard let url = Support.mailtoURL(subject: subject, body: message) else { return }
        openURL(url) { opened in
            if opened {
                Analytics.shared.feedbackSent(kind: kind.rawValue, via: "mail")
                dismiss()
            } else {
                // нет почты на устройстве: адрес в буфер, игрок напишет сам
                UIPasteboard.general.string = Support.email
                error = String(format: L10n.t("feedback.no_mail"), Support.email)
            }
        }
    }
}
