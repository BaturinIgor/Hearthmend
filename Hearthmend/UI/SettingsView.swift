import SwiftUI
import HearthCore

/// Настройки: звук, музыка, вибрация, покупки, ссылки.
struct SettingsView: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var shop: StoreManager
    @ObservedObject private var audio = Audio.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Text(String(format: L10n.t("settings.level"), store.state.level))
                            .font(Pixel.font(17))
                        if store.game.isVIP { Text("👑") }
                        Spacer()
                        Text("🏡 \(store.state.completedTasks.count)/\(store.game.village.allTasks.count)")
                            .font(Pixel.font(15))
                    }
                }
                Section {
                    Toggle(L10n.t("settings.sound"), isOn: $audio.soundOn)
                    Toggle(L10n.t("settings.music"), isOn: $audio.musicOn)
                    Toggle(L10n.t("settings.haptics"), isOn: $audio.hapticsOn)
                }
                Section {
                    Button(L10n.t("shop.restore")) { Task { await shop.restore() } }
                    Link(L10n.t("shop.privacy"), destination: Links.privacy)
                    Link(L10n.t("shop.terms"), destination: Links.terms)
                }
                Section {
                    HStack {
                        Text(L10n.t("settings.version"))
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(L10n.t("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L10n.t("common.close")) { dismiss() } }
            }
        }
        .navigationViewStyle(.stack)
    }
}
