import SwiftUI
import HearthCore

/// «Обмен» на выходных: дорожка вещей от веточки до прилавка и три предложения жителей.
struct BarterSheet: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var bob = false
    @State private var flash: Int?

    var body: some View {
        PixelSheet(L10n.t("barter.title")) {
            ScrollView {
                VStack(spacing: 12) {
                    if let b = store.game.barter {
                        Text(L10n.t("barter.intro"))
                            .font(Pixel.font(14))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        trail(b)
                        if b.finished {
                            finished(b)
                        } else {
                            current(b)
                            ForEach(Array(b.offers.enumerated()), id: \.offset) { i, offer in
                                card(offer, index: i, good: b.good, last: b.step == Barter.steps - 1)
                                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                            removal: .scale(scale: 0.8).combined(with: .opacity)))
                            }
                            .id(b.step)
                            tentHint(b)
                        }
                        if let ends = store.game.barterEndsAt {
                            PixelText(String(format: L10n.t("barter.ends"), timeLeft(ends)), size: 12).opacity(0.65)
                        }
                    }
                }
                .foregroundColor(Theme.text)
                .padding(16)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { bob = true }
        }
    }

    // MARK: - Дорожка

    private func trail(_ b: BarterState) -> some View {
        HStack(spacing: 2) {
            ForEach(0...Barter.steps, id: \.self) { i in
                let have = i < b.trail.count
                ZStack {
                    Circle().fill(i == b.step && !b.finished ? Color.white : Theme.card)
                    Circle().stroke(i == b.step ? Theme.accent : Theme.wood.opacity(0.35), lineWidth: i == b.step ? 2.5 : 1.5)
                    if have {
                        DecorIcon(key: b.trail[i], size: 22)
                    } else if i == Barter.steps {
                        DecorIcon(key: "decor_stall_red", size: 22).saturation(0).opacity(0.35)
                    } else {
                        PixelIcon(key: "ui_question", size: 14).opacity(0.4)
                    }
                }
                .frame(width: 32, height: 32)
                .scaleEffect(i == b.step && !b.finished && bob ? 1.08 : 1)
                if i < Barter.steps {
                    Rectangle().fill(i < b.step ? Theme.accent : Theme.wood.opacity(0.25)).frame(height: 3)
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: b.step)
    }

    private func current(_ b: BarterState) -> some View {
        HStack(spacing: 8) {
            PixelText(L10n.t("barter.have"), size: 14)
            DecorIcon(key: b.good, size: 34)
                .offset(y: bob ? -2 : 1)
            Spacer()
            PixelText("\(b.step)/\(Barter.steps)", size: 14).opacity(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(PixelSlice(key: "ui_paper", inset: 4))
    }

    // MARK: - Предложение

    private func card(_ offer: BarterOffer, index: Int, good: String, last: Bool) -> some View {
        let can = store.game.canBarter(index)
        return HStack(spacing: 10) {
            VStack(spacing: 2) {
                ResidentIcon(id: offer.friend, size: 40)
                PixelText(L10n.t("resident.\(offer.friend)"), size: 12)
            }
            .frame(width: 62)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    DecorIcon(key: good, size: 24)
                    PixelText("+", size: 14)
                    ZStack(alignment: .bottomTrailing) {
                        ItemIcon(item: offer.needs, size: 28)
                        TierBadge(tier: offer.needs.tier)
                    }
                    .frame(width: 32, height: 32)
                    Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold)).opacity(0.6)
                    DecorIcon(key: offer.gives, size: last ? 38 : 30)
                        .scaleEffect(flash == index ? 1.25 : 1)
                }
                HStack(spacing: 6) {
                    HStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { s in
                            PixelIcon(key: "ui_star", size: 13).opacity(s <= offer.level ? 1 : 0.2)
                        }
                    }
                    PixelText(ShopRewardText.short(ProductReward(energy: offer.energy, coins: offer.coins)), size: 12)
                }
            }
            Spacer(minLength: 0)
            Button {
                trade(index)
            } label: {
                PixelText(L10n.t("barter.swap"), size: 14)
            }
            .buttonStyle(PixelButtonStyle(kind: can ? .green : .wood, size: 14))
            .opacity(can ? 1 : 0.7)
        }
        .padding(10)
        .background(PixelSlice(key: offer.level == 2 ? "ui_paper_gold" : "ui_paper", inset: 4))
        .overlay(alignment: .topTrailing) { if can { RedDot().offset(x: 3, y: -3) } }
    }

    private func trade(_ index: Int) {
        guard store.game.canBarter(index) else {
            store.barter(index) // подсветит нужный предмет на поле и подскажет
            dismiss()
            return
        }
        flash = index
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                flash = nil
                store.barter(index)
            }
        }
    }

    // MARK: - Подсказки и итог

    private func tentHint(_ b: BarterState) -> some View {
        let reached = b.value >= Barter.tentValue
        return HStack(spacing: 8) {
            DecorIcon(key: Barter.tent, size: 30)
                .saturation(reached ? 1 : 0.2)
            VStack(alignment: .leading, spacing: 4) {
                PixelText(L10n.t("barter.tent"), size: 12)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressBar(value: min(1, Double(b.value) / Double(Barter.tentValue)), fill: "ui_bar_fill")
                    .frame(height: 10)
            }
            PixelText("\(min(b.value, Barter.tentValue))/\(Barter.tentValue)", size: 12)
        }
        .padding(10)
        .background(PixelSlice(key: "ui_paper_lilac", inset: 4))
    }

    private func finished(_ b: BarterState) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 14) {
                if let stall = b.stall { DecorIcon(key: stall, size: 72) }
                if b.tent { DecorIcon(key: Barter.tent, size: 72) }
            }
            .scaleEffect(bob ? 1.04 : 0.98)
            Text(L10n.t("barter.done"))
                .font(Pixel.font(18))
            PixelText(L10n.t("barter.done_hint") + "   💎 \(b.gems)", size: 13)
                .multilineTextAlignment(.center)
                .opacity(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(PixelSlice(key: "ui_paper_green", inset: 4))
        .transition(.scale.combined(with: .opacity))
    }

    private func timeLeft(_ ends: Date) -> String {
        let s = max(0, Int(ends.timeIntervalSince(store.game.now())))
        if s >= 86400 { return String(format: L10n.t("event.days_left"), s / 86400 + (s % 86400 > 0 ? 1 : 0)) }
        return String(format: "%d:%02d", s / 3600, s / 60 % 60)
    }
}
