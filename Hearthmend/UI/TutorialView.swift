import SwiftUI
import HearthCore

/// Подсказка Милы внизу поля на время обучения.
struct TutorialTip: View {
    @EnvironmentObject private var store: GameStore
    let openVillage: () -> Void
    @State private var bounce = false

    var body: some View {
        let step = store.game.tutorial
        if step != .done {
            HStack(alignment: .top, spacing: 10) {
                Text("👩‍🌾")
                    .font(.system(size: 34))
                    .offset(y: bounce ? -3 : 2)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("tutorial.\(step)"))
                        .font(Pixel.font(14))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if step == .build {
                            Button(L10n.t("tutorial.go_village"), action: openVillage)
                                .font(Pixel.font(14))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(PixelSlice(key: "ui_btn_green", inset: 5, scale: 2))
                        }
                        Spacer()
                        Button(L10n.t("tutorial.skip")) { store.skipTutorial() }
                            .font(Pixel.font(12))
                            .foregroundColor(Theme.wood.opacity(0.8))
                    }
                }
            }
            .foregroundColor(Theme.text)
            .padding(12)
            .background(PixelSlice(key: "ui_paper", inset: 4))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent, lineWidth: 2))
            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            .padding(.horizontal, 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(step)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { bounce = true }
            }
        }
    }
}
