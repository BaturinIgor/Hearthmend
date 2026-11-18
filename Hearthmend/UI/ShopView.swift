import SwiftUI
import HearthCore

enum Links {
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacy = URL(string: "https://baturinigor.github.io/hearthmend-legal/privacy.html")!
}

/// Разделы лавки. На вкладке красная точка, если там есть что забрать бесплатно.
enum ShopTab: String, CaseIterable, Identifiable {
    case offers, gems, resources, vip
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .offers: return "ui_gift"
        case .gems: return "ui_gem"
        case .resources: return "ui_energy"
        case .vip: return "ui_crown"
        }
    }

    var title: String { L10n.t("shop.tab.\(rawValue)") }
}

/// Лавка: вкладки «Выгодно», «Кристаллы», «Ресурсы», «VIP». Сверху кошелек, снизу восстановление покупок.
struct ShopView: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var shop: StoreManager
    @Environment(\.dismiss) private var dismiss
    @State var tab: ShopTab = .offers

    var body: some View {
        PixelSheet(L10n.t("shop.title")) {
            VStack(spacing: 8) {
                wallet
                tabs.padding(.horizontal, 14)
                ScrollView {
                    VStack(spacing: 14) {
                        switch tab {
                        case .offers: offersTab
                        case .gems: gemsTab
                        case .resources: resourcesTab
                        case .vip: vipTab
                        }
                        footer
                    }
                    .padding(14)
                    .id(tab)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: tab)
        }
    }

    private func dot(_ t: ShopTab) -> Bool {
        switch t {
        case .offers: return store.game.shopGiftReady || store.game.piggyFull
        case .resources: return store.game.coinEnergyPrice.map { store.state.coins >= $0 && store.state.energy < 10 } ?? false
        case .gems, .vip: return false
        }
    }

    private var tabs: some View {
        HStack(spacing: 6) {
            ForEach(ShopTab.allCases) { t in
                Button {
                    Haptics.light()
                    tab = t
                } label: {
                    VStack(spacing: 2) {
                        PixelIcon(key: t.icon, size: 22)
                        Text(t.title).font(Pixel.font(11)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundColor(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(PixelSlice(key: t == tab ? "ui_paper_gold" : "ui_paper", inset: 4, scale: 2))
                    .scaleEffect(t == tab ? 1.04 : 1)
                    .overlay(alignment: .topTrailing) {
                        if dot(t) {
                            Circle().fill(Color(red: 0.86, green: 0.25, blue: 0.3))
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                                .offset(x: 3, y: -3)
                        }
                    }
                }
                .accessibilityLabel(t.title)
            }
        }
    }

    // MARK: - Вкладки

    @ViewBuilder
    private var offersTab: some View {
        giftCard
        offers
        if !store.game.hasBought(Products.starter) { starterCard }
        StampCard()
    }

    private var gemsTab: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            gemPack(Products.gemsSmall, icon: "💎")
            gemPack(Products.gemsMedium, icon: "💎💎", badge: L10n.t("shop.popular"))
            gemPack(Products.gemsLarge, icon: "👝")
            gemPack(Products.gemsChest, icon: "🧰")
            gemPack(Products.gemsHuge, icon: "💰")
            gemPack(Products.gemsMega, icon: "🏰", badge: L10n.t("shop.best"))
        }
    }

    @ViewBuilder
    private var resourcesTab: some View {
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
        section(L10n.t("shop.coins")) {
            VStack(spacing: 8) {
                ForEach(Balance.coinPacks, id: \.gems) { pack in
                    ShopRow(icon: "🪙", title: "+\(pack.coins)", button: "💎 \(pack.gems)") { store.buyCoins(pack) }
                }
            }
        }
        if let price = store.game.basketSlotPrice {
            section(L10n.t("shop.basket")) {
                ShopRow(icon: "🧺", title: String(format: L10n.t("shop.basket_slot"), store.state.basketSize + 1),
                        button: "🪙 \(price)") { store.buyBasketSlot() }
            }
        }
    }

    @ViewBuilder
    private var vipTab: some View {
        if !store.game.isVIP { vipCard } else { vipActive }
    }

    /// Бесплатный подарок дня: повод заглянуть в лавку каждый день.
    private var giftCard: some View {
        let ready = store.game.shopGiftReady
        let gift = store.game.shopGift
        return HStack(spacing: 12) {
            PixelIcon(key: "ui_gift", size: 40)
                .scaleEffect(ready ? 1.06 : 1)
                .animation(ready ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default, value: ready)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("shop.gift")).font(Pixel.font(17))
                Text(ready ? L10n.t("shop.gift_hint") : L10n.t("shop.gift_tomorrow"))
                    .font(Pixel.font(12)).opacity(0.75)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if ready {
                Button { store.claimShopGift() } label: {
                    PixelText(ShopRewardText.short(gift), size: 15).lineLimit(1).fixedSize()
                }
                .buttonStyle(PixelButtonStyle(kind: .green, size: 15, compact: true))
            } else {
                PixelIcon(key: "ui_check", size: 26)
            }
        }
        .foregroundColor(Theme.text)
        .padding(14)
        .background(PixelSlice(key: ready ? "ui_paper_gold" : "ui_paper", inset: 4))
    }

    private var wallet: some View {
        HStack(spacing: 16) {
            PixelText("💎 \(store.state.gems)", size: 14)
            PixelText("🪙 \(store.state.coins)", size: 14)
            PixelText("⚡️ \(store.state.energy)", size: 14)
        }
        .font(Pixel.font(17))
        .foregroundColor(Theme.text)
    }

    // MARK: - Особые предложения

    @ViewBuilder
    private var offers: some View {
        let game = store.game
        let showPass = game.activeEvent != nil && !game.hasEventPass
        let showWeekend = game.canOffer(Products.weekendBundle)
        let showBuilder = game.canOffer(Products.builder)
        VStack(spacing: 10) {
            piggyCard
            if showPass { passCard }
            if showWeekend {
                OfferCard(icon: "🎁", title: L10n.t("shop.weekend"), hint: L10n.t("shop.weekend_hint"),
                          reward: Products.rewards[Products.weekendBundle]!, card: "ui_paper_pink",
                          price: priceTitle(Products.weekendBundle), busy: shop.purchasing == Products.weekendBundle) {
                    Task { await shop.buy(Products.weekendBundle) }
                }
            }
            if showBuilder {
                OfferCard(icon: "🛠️", title: L10n.t("shop.builder"), hint: L10n.t("shop.builder_hint"),
                          reward: Products.rewards[Products.builder]!, card: "ui_paper",
                          price: priceTitle(Products.builder), busy: shop.purchasing == Products.builder) {
                    Task { await shop.buy(Products.builder) }
                }
            }
        }
    }

    private var piggyCard: some View {
        let b = store.balance
        let gems = store.state.piggyGems
        let ready = gems >= b.piggyMin
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                PixelIcon(key: "ui_piggy", size: (34) * 1.1)
                    .scaleEffect(store.game.piggyFull ? 1.08 : 1)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: store.game.piggyFull)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("shop.piggy")).font(Pixel.font(18))
                    Text(store.game.piggyFull ? L10n.t("shop.piggy_full")
                         : String(format: L10n.t("shop.piggy_hint"), b.piggyPerOrder, b.piggyMin))
                        .font(Pixel.font(12)).opacity(0.75)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                PixelText("💎 \(gems)", size: 18)
            }
            ProgressBar(value: Double(gems) / Double(b.piggyMax), fill: "ui_bar_pink").frame(height: 12)
            if ready {
                BuyButton(title: priceTitle(Products.piggy), busy: shop.purchasing == Products.piggy) {
                    Task { await shop.buy(Products.piggy) }
                }
            }
        }
        .foregroundColor(Theme.text)
        .padding(14)
        .background(PixelSlice(key: ready ? "ui_paper_pink" : "ui_paper", inset: 4))
    }

    private var passCard: some View {
        let total = Products.eventPassRewards.reduce(EventReward()) {
            EventReward(gems: $0.gems + $1.gems, energy: $0.energy + $1.energy, coins: $0.coins + $1.coins)
        }
        let decor = Products.eventPassRewards.first { $0.decor != nil }?.decor
        return OfferCard(icon: "🎟️", title: L10n.t("shop.pass"), hint: L10n.t("shop.pass_hint"),
                         reward: ProductReward(gems: total.gems, energy: total.energy, decor: decor), card: "ui_paper_lilac",
                         price: priceTitle(Products.eventPass), busy: shop.purchasing == Products.eventPass) {
            Task { await shop.buy(Products.eventPass) }
        }
    }

    private var vipCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PixelText("👑 VIP", size: 22)
                Spacer()
                Text(L10n.t("shop.vip_month")).font(Pixel.font(13)).opacity(0.8)
            }
            ForEach(["shop.vip_1", "shop.vip_2", "shop.vip_3"], id: \.self) { key in
                Label(L10n.t(key), systemImage: "checkmark.seal.fill")
                    .font(Pixel.font(14))
            }
            BuyButton(title: priceTitle(Products.vipMonthly, suffix: L10n.t("shop.per_month")),
                      busy: shop.purchasing == Products.vipMonthly) {
                Task { await shop.buy(Products.vipMonthly) }
            }
            Text(L10n.t("shop.vip_terms"))
                .font(Pixel.font(11))
                .opacity(0.7)
        }
        .foregroundColor(Theme.text)
        .padding(14)
        .background(PixelSlice(key: "ui_paper_gold", inset: 4))
    }

    private var vipActive: some View {
        HStack {
            PixelIcon(key: "ui_crown", size: (28) * 1.1)
            VStack(alignment: .leading) {
                Text(L10n.t("shop.vip_active")).font(Pixel.font(16))
                if let until = store.state.vipUntil {
                    Text(until, style: .date).font(Pixel.font(13)).opacity(0.8)
                }
            }
            Spacer()
        }
        .foregroundColor(Theme.text)
        .padding(14)
        .background(PixelSlice(key: "ui_paper", inset: 4))
    }

    private var starterCard: some View {
        let reward = Products.rewards[Products.starter]!
        return VStack(spacing: 8) {
            Text(L10n.t("shop.starter")).font(Pixel.font(20))
            PixelText("💎 \(reward.gems)   ⚡️ \(reward.energy)   🪙 \(reward.coins)", size: 14)
                .font(Pixel.font(16))
            Text(L10n.t("shop.starter_hint")).font(Pixel.font(12)).opacity(0.75)
            BuyButton(title: priceTitle(Products.starter), busy: shop.purchasing == Products.starter) {
                Task { await shop.buy(Products.starter) }
            }
        }
        .foregroundColor(Theme.text)
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(PixelSlice(key: "ui_paper_green", inset: 4))
    }

    private func gemPack(_ id: String, icon: String, badge: String? = nil) -> some View {
        let bonus = Products.gemBonus(id)
        return VStack(spacing: 6) {
            PixelText(icon, size: 26)
            Text("\(Products.rewards[id]?.gems ?? 0)")
                .font(Pixel.font(18))
                .foregroundColor(Theme.text)
            Text(bonus > 0 ? String(format: L10n.t("shop.bonus"), bonus) : " ")
                .font(Pixel.font(12))
                .foregroundColor(Color(red: 0.2, green: 0.55, blue: 0.25))
            BuyButton(title: priceTitle(id), busy: shop.purchasing == id) {
                Task { await shop.buy(id) }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(PixelSlice(key: badge != nil ? "ui_paper_gold" : "ui_paper", inset: 4))
        .overlay(alignment: .top) {
            if let badge {
                Text(badge)
                    .font(Pixel.font(11))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(red: 0.86, green: 0.25, blue: 0.3)))
                    .offset(y: -9)
            }
        }
        .padding(.top, badge != nil ? 6 : 0)
    }

    private func priceTitle(_ id: String, suffix: String = "") -> String {
        guard let price = shop.price(id) else { return L10n.t("shop.unavailable") }
        return price + suffix
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Pixel.font(15))
                .foregroundColor(Theme.wood)
            content()
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button(L10n.t("shop.restore")) { Task { await shop.restore() } }
                .font(Pixel.font(14))
            HStack(spacing: 16) {
                Link(L10n.t("shop.terms"), destination: Links.terms)
                Link(L10n.t("shop.privacy"), destination: Links.privacy)
            }
            .font(Pixel.font(12))
        }
        .foregroundColor(Theme.wood)
        .padding(.top, 8)
    }
}

