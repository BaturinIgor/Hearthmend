import SwiftUI
import HearthCore

/// Ряд круглых значков над шапкой: подарки, торговец, животные, копилка. На каждом таймер
/// или красная точка, если что-то ждет. Еще не открытое видно серым, с замком и уровнем.
struct TopIcons: View {
    @EnvironmentObject private var store: GameStore
    let openDaily: () -> Void
    let openShop: () -> Void
    let openVillage: () -> Void
    @State private var showPets = false
    @State private var showJournal = false

    var body: some View {
        let g = store.game
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if g.dailyRewardReady {
                    TopIcon(icon: "ui_gift", label: L10n.t("top.daily"), dot: true, action: openDaily)
                }
                if store.journalTotal > 0 {
                    TopIcon(icon: "ui_book", label: L10n.t("top.journal"), dot: true) { showJournal = true }
                }
                merchant
                pets
                TopIcon(icon: "ui_piggy", label: g.piggyFull ? L10n.t("top.full") : "💎\(store.state.piggyGems)",
                        dot: g.piggyFull, action: openShop)
                if !g.boostUnlocked {
                    TopIcon(icon: "ui_energy", label: String(format: L10n.t("top.level"), store.balance.boostLevel), locked: true) {
                        store.show(String(format: L10n.t("top.boost_locked"), store.balance.boostLevel))
                    }
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 50)
        .sheet(isPresented: $showPets) { PetsSheet() }
        .background(EmptyView().sheet(isPresented: $showJournal) { JournalSheet(tab: store.journalStartTab) })
    }

    @ViewBuilder
    private var merchant: some View {
        let g = store.game
        if !g.merchantUnlocked {
            TopIcon(icon: "ui_wagon", label: String(format: L10n.t("top.level"), Balance.merchantLevel), locked: true) {
                store.show(String(format: L10n.t("top.merchant_locked"), Balance.merchantLevel))
            }
        } else if let visit = store.state.merchant {
            TopIcon(icon: "ui_wagon", label: clock(visit.leavesAt.timeIntervalSince(g.now())), dot: store.canDeliverMerchant) {
                store.show(L10n.t("merchant.about"))
            }
        } else if let t = g.merchantArrivesIn {
            TopIcon(icon: "ui_wagon", label: clock(t), dimmed: true) {
                store.show(String(format: L10n.t("top.merchant_soon"), clock(t)))
            }
        }
    }

    @ViewBuilder
    private var pets: some View {
        let g = store.game
        let open = Pets.all.contains { g.petAvailable($0.id) }
        if open {
            TopIcon(icon: PetArt.frame("chicken", 0), label: L10n.t("pets.title"),
                    dot: g.petGiftsReady > 0 || g.anyPetAdoptable) { showPets = true }
        } else {
            TopIcon(icon: PetArt.frame("chicken", 0), label: "🔒", locked: true) {
                store.show(String(format: L10n.t("pets.locked"), L10n.t("district.farmstead")))
            }
        }
    }

    private func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%d:%02d", s / 3600, s / 60 % 60)
    }
}

struct TopIcon: View {
    let icon: String
    let label: String
    var dot = false
    var locked = false
    var dimmed = false
    let action: () -> Void
    @State private var bounce = false

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            VStack(spacing: 1) {
                ZStack {
                    Circle().fill(Theme.card)
                    Circle().stroke(Theme.wood.opacity(0.45), lineWidth: 2)
                    PixelIcon(key: icon, size: 24)
                        .saturation(locked ? 0 : 1)
                        .opacity(locked || dimmed ? 0.5 : 1)
                    if locked {
                        PixelIcon(key: "ui_lock", size: 14).offset(x: 10, y: 9)
                    }
                }
                .frame(width: 34, height: 34)
                .overlay(alignment: .topTrailing) {
                    if dot {
                        Circle().fill(Color(red: 0.86, green: 0.25, blue: 0.3))
                            .frame(width: 11, height: 11)
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                            .offset(x: 2, y: -2)
                    }
                }
                .scaleEffect(dot && bounce ? 1.08 : 1)
                PixelText(label, size: 10)
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundColor(Theme.text)
            }
        }
        .onAppear {
            guard dot else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { bounce = true }
        }
    }
}
