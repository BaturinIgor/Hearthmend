import SwiftUI
import HearthCore

enum Links {
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacy = URL(string: "https://baturinigor.github.io/hearthmend-legal/privacy.html")!
}

/// Магазин: VIP, стартовый набор, кристаллы за деньги, энергия за кристаллы и монеты, корзина.
struct ShopView: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var shop: StoreManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {
                    wallet
                    if !store.game.isVIP { vipCard } else { vipActive }
                    if !store.game.hasBought(Products.starter) { starterCard }
                    section(L10n.t("shop.gems")) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            gemPack(Products.gemsSmall, icon: "💎")
                            gemPack(Products.gemsMedium, icon: "💎💎")
                            gemPack(Products.gemsLarge, icon: "👝")
                            gemPack(Products.gemsChest, icon: "🧰")
                        }
                    }
                    section(L10n.t("shop.energy")) {
                        VStack(spacing: 8) {
                            ShopRow(icon: "⚡️", title: "+\(store.balance.energyPack)",
                                    button: "💎 \(store.game.energyPackGems)") { store.buyEnergyWithGems() }
                            if let price = store.game.coinEnergyPrice {
                                ShopRow(icon: "⚡️", title: "+\(store.balance.coinEnergyAmount)",
                                        subtitle: L10n.t("shop.coin_energy_hint"),
                                        button: "🪙 \(price)") { store.buyEnergyWithCoins() }
                            } else {
                                ShopRow(icon: "⚡️", title: "+\(store.balance.coinEnergyAmount)",
                                        subtitle: L10n.t("shop.coin_energy_tomorrow"), button: nil) {}
                            }
                        }
                    }
                    if let price = store.game.basketSlotPrice {
                        section(L10n.t("shop.basket")) {
                            ShopRow(icon: "🧺", title: String(format: L10n.t("shop.basket_slot"), store.state.basketSize + 1),
                                    button: "🪙 \(price)") { store.buyBasketSlot() }
                        }
                    }
                    footer
                }
                .padding(14)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(L10n.t("shop.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.close")) { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var wallet: some View {
        HStack(spacing: 16) {
            Text("💎 \(store.state.gems)")
            Text("🪙 \(store.state.coins)")
            Text("⚡️ \(store.state.energy)")
        }
        .font(.system(size: 17, weight: .heavy, design: .rounded))
        .foregroundColor(Theme.text)
    }

    private var vipCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("👑 VIP").font(.system(size: 22, weight: .heavy, design: .rounded))
                Spacer()
                Text(L10n.t("shop.vip_month")).font(.system(size: 13, weight: .semibold, design: .rounded)).opacity(0.8)
            }
            ForEach(["shop.vip_1", "shop.vip_2", "shop.vip_3"], id: \.self) { key in
                Label(L10n.t(key), systemImage: "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            BuyButton(title: priceTitle(Products.vipMonthly, suffix: L10n.t("shop.per_month")),
                      busy: shop.purchasing == Products.vipMonthly) {
                Task { await shop.buy(Products.vipMonthly) }
            }
            Text(L10n.t("shop.vip_terms"))
                .font(.system(size: 11, design: .rounded))
                .opacity(0.7)
        }
        .foregroundColor(Theme.text)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(LinearGradient(colors: [Color(red: 1, green: 0.93, blue: 0.7), Theme.card], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.7), lineWidth: 2))
    }

    private var vipActive: some View {
        HStack {
            Text("👑").font(.system(size: 28))
            VStack(alignment: .leading) {
                Text(L10n.t("shop.vip_active")).font(.system(size: 16, weight: .heavy, design: .rounded))
                if let until = store.state.vipUntil {
                    Text(until, style: .date).font(.system(size: 13, design: .rounded)).opacity(0.8)
                }
            }
            Spacer()
        }
        .foregroundColor(Theme.text)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
    }

    private var starterCard: some View {
        let reward = Products.rewards[Products.starter]!
        return VStack(spacing: 8) {
            Text(L10n.t("shop.starter")).font(.system(size: 20, weight: .heavy, design: .rounded))
            Text("💎 \(reward.gems)   ⚡️ \(reward.energy)   🪙 \(reward.coins)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text(L10n.t("shop.starter_hint")).font(.system(size: 12, design: .rounded)).opacity(0.75)
            BuyButton(title: priceTitle(Products.starter), busy: shop.purchasing == Products.starter) {
                Task { await shop.buy(Products.starter) }
            }
        }
        .foregroundColor(Theme.text)
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent, lineWidth: 2))
    }

    private func gemPack(_ id: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Text(icon).font(.system(size: 30))
            Text("\(Products.rewards[id]?.gems ?? 0)")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.text)
            BuyButton(title: priceTitle(id), busy: shop.purchasing == id) {
                Task { await shop.buy(id) }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.wood.opacity(0.35), lineWidth: 1.5))
    }

    private func priceTitle(_ id: String, suffix: String = "") -> String {
        guard let price = shop.price(id) else { return L10n.t("shop.unavailable") }
        return price + suffix
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.wood)
            content()
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button(L10n.t("shop.restore")) { Task { await shop.restore() } }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            HStack(spacing: 16) {
                Link(L10n.t("shop.terms"), destination: Links.terms)
                Link(L10n.t("shop.privacy"), destination: Links.privacy)
            }
            .font(.system(size: 12, design: .rounded))
        }
        .foregroundColor(Theme.wood)
        .padding(.top, 8)
    }
}