/// Карточка набора: что внутри и кнопка с ценой.
struct OfferCard: View {
    let icon: String
    let title: String
    let hint: String
    let reward: ProductReward
    /// Рамка карточки: ui_paper или ее цветной вариант.
    let card: String
    let price: String
    var busy = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                EmojiIcon(icon, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Pixel.font(18))
                    Text(hint).font(Pixel.font(12)).opacity(0.75)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            // что внутри: крупные плитки, а не строчка мелких значков
            HStack(spacing: 8) {
                if reward.gems > 0 { RewardChip(icon: "ui_gem", value: "\(reward.gems)") }
                if reward.energy > 0 { RewardChip(icon: "ui_energy", value: "\(reward.energy)") }
                if reward.coins > 0 { RewardChip(icon: "ui_coin", value: Fmt.compact(reward.coins)) }
                if reward.stars > 0 { RewardChip(icon: "ui_star", value: "\(reward.stars)") }
                if let decor = reward.decor { RewardChip(decor: decor) }
                Spacer(minLength: 0)
            }
            BuyButton(title: price, busy: busy, action: action)
        }
        .foregroundColor(Theme.text)
        .padding(14)
        .background(PixelSlice(key: card, inset: 4))
    }
}

/// Плитка награды в карточке покупки: большая иконка и число под ней.
struct RewardChip: View {
    var icon: String?
    var value: String?
    var decor: String?

