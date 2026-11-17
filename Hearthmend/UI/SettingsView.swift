import SwiftUI
import HearthCore

/// Настройки: звук, музыка, вибрация, покупки, ссылки.
struct SettingsView: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var shop: StoreManager
    @ObservedObject private var audio = Audio.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PixelSheet(L10n.t("settings.title")) {
            ScrollView {
                VStack(spacing: 12) {
                    HStack {
                        Text(String(format: L10n.t("settings.level"), store.state.level))
                            .font(Pixel.font(17))
                        if store.game.isVIP { Text("👑") }
                        Spacer()
                        Text("🏡 \(store.state.completedTasks.count)/\(store.game.village.allTasks.count)")
                            .font(Pixel.font(15))
                    }
                    .woodPanel(padding: 16)
                    VStack(spacing: 10) {
                        toggle("settings.sound", $audio.soundOn)
                        toggle("settings.music", $audio.musicOn)
                        toggle("settings.haptics", $audio.hapticsOn)
                    }
                    .paperPanel(padding: 14)
                    VStack(spacing: 10) {
                        Button(L10n.t("shop.restore")) { Task { await shop.restore() } }
                            .buttonStyle(PixelButtonStyle(kind: .wood, size: 15))
                        HStack(spacing: 18) {
                            Link(L10n.t("shop.privacy"), destination: Links.privacy)
                            Link(L10n.t("shop.terms"), destination: Links.terms)
                        }
                        .font(Pixel.font(13))
                        .foregroundColor(Theme.wood)
                    }
                    .frame(maxWidth: .infinity)
                    .paperPanel(padding: 14)
                    Text("\(L10n.t("settings.version")) \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                        .font(Pixel.font(12))
                        .opacity(0.6)
                }
                .padding(16)
            }
        }
    }

    private func toggle(_ key: String, _ value: Binding<Bool>) -> some View {
        Toggle(isOn: value) { Text(L10n.t(key)).font(Pixel.font(16)) }
            .tint(Theme.accent)
    }
}