private struct BuyButton: View {
    let title: String
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(busy ? 0 : 1)
                if busy { ProgressView().tint(.white) }
            }
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent))
        }
        .disabled(busy)
    }
}

private struct ShopRow: View {
    let icon: String
    let title: String
    var subtitle: String?
    let button: String?
    let action: () -> Void

    var body: some View {
        HStack {
            Text(icon).font(.system(size: 26))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 17, weight: .heavy, design: .rounded))
                if let subtitle {
                    Text(subtitle).font(.system(size: 12, design: .rounded)).opacity(0.75)
                }
            }
            Spacer()
            if let button {
                Button(action: action) {
                    Text(button)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 38)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.wood))
                }
            }
        }
        .foregroundColor(Theme.text)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
    }
}

// MARK: - Кувшин светлячков

/// Кувшин на поле: светится тем ярче, чем больше в нем энергии. Тап открывает или показывает таймер.
struct JarButton: View {
    @EnvironmentObject private var store: GameStore
    @State private var showInfo = false
    @State private var flicker = false

    var body: some View {
        let fill = Double(store.state.jarEnergy) / Double(max(1, store.balance.jarCapacity))
        Button {
            if store.game.jarFreeIn == nil, store.state.jarEnergy > 0 {
                store.openJar(paid: false)
            } else {
                showInfo = true
            }
        } label: {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Theme.card)
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.yellow.opacity(0.25 + 0.5 * fill))
                    .frame(height: 34 * fill)
                    .padding(2)
                Text("🫙").font(.system(size: 22)).frame(maxHeight: .infinity)
                if fill > 0 {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color.yellow)
                            .frame(width: 4, height: 4)
                            .shadow(color: .yellow, radius: 3)
                            .offset(x: CGFloat(i - 1) * 9, y: flicker ? -22 - CGFloat(i * 3) : -12)
                            .opacity(flicker ? 0.2 : 1)
                    }
                }
            }
            .frame(width: 42, height: 40)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(store.game.jarFreeIn == nil && fill > 0 ? Color.orange : Theme.wood.opacity(0.4), lineWidth: 1.5))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { flicker = true }
        }
        .sheet(isPresented: $showInfo) { JarSheet() }
    }
}

private struct JarSheet: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Text("🫙").font(.system(size: 56))
            Text(L10n.t("jar.title")).font(.system(size: 22, weight: .heavy, design: .rounded))
            Text(L10n.t("jar.about"))
                .font(.system(size: 14, design: .rounded))
                .multilineTextAlignment(.center)
                .opacity(0.8)
            Text("⚡️ \(store.state.jarEnergy) / \(store.balance.jarCapacity)")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
            if let left = store.game.jarFreeIn {
                Text(String(format: L10n.t("jar.free_in"), Self.format(left)))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                if store.state.jarEnergy > 0 {
                    Button {
                        store.openJar(paid: true)
                        dismiss()
                    } label: {
                        Text(store.game.isVIP ? L10n.t("jar.open_vip") : String(format: L10n.t("jar.open_gems"), store.game.jarOpenGems))
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent))
                    }
                }
            } else {
                Text(L10n.t("jar.empty")).font(.system(size: 14, design: .rounded)).opacity(0.8)
            }
        }
        .foregroundColor(Theme.text)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }
}

// MARK: - Ежедневная награда

struct DailyRewardView: View {
    @EnvironmentObject private var store: GameStore
    let close: () -> Void
    @State private var claimed: ProductReward?

    var body: some View {
        let today = store.game.dailyStreakNext % Balance.dailyRewards.count
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(L10n.t("daily.title")).font(.system(size: 22, weight: .heavy, design: .rounded))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(Array(Balance.dailyRewards.enumerated()), id: \.offset) { i, reward in
                        VStack(spacing: 2) {
                            Text(String(format: L10n.t("daily.day"), i + 1))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                            Text(Self.short(reward)).font(.system(size: 13, weight: .heavy, design: .rounded))
                                .minimumScaleFactor(0.6)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(RoundedRectangle(cornerRadius: 10).fill(i == today ? Theme.accent.opacity(0.25) : Theme.card))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(i == today ? Theme.accent : Theme.wood.opacity(0.3), lineWidth: i == today ? 2.5 : 1))
                        .opacity(i < today ? 0.5 : 1)
                        .scaleEffect(i == today && claimed != nil ? 1.12 : 1)
                    }
                }
                Button {
                    if claimed == nil {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { claimed = store.claimDaily() }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: close)
                    } else {
                        close()
                    }
                } label: {
                    Text(claimed == nil ? L10n.t("daily.claim") : "✓")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent))
                }
                if store.game.isVIP {
                    Text(L10n.t("daily.vip")).font(.system(size: 12, weight: .semibold, design: .rounded))
                }
            }
            .foregroundColor(Theme.text)
            .padding(20)
            .frame(maxWidth: 360)
            .background(RoundedRectangle(cornerRadius: 22).fill(Theme.card))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            .padding(20)
        }
    }

    static func short(_ r: ProductReward) -> String {
        var parts: [String] = []
        if r.energy > 0 { parts.append("⚡️\(r.energy)") }
        if r.gems > 0 { parts.append("💎\(r.gems)") }
        if r.coins > 0 { parts.append("🪙\(r.coins)") }
        return parts.joined(separator: " ")
    }
}