    var body: some View {
        VStack(spacing: 2) {
            if let decor {
                DecorIcon(key: decor, size: 30)
            } else if let icon {
                PixelIcon(key: icon, size: 26)
            }
            if let value { PixelText(value, size: 14) }
        }
        .frame(minWidth: 54, minHeight: 50)
        .padding(.horizontal, 4)
        .background(PixelSlice(key: "ui_paper", inset: 4, scale: 2))
    }
}

struct BuyButton: View {
    let title: String
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                PixelText(title, size: 16).opacity(busy ? 0 : 1)
                if busy { ProgressView().tint(.white) }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(PixelSlice(key: "ui_btn_green", inset: 5))
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
            PixelText(icon, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Pixel.font(17))
                if let subtitle {
                    Text(subtitle).font(Pixel.font(12)).opacity(0.75)
                }
            }
            Spacer()
            if let button {
                Button(action: action) {
                    PixelText(button, size: 15)
                        .font(Pixel.font(15))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 38)
                        .background(PixelSlice(key: "ui_btn_wood", inset: 5, scale: 3))
                }
            }
        }
        .foregroundColor(Theme.text)
        .padding(12)
        .background(PixelSlice(key: "ui_paper", inset: 4))
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
                PixelIcon(key: "ui_jar", size: (22) * 1.1).frame(maxHeight: .infinity)
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

