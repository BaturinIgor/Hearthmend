import SwiftUI
import HearthCore

/// Короткая запись больших чисел для шапки: 9 999, 12,4K, 1,25M.
enum Fmt {
    static func compact(_ n: Int) -> String {
        let sep = Locale.current.decimalSeparator ?? "."
        func trim(_ v: Double, _ digits: Int) -> String {
            var s = String(format: "%.\(digits)f", v)
            while s.contains("."), s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
            return s.replacingOccurrences(of: ".", with: sep)
        }
        switch abs(n) {
        case ..<10_000: return "\(n)"
        case ..<100_000: return trim(Double(n) / 1_000, 1) + "K"
        case ..<1_000_000: return "\(n / 1_000)K"
        default: return trim(Double(n) / 1_000_000, 2) + "M"
        }
    }
}

/// Окно «не хватает»: всплывает там, где игрок споткнулся, и сразу предлагает, как пополнить.
/// Закрывается тапом мимо или крестиком.
struct ShortageLayer: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        ZStack {
            if let s = store.shortage {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .onTapGesture { close() }
                    .transition(.opacity)
                ShortageCard(shortage: s, close: close)
                    .padding(.horizontal, 24)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.shortage)
    }

    private func close() { store.shortage = nil }
}

private struct ShortageCard: View {
    @EnvironmentObject private var store: GameStore
    let shortage: Shortage
    let close: () -> Void
    @State private var showShop = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Button(action: close) { PixelIcon(key: "ui_close", size: 30) }
                    .accessibilityLabel(L10n.t("common.close"))
            }
            .padding(.bottom, -18)
            PixelIcon(key: icon, size: 52)
            PixelText(title, size: 20)
                .multilineTextAlignment(.center)
            if let sub = subtitle {
                PixelText(sub, size: 14)
                    .multilineTextAlignment(.center)
                    .opacity(0.75)
            }
            VStack(spacing: 8) { options }
            Button {
                Haptics.light()
                showShop = true
            } label: {
                Text(L10n.t("shortage.shop"))
            }
            .buttonStyle(PixelButtonStyle(kind: .wood, size: 15, compact: true))
        }
        .foregroundColor(Theme.text)
        .padding(20)
        .frame(maxWidth: 340)
        .background(PixelSlice(key: "ui_panel", inset: 6))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .sheet(isPresented: $showShop, onDismiss: close) { ShopView(tab: shortage.isGems ? .gems : .resources) }
    }

    private var icon: String {
        switch shortage {
        case .energy: return "ui_energy"
        case .coins: return "ui_coin"
        case .gems: return "ui_gem"
        }
    }

    private var title: String {
        switch shortage {
        case .energy: return L10n.t("shortage.energy")
        case .coins(let need): return String(format: L10n.t("shortage.coins"), need)
        case .gems(let need): return String(format: L10n.t("shortage.gems"), need)
        }
    }

    private var subtitle: String? {
        switch shortage {
        case .energy:
            guard let next = store.nextEnergyIn else { return nil }
            let missing = max(0, store.balance.energyMax - store.state.energy - 1)
            let s = Int((next + Double(missing) * store.balance.energyRegen).rounded(.up))
            return String(format: L10n.t("shortage.energy_full"), String(format: "%d:%02d", s / 3600, s / 60 % 60))
        case .coins: return L10n.t("shortage.coins_hint")
        case .gems:
            let free = store.journalTotal
            return free > 0 ? String(format: L10n.t("shortage.gems_free"), free) : L10n.t("shortage.gems_hint")
        }
    }

    @ViewBuilder
    private var options: some View {
        switch shortage {
        case .energy:
            row("⚡️ +\(store.balance.energyPack)", price: "💎\(store.game.energyPackGems)", enabled: true) {
                store.buyEnergyWithGems()
                if store.shortage == .energy { close() }
            }
            if let price = store.game.coinEnergyPrice {
                row("⚡️ +\(store.balance.coinEnergyAmount)", price: "🪙\(price)", enabled: true) {
                    store.buyEnergyWithCoins()
                    if store.shortage == .energy { close() }
                }
            }
        case .coins:
            ForEach(Balance.coinPacks, id: \.gems) { pack in
                row("🪙 +\(pack.coins)", price: "💎\(pack.gems)", enabled: true) { store.buyCoins(pack) }
            }
        case .gems:
            EmptyView()
        }
    }

    private func row(_ what: String, price: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            PixelText(what, size: 17)
            Spacer()
            Button(action: action) { PixelText(price, size: 16).lineLimit(1).fixedSize() }
                .buttonStyle(PixelButtonStyle(kind: .green, size: 16, compact: true))
                .disabled(!enabled)
        }
        .padding(10)
        .background(PixelSlice(key: "ui_paper", inset: 4))
    }
}
