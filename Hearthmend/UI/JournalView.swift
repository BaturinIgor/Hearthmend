import SwiftUI
import HearthCore

/// Журнал: задания дня, жители, альбом и достижения в одном окне. Кнопка внизу поля одна,
/// на ней сумма всего, что можно забрать.
enum JournalTab: String, CaseIterable, Identifiable {
    case quests, friends, album, achievements
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .quests: return "ui_ticket"
        case .friends: return "ui_heart"
        case .album: return "ui_book"
        case .achievements: return "ui_trophy"
        }
    }

    var title: String { L10n.t("\(rawValue).title") }
}

extension GameStore {
    func journalCount(_ tab: JournalTab) -> Int {
        switch tab {
        case .quests: return game.questsClaimable
        case .friends: return game.friendsClaimable
        case .album: return game.collectionClaimable
        case .achievements: return game.achievementsClaimable
        }
    }

    var journalTotal: Int { JournalTab.allCases.reduce(0) { $0 + journalCount($1) } }

    /// Вкладка, с которой открывать журнал: первая, где есть награда.
    var journalStartTab: JournalTab { JournalTab.allCases.first { journalCount($0) > 0 } ?? .quests }
}

struct JournalButton: View {
    @EnvironmentObject private var store: GameStore
    @State private var open = false

    var body: some View {
        BadgeButton(icon: "ui_book", count: store.journalTotal) { open = true }
            .sheet(isPresented: $open) { JournalSheet(tab: store.journalStartTab) }
    }
}

struct JournalSheet: View {
    @EnvironmentObject private var store: GameStore
    @State var tab: JournalTab

    var body: some View {
        PixelSheet(tab.title) {
            VStack(spacing: 0) {
                tabs
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                ZStack {
                    switch tab {
                    case .quests: QuestsPage()
                    case .friends: FriendsPage()
                    case .album: AlbumPage()
                    case .achievements: AchievementsPage()
                    }
                }
                .id(tab)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: tab)
    }

    private var tabs: some View {
        HStack(spacing: 8) {
            ForEach(JournalTab.allCases) { t in
                let count = store.journalCount(t)
                Button {
                    Haptics.light()
                    tab = t
                } label: {
                    PixelIcon(key: t.icon, size: 26)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(PixelSlice(key: t == tab ? "ui_paper_gold" : "ui_paper", inset: 4, scale: 2))
                        .scaleEffect(t == tab ? 1.04 : 1)
                        .overlay(alignment: .topTrailing) {
                            if count > 0 {
                                Text("\(count)")
                                    .font(Pixel.digits(12))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 3)
                                    .background(Circle().fill(Color(red: 0.86, green: 0.25, blue: 0.3)).frame(minWidth: 18, minHeight: 18))
                                    .offset(x: 4, y: -6)
                            }
                        }
                }
                .accessibilityLabel(t.title)
            }
        }
    }
}

// MARK: - Жители

struct FriendsPage: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(L10n.t("friends.hint"))
                    .font(Pixel.body(13))
                    .multilineTextAlignment(.center)
                    .opacity(0.75)
                ForEach(Friends.all, id: \.self) { id in
                    row(id)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func row(_ id: String) -> some View {
        let g = store.game
        let met = g.friendMet(id)
        let level = g.friendLevel(id)
        let claimed = g.friendClaimedLevel(id)
        let canClaim = g.friendCanClaim(id)
        let best = level >= Friends.maxLevel && claimed >= Friends.maxLevel
        HStack(alignment: .top, spacing: 12) {
            ResidentIcon(id: id, size: 46)
                .padding(4)
                .background(PixelSlice(key: best ? "ui_paper_gold" : "ui_paper", inset: 4))
                .saturation(met ? 1 : 0)
                .opacity(met ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(L10n.t("resident.\(id)")).font(Pixel.font(17))
                    Spacer(minLength: 0)
                    HStack(spacing: 1) {
                        ForEach(0..<Friends.maxLevel, id: \.self) { i in
                            PixelIcon(key: "ui_heart", size: 14)
                                .saturation(i < level ? 1 : 0)
                                .opacity(i < level ? 1 : 0.3)
                        }
                    }
                }
                if met {
                    Text(L10n.t("friends.about.\(id)"))
                        .font(Pixel.body(12))
                        .opacity(0.75)
                        .fixedSize(horizontal: false, vertical: true)
                    if let p = g.friendProgress(id) {
                        HStack(spacing: 8) {
                            ProgressBar(value: Double(p.have) / Double(max(1, p.need)))
                                .frame(height: 12)
                            PixelText("\(p.have)/\(p.need)", size: 14).lineLimit(1).fixedSize()
                        }
                    }
                    gift(id, level: claimed + 1, canClaim: canClaim, best: best)
                } else {
                    HStack(spacing: 6) {
                        PixelIcon(key: "ui_lock", size: 18)
                        Text(L10n.t("friends.locked")).font(Pixel.body(12)).opacity(0.7)
                    }
                }
            }
        }
        .padding(12)
        .background(PixelSlice(key: canClaim ? "ui_paper_gold" : best ? "ui_paper_green" : "ui_paper", inset: 4))
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: claimed)
    }

    @ViewBuilder
    private func gift(_ id: String, level: Int, canClaim: Bool, best: Bool) -> some View {
        if best {
            HStack(spacing: 6) {
                PixelIcon(key: "ui_check", size: 18)
                Text(L10n.t("friends.best_label")).font(Pixel.body(12))
            }
        } else {
            let reward = Friends.reward(level: level, resident: id)
            let text = ShopRewardText.short(reward) + (reward.decor != nil ? " 🪴" : "")
            HStack(spacing: 8) {
                Text(String(format: L10n.t("friends.gift"), level)).font(Pixel.body(12)).opacity(0.8)
                Spacer(minLength: 0)
                if canClaim {
                    Button { store.claimFriend(id) } label: { PixelText(text, size: 15).lineLimit(1).fixedSize() }
                        .buttonStyle(PixelButtonStyle(kind: .green, size: 15, compact: true))
                        .transition(.scale.combined(with: .opacity))
                } else {
                    PixelText(text, size: 15).lineLimit(1).fixedSize().opacity(0.6)
                }
            }
        }
    }
}

