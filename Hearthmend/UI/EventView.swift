import SwiftUI
import HearthCore

/// Баннер события на поле: ленточки, сколько осталось до конца, мигает, когда нужен выбор.
struct EventBanner: View {
    @EnvironmentObject private var store: GameStore
    @State private var open = false
    @State private var pulse = false

    var body: some View {
        if let def = store.game.activeEvent {
            let next = def.milestones.first { $0.tokens > store.state.eventTokens }?.tokens ?? def.maxTokens
            Button {
                Haptics.light()
                open = true
            } label: {
                HStack(spacing: 8) {
                    PixelIcon(key: "ui_ribbon", size: (20) * 1.1)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(L10n.t("event.\(def.id).title"))
                                .font(Pixel.font(13))
                            Spacer()
                            if let ends = store.game.eventEndsAt {
                                Text(timeLeft(ends)).font(Pixel.font(11)).opacity(0.7)
                            }
                        }
                        ProgressBar(value: Double(store.state.eventTokens) / Double(max(1, next)), fill: "ui_bar_pink")
                            .frame(height: 12)
                    }
                    Text("\(store.state.eventTokens)/\(next)")
                        .font(Pixel.font(12))
                }
                .foregroundColor(Theme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(PixelSlice(key: "ui_paper_pink", inset: 4))
                .scaleEffect(store.game.eventNeedsChoice && pulse ? 1.03 : 1)
                .overlay(alignment: .topTrailing) { if store.game.eventNeedsChoice { RedDot().offset(x: 3, y: -3) } }
            }
            .padding(.horizontal, 8)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
            }
            .sheet(isPresented: $open) { EventSheet(def: def) }
            .onChange(of: store.eventRewards) { rewards in
                guard !rewards.isEmpty else { return }
                store.show(String(format: L10n.t("event.reward"), rewards.map(Self.describe).joined(separator: " ")))
                store.eventRewards = []
            }
        }
    }

    private func timeLeft(_ ends: Date) -> String {
        let s = max(0, Int(ends.timeIntervalSinceNow))
        if s >= 86400 { return String(format: L10n.t("event.days_left"), s / 86400 + (s % 86400 > 0 ? 1 : 0)) }
        return String(format: "%d:%02d", s / 3600, s / 60 % 60)
    }

    static func describe(_ r: EventReward) -> String {
        var parts: [String] = []
        if r.energy > 0 { parts.append("⚡️\(r.energy)") }
        if r.gems > 0 { parts.append("💎\(r.gems)") }
        if r.coins > 0 { parts.append("🪙\(r.coins)") }
        if r.decor != nil { parts.append("🪴") }
        return parts.joined(separator: " ")
    }
}

/// Экран события: история, выбор жителя и дорожка наград.
struct EventSheet: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var shop: StoreManager
    @Environment(\.dismiss) private var dismiss
    let def: EventDef

    var body: some View {
        PixelSheet(L10n.t("event.\(def.id).title")) {
            ScrollView {
                VStack(spacing: 14) {
                    Text(L10n.t("event.\(def.id).intro"))
                        .font(Pixel.font(15))
                        .multilineTextAlignment(.center)
                    PixelText(L10n.t("event.how"), size: 13)
                        .opacity(0.75)
                        .multilineTextAlignment(.center)
                    choice
                    passBanner
                    track
                }
                .foregroundColor(Theme.text)
                .padding(16)
            }
        }
    }

    @ViewBuilder
    private var choice: some View {
        if let picked = store.state.eventChoice {
            Text(L10n.t("event.\(def.id).after.\(picked)"))
                .font(Pixel.font(14))
                .multilineTextAlignment(.center)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(PixelSlice(key: "ui_paper", inset: 4))
        } else {
            VStack(spacing: 8) {
                Text(L10n.t("event.choose"))
                    .font(Pixel.font(16))
                HStack(spacing: 10) {
                    ForEach(def.choices, id: \.id) { c in
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { store.chooseEvent(c.id) }
                        } label: {
                            VStack(spacing: 6) {
                                ResidentIcon(id: c.id, size: 44)
                                Text(L10n.t("resident.\(c.id)")).font(Pixel.font(15))
                                Text(L10n.t("event.\(def.id).choice.\(c.id)"))
                                    .font(Pixel.font(12))
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                DecorIcon(key: c.decor, size: 36)
                            }
                            .foregroundColor(Theme.text)
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background(PixelSlice(key: "ui_paper_pink", inset: 4))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var passBanner: some View {
        if !store.game.hasEventPass {
            VStack(spacing: 6) {
                Text(L10n.t("shop.pass_hint"))
                    .font(Pixel.font(13))
                    .multilineTextAlignment(.center)
                BuyButton(title: "🎟️ " + (shop.price(Products.eventPass) ?? L10n.t("shop.unavailable")),
                          busy: shop.purchasing == Products.eventPass) {
                    Task { await shop.buy(Products.eventPass) }
                }
            }
            .padding(12)
            .background(PixelSlice(key: "ui_paper_lilac", inset: 4))
        } else {
            PixelText("🎟️ " + L10n.t("shop.pass_active"), size: 15)
                .foregroundColor(.purple)
        }
    }

    private func passReward(_ i: Int) -> some View {
        let pass = store.game.hasEventPass
        let r = Products.eventPassRewards.indices.contains(i) ? Products.eventPassRewards[i] : EventReward()
        return HStack(spacing: 4) {
            if let decor = r.decor { DecorIcon(key: decor, size: 22) }
            PixelText(EventBanner.describe(r), size: 12)
            if !pass { Image(systemName: "lock.fill").font(.system(size: 11)).opacity(0.6) }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(PixelSlice(key: pass ? "ui_paper_lilac" : "ui_paper", inset: 4, scale: 2))
        .opacity(pass ? 1 : 0.7)
    }

    private var track: some View {
        VStack(spacing: 6) {
            ForEach(Array(def.milestones.enumerated()), id: \.offset) { i, m in
                let done = i < store.state.eventClaimed
                HStack {
                    PixelText("🎀 \(m.tokens)", size: 15)
                        .frame(width: 70, alignment: .leading)
                    if m.choiceDecor == true {
                        if let picked = store.state.eventChoice, let c = def.choices.first(where: { $0.id == picked }) {
                            DecorIcon(key: c.decor, size: 26)
                        } else {
                            PixelIcon(key: "ui_question", size: (20) * 1.1)
                        }
                    }
                    if let decor = m.decor { DecorIcon(key: decor, size: 26) }
                    PixelText(EventBanner.describe(EventReward(gems: m.gems ?? 0, energy: m.energy ?? 0, coins: m.coins ?? 0)), size: 12)
                    Spacer()
                    passReward(i)
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(done ? Theme.accent : Theme.wood.opacity(0.4))
                }
                .padding(10)
                .background(PixelSlice(key: done ? "ui_paper_green" : "ui_paper", inset: 4))
            }
        }
    }
}

/// Иконка украшения из спрайтов или запасной значок.
struct DecorIcon: View {
    let key: String
    let size: CGFloat

    var body: some View {
        if let image = Sprites.image(key) {
            Image(uiImage: image).resizable().interpolation(.none).scaledToFit().frame(width: size, height: size)
        } else {
            PixelIcon(key: "ui_plant", size: (size * 0.8) * 1.1)
        }
    }
}