struct JarSheet: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PixelSheet(L10n.t("jar.title")) {
        VStack(spacing: 14) {
            PixelIcon(key: "ui_jar", size: 60)
            Text(L10n.t("jar.about"))
                .font(Pixel.font(14))
                .multilineTextAlignment(.center)
                .opacity(0.8)
            PixelText("⚡️ \(store.state.jarEnergy) / \(store.balance.jarCapacity)", size: 20)
            if let left = store.game.jarFreeIn {
                Text(String(format: L10n.t("jar.free_in"), Self.format(left)))
                    .font(Pixel.font(14))
                if store.state.jarEnergy > 0 {
                    Button {
                        store.openJar(paid: true)
                        dismiss()
                    } label: {
                        PixelText(store.game.isVIP ? L10n.t("jar.open_vip") : String(format: L10n.t("jar.open_gems"), store.game.jarOpenGems), size: 17)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(PixelSlice(key: "ui_btn_green", inset: 5))
                    }
                }
            } else if store.state.jarEnergy > 0 {
                Button {
                    store.openJar(paid: false)
                    dismiss()
                } label: {
                    PixelText(L10n.t("jar.open_free"), size: 17)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(PixelSlice(key: "ui_btn_green", inset: 5))
                }
            } else {
                Text(L10n.t("jar.empty")).font(Pixel.font(14)).opacity(0.8)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
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
                Text(L10n.t("daily.title")).font(Pixel.font(22))
                let days = Balance.dailyRewards
                // шесть одинаковых карточек и седьмая - большой подарок во всю ширину
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(0..<(days.count - 1), id: \.self) { i in
                        dayCard(i, days[i], today: today)
                            .frame(maxWidth: .infinity)
                            .frame(height: 70)
                    }
                }
                let last = days.count - 1
                HStack(spacing: 12) {
                    PixelIcon(key: "ui_chest", size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: L10n.t("daily.day"), last + 1)).font(Pixel.font(14))
                        PixelText(Self.short(days[last]), size: 16).lineLimit(1).fixedSize()
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(height: 70)
                .background(PixelSlice(key: last == today ? "ui_paper_green" : "ui_paper_gold", inset: 4))
                .opacity(last < today ? 0.5 : 1)
                .scaleEffect(last == today && claimed != nil ? 1.06 : 1)
                Button {
                    if claimed == nil {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { claimed = store.claimDaily() }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: close)
                    } else {
                        close()
                    }
                } label: {
                    PixelText(claimed == nil ? L10n.t("daily.claim") : "✓", size: 18)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(PixelSlice(key: "ui_btn_green", inset: 5))
                }
                if store.game.isVIP {
                    PixelText(L10n.t("daily.vip"), size: 12)
                }
            }
            .foregroundColor(Theme.text)
            .padding(20)
            .frame(maxWidth: 360)
            .background(PixelSlice(key: "ui_paper", inset: 4))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            .padding(20)
        }
    }

    private func dayCard(_ i: Int, _ reward: ProductReward, today: Int) -> some View {
        VStack(spacing: 4) {
            Text(String(format: L10n.t("daily.day"), i + 1)).font(Pixel.font(13))
            PixelText(Self.short(reward), size: 16).lineLimit(1).fixedSize()
        }
        .background(Color.clear)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PixelSlice(key: i == today ? "ui_paper_green" : "ui_paper", inset: 4))
        .opacity(i < today ? 0.5 : 1)
        .scaleEffect(i == today && claimed != nil ? 1.12 : 1)
    }

    static func short(_ r: ProductReward) -> String {
        var parts: [String] = []
        if r.energy > 0 { parts.append("⚡️\(r.energy)") }
        if r.gems > 0 { parts.append("💎\(r.gems)") }
        if r.coins > 0 { parts.append("🪙\(r.coins)") }
        return parts.joined(separator: " ")
    }
}

