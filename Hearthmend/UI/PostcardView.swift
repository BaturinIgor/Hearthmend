import SwiftUI
import HearthCore

/// Открытка с видом деревни, собранная из кусочков. Кусочки открываются в перемешанном порядке,
/// закрытые лежат пергаментом.
struct PostcardSheet: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    /// Порядок открытия кусочков 3x3: не по строкам, чтобы картинка проявлялась интереснее.
    private static let order = [4, 0, 8, 2, 6, 1, 7, 3, 5]

    var body: some View {
        let total = store.balance.postcardPieces
        let opened = store.state.postcardPieces
        let view = store.game.postcardView
        let decor = Postcards.decor[store.state.postcardIndex % Postcards.decor.count]
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {
                    Text(L10n.t("district.\(view)"))
                        .font(Pixel.font(20))
                    picture(view: view, opened: opened, total: total)
                    ProgressBar(value: Double(opened) / Double(total)).frame(height: 10)
                    Text(String(format: L10n.t("postcard.progress"), opened, total))
                        .font(Pixel.font(14))
                    Text(L10n.t("postcard.how"))
                        .font(.system(size: 13, design: .rounded))
                        .multilineTextAlignment(.center)
                        .opacity(0.8)
                    HStack(spacing: 14) {
                        PixelText("💎 \(store.balance.postcardGems)", size: 14)
                        PixelText("🪙 \(store.balance.postcardCoins)", size: 14)
                        DecorIcon(key: decor, size: 30)
                    }
                    .font(Pixel.font(17))
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(PixelSlice(key: "ui_paper", inset: 4))
                    Text(String(format: L10n.t("postcard.collected"), store.state.postcardIndex))
                        .font(.system(size: 12, design: .rounded))
                        .opacity(0.6)
                }
                .foregroundColor(Theme.text)
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(L10n.t("postcard.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L10n.t("common.close")) { dismiss() } }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func picture(view: String, opened: Int, total: Int) -> some View {
        let shown = Set(Self.order.prefix(min(opened, Self.order.count)))
        return GeometryReader { geo in
            let w = geo.size.width / 3, h = geo.size.height / 3
            ZStack(alignment: .topLeading) {
                if let image = Sprites.image("postcard_\(view)") {
                    Image(uiImage: image).resizable().interpolation(.none)
                } else {
                    LinearGradient(colors: [Color(red: 0.45, green: 0.66, blue: 0.33), Color(red: 0.36, green: 0.55, blue: 0.29)],
                                   startPoint: .top, endPoint: .bottom)
                }
                ForEach(0..<9, id: \.self) { i in
                    if !shown.contains(i) {
                        ZStack {
                            Rectangle().fill(Color(red: 0.93, green: 0.86, blue: 0.70))
                            Rectangle().stroke(Theme.wood.opacity(0.35), lineWidth: 1)
                            Text("?").font(Pixel.font(26)).foregroundColor(Theme.wood.opacity(0.4))
                        }
                        .frame(width: w, height: h)
                        .offset(x: CGFloat(i % 3) * w, y: CGFloat(i / 3) * h)
                        .transition(.opacity.combined(with: .scale(scale: 1.15)))
                    }
                }
            }
            .animation(.easeOut(duration: 0.5), value: opened)
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white, lineWidth: 6))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        .rotationEffect(.degrees(-1.5))
        .padding(.horizontal, 6)
    }
}
