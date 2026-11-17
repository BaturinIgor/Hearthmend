import SwiftUI
import HearthCore

/// Кто просит заказ: житель, связанный с цепочкой первого предмета.
enum Residents {
    static var byChain: [String: String] { Friends.byChain }

    static func requester(of order: Order) -> String { Friends.requester(of: order) }
}

/// Кнопка внизу поля со значком и красной точкой, если есть что забрать.
struct BadgeButton: View {
    let icon: String
    let count: Int
    var label: String?
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 3) {
                PixelIcon(key: icon, size: 22)
                if let label { PixelText(label, size: 13).lineLimit(1).fixedSize() }
            }
            .foregroundColor(Theme.text)
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(PixelSlice(key: count > 0 ? "ui_paper_gold" : "ui_paper", inset: 4, scale: 2))
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text("\(count)")
                        .font(Pixel.digits(12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                        .background(Circle().fill(Color(red: 0.86, green: 0.25, blue: 0.3)).frame(minWidth: 18, minHeight: 18))
                        .offset(x: 6, y: -6)
                        .transition(.scale)
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: count)
    }
}

/// Задания дня: три задачи с полосками, награда за каждую и сундук за все.
struct QuestsPage: View {
    @EnvironmentObject private var store: GameStore
    @State private var now: Date?
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(String(format: L10n.t("quests.reset"), timeLeft))
                    .font(Pixel.body(13))
                    .opacity(0.7)
                ForEach(Array(store.quests.enumerated()), id: \.offset) { i, q in
                    row(i, q)
                }
                chest
            }
            .padding(16)
        }
        .onReceive(timer) { _ in now = store.game.now() }
    }

    private var timeLeft: String {
        let next = Date(timeIntervalSince1970: Double(store.game.questDay + 1) * 86_400)
        let s = max(0, Int(next.timeIntervalSince(now ?? store.game.now())))
        return String(format: "%d:%02d", s / 3600, (s % 3600) / 60)
    }

    private func icon(_ kind: QuestKind) -> String {
        switch kind {
        case .merge: return "ui_star"
        case .spawn: return "ui_crate"
        case .deliver: return "ui_basket"
        case .bigMerge: return "ui_rosette"
        }
    }

    private func row(_ i: Int, _ q: Quest) -> some View {
        let reward = store.balance.questReward(q.kind)
        return HStack(spacing: 12) {
            PixelIcon(key: icon(q.kind), size: 36)
            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: L10n.t("quests.\(q.kind.rawValue)"), q.target))
                    .font(Pixel.body(14))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    ProgressBar(value: Double(q.progress) / Double(max(1, q.target)))
                        .frame(height: 12)
                    PixelText("\(q.progress)/\(q.target)", size: 15).lineLimit(1).fixedSize()
                }
            }
            Group {
                if q.claimed {
                    PixelIcon(key: "ui_check", size: 30)
                } else if q.done {
                    Button {
                        store.claimQuest(i)
                    } label: {
                        PixelText(ShopRewardText.short(reward), size: 15).lineLimit(1).fixedSize()
                    }
                    .buttonStyle(PixelButtonStyle(kind: .green, size: 15, compact: true))
                } else {
                    PixelText(ShopRewardText.short(reward), size: 15)
                        .lineLimit(1).fixedSize()
                        .opacity(0.75)
                }
            }
            .frame(minWidth: 70)
        }
        .padding(12)
        .background(PixelSlice(key: q.claimed ? "ui_paper_green" : q.done ? "ui_paper_gold" : "ui_paper", inset: 4))
    }

    private var chest: some View {
        let qs = store.quests
        let all = !qs.isEmpty && qs.allSatisfy(\.claimed)
        let reward = store.balance.questChest
        return VStack(spacing: 8) {
            PixelIcon(key: "ui_chest", size: 56)
                .scaleEffect(all && !store.state.questChestClaimed ? 1.1 : 1)
                .opacity(store.state.questChestClaimed ? 0.5 : 1)
            Text(L10n.t("quests.chest")).font(Pixel.font(17))
            PixelText(ShopRewardText.short(reward), size: 16)
            if all && !store.state.questChestClaimed {
                Button { store.claimQuestChest() } label: { Text(L10n.t("quests.open")) }
                    .buttonStyle(PixelButtonStyle(kind: .green, size: 17))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(PixelSlice(key: "ui_panel", inset: 6))
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: store.state.questChestClaimed)
    }
}

/// Короткая запись награды иконками: "💎5 ⚡️15".
enum ShopRewardText {
    static func short(_ r: ProductReward) -> String {
        var parts: [String] = []
        if r.gems > 0 { parts.append("💎\(r.gems)") }
        if r.energy > 0 { parts.append("⚡️\(r.energy)") }
        if r.coins > 0 { parts.append("🪙\(r.coins)") }
        if r.stars > 0 { parts.append("⭐️\(r.stars)") }
        return parts.joined(separator: " ")
    }
}

/// Альбом: все предметы по цепочкам. Найденные видны, ненайденные - силуэтом,
/// за новую находку тап по карточке дает награду.
struct AlbumPage: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(L10n.t("album.hint"))
                    .font(Pixel.body(13))
                    .multilineTextAlignment(.center)
                    .opacity(0.75)
                ForEach(store.catalog.chains, id: \.id) { chain in
                    chainRow(chain.id)
                }
            }
            .padding(16)
        }
    }

    private func chainRow(_ chain: String) -> some View {
        let top = store.catalog.maxTier(of: chain)
        let found = (0...top).filter { store.game.isDiscovered(Item(chain: chain, tier: $0)) }.count
        let complete = store.game.chainCollected(chain)
        let paid = store.state.collectionChains.contains(chain)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                ResidentIcon(id: Residents.byChain[chain] ?? "tim", size: 26)
                Text(L10n.t("chain.\(chain)")).font(Pixel.font(16))
                Spacer()
                if complete && !paid {
                    Button { store.claimChain(chain) } label: { PixelText("💎\(store.balance.chainCompleteGems)", size: 15) }
                        .buttonStyle(PixelButtonStyle(kind: .green, size: 15, compact: true))
                } else {
                    PixelText("\(found)/\(top + 1)", size: 15)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(0...top, id: \.self) { tier in
                    cell(Item(chain: chain, tier: tier))
                }
            }
        }
        .padding(12)
        .background(PixelSlice(key: paid ? "ui_paper_green" : "ui_paper", inset: 4))
    }

    @ViewBuilder
    private func cell(_ item: Item) -> some View {
        let found = store.game.isDiscovered(item)
        let claimed = store.game.isCollectionClaimed(item)
        Button {
            if found && !claimed { store.claimDiscovery(item) }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                ItemIcon(item: item, size: 30)
                    .colorMultiply(found ? .white : .black)
                    .opacity(found ? 1 : 0.25)
                if found { TierBadge(tier: item.tier) }
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(found && !claimed ? Color(red: 1, green: 0.85, blue: 0.4).opacity(0.5) : Color.clear)
            .overlay(alignment: .topTrailing) {
                if found && !claimed {
                    Circle().fill(Color(red: 0.86, green: 0.25, blue: 0.3)).frame(width: 9, height: 9).offset(x: 2, y: -2)
                }
            }
        }
        .disabled(!found || claimed)
    }
}