/// Карточка штампов: каждая покупка ставит штамп, за полную карточку кристаллы и украшение.
struct StampCard: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        let b = store.balance
        let have = store.state.stamps
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.t("shop.stamps")).font(Pixel.font(17))
                Spacer()
                Text("\(have)/\(b.stampsPerCard)").font(Pixel.font(14)).opacity(0.7)
            }
            HStack(spacing: 6) {
                ForEach(0..<b.stampsPerCard, id: \.self) { i in
                    let last = i == b.stampsPerCard - 1
                    ZStack {
                        Circle()
                            .strokeBorder(Theme.wood.opacity(i < have ? 0.9 : 0.35), style: StrokeStyle(lineWidth: 2, dash: i < have ? [] : [4, 3]))
                            .background(Circle().fill(i < have ? Color(red: 0.98, green: 0.84, blue: 0.55) : Color.white.opacity(0.5)))
                        if i < have {
                            PixelIcon(key: "ui_rosette", size: (22) * 1.1).transition(.scale(scale: 2.2).combined(with: .opacity))
                        } else if last {
                            PixelIcon(key: "ui_gift", size: (20) * 1.1).opacity(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .rotationEffect(.degrees(i < have ? Double((i * 37) % 17) - 8 : 0))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.55), value: have)
            PixelText(String(format: L10n.t("shop.stamps_hint"), b.stampsPerCard, b.stampCardGems), size: 12).opacity(0.75)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(Theme.text)
        .padding(14)
        .background(PixelSlice(key: "ui_paper", inset: 4))
    }
}