// MARK: - Достижения

struct AchievementsPage: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(L10n.t("achievements.hint"))
                    .font(Pixel.body(13))
                    .multilineTextAlignment(.center)
                    .opacity(0.75)
                ForEach(AchievementKind.allCases, id: \.self) { kind in
                    row(kind)
                }
            }
            .padding(16)
        }
    }

    static func icon(_ kind: AchievementKind) -> String {
        switch kind {
        case .merges: return "ui_star"
        case .orders: return "ui_basket"
        case .buildings: return "ui_house"
        case .level: return "ui_crown"
        case .album: return "ui_book"
        case .postcards: return "ui_frame"
        case .friends: return "ui_heart"
        case .merchant: return "ui_wagon"
        case .decor: return "ui_plant"
        }
    }

    /// Бронза, серебро, золото.
    private static let medal: [Color] = [
        Color(red: 0.80, green: 0.52, blue: 0.28),
        Color(red: 0.72, green: 0.76, blue: 0.80),
        Color(red: 0.98, green: 0.78, blue: 0.24),
    ]

    private func row(_ kind: AchievementKind) -> some View {
        let g = store.game
        let goals = g.achievementGoals(kind)
        let value = g.achievementValue(kind)
        let tier = g.achievementTier(kind)
        let claimed = g.achievementClaimed(kind)
        let done = claimed >= goals.count
        let goal = goals[min(claimed, goals.count - 1)]
        return HStack(spacing: 12) {
            PixelIcon(key: Self.icon(kind), size: 34)
                .padding(6)
                .background(Circle().fill(claimed > 0 ? Self.medal[claimed - 1].opacity(0.55) : Theme.wood.opacity(0.12)))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(String(format: L10n.t("achievements.\(kind.rawValue)"), goal))
                        .font(Pixel.body(14))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(i < claimed ? Self.medal[i] : Theme.wood.opacity(0.18))
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(Theme.text.opacity(0.5), lineWidth: 1))
                        }
                    }
                }
                if !done {
                    HStack(spacing: 8) {
                        ProgressBar(value: Double(min(value, goal)) / Double(max(1, goal)))
                            .frame(height: 12)
                        PixelText("\(min(value, goal))/\(goal)", size: 14).lineLimit(1).fixedSize()
                    }
                }
            }
            Group {
                if done {
                    PixelIcon(key: "ui_check", size: 28)
                } else if tier > claimed {
                    Button { store.claimAchievement(kind) } label: {
                        PixelText("💎\(Achievements.tierGems[claimed])", size: 15).lineLimit(1).fixedSize()
                    }
                    .buttonStyle(PixelButtonStyle(kind: .green, size: 15, compact: true))
                } else {
                    PixelText("💎\(Achievements.tierGems[claimed])", size: 15).lineLimit(1).fixedSize().opacity(0.6)
                }
            }
            .frame(minWidth: 58)
        }
        .padding(12)
        .background(PixelSlice(key: done ? "ui_paper_green" : tier > claimed ? "ui_paper_gold" : "ui_paper", inset: 4))
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: claimed)
    }
}
