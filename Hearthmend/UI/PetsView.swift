import SwiftUI
import HearthCore

/// Кадры ходьбы животных (pet_<id>_<n>, tools/village_map.py) и в какую сторону они смотрят.
enum PetArt {
    static let frames: [String: Int] = [
        "chicken": 6, "duck": 6, "sheep": 8, "frog": 8, "pig": 8,
        "goose": 6, "cow": 8, "swan": 6, "horse": 6, "mouse": 6,
    ]
    static let facesRight: Set<String> = ["chicken", "frog"]

    static func frame(_ id: String, _ n: Int) -> String { "pet_\(id)_\(n % max(1, frames[id] ?? 1))" }
}

/// Животное на карте деревни: бродит по своему району, перебирая кадры ходьбы.
/// Когда готов подарок, над ним прыгает сердечко, тап забирает подарок.
struct PetWalker: View {
    @EnvironmentObject private var store: GameStore
    let pet: String
    let area: (minX: Double, maxX: Double, minY: Double, maxY: Double)
    let scale: CGFloat
    @State private var pos: CGPoint?
    @State private var right = true
    @State private var moving = false
    @State private var frame = 0
    @State private var alive = false
    @State private var hop = false
    @State private var hearts = false
    private let tick = Timer.publish(every: 0.11, on: .main, in: .common).autoconnect()

    var body: some View {
        let side = 32 * scale
        let p = pos ?? CGPoint(x: (area.minX + area.maxX) / 2, y: (area.minY + area.maxY) / 2)
        let ready = store.game.petGiftReady(pet)
        ZStack(alignment: .top) {
            PixelIcon(key: PetArt.frame(pet, moving ? frame : 0), size: side)
                .scaleEffect(x: right == PetArt.facesRight.contains(pet) ? 1 : -1, y: 1)
                .frame(width: side, height: side)
            if ready {
                PixelIcon(key: "ui_heart", size: 9 * scale)
                    .offset(y: (hop ? -6 : -1) * scale)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: hop)
            }
            if hearts {
                PixelIcon(key: "ui_heart", size: 8 * scale)
                    .offset(y: -16 * scale)
                    .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
            }
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .offset(x: p.x * 16 * scale - side / 2, y: p.y * 16 * scale - side)
        .onTapGesture { collect() }
        .onReceive(tick) { _ in if moving { frame += 1 } }
        .onAppear {
            alive = true
            hop = true
            pos = randomPoint()
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0.3...2)) { walk() }
        }
        .onDisappear { alive = false }
    }

    private func randomPoint() -> CGPoint {
        CGPoint(x: Double.random(in: area.minX...area.maxX), y: Double.random(in: area.minY...area.maxY))
    }

    private func walk() {
        guard alive, let from = pos else { return }
        let to = randomPoint()
        let dist = hypot(to.x - from.x, to.y - from.y)
        let duration = max(0.6, Double(dist) / 1.4)
        right = to.x >= from.x
        moving = true
        withAnimation(.linear(duration: duration)) { pos = to }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            moving = false
            frame = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 1.5...4.5)) { walk() }
        }
    }

    private func collect() {
        guard store.collectPet(pet) else {
            Haptics.light()
            store.show(L10n.t("pet.\(pet)"))
            return
        }
        withAnimation(.spring(response: 0.3)) { hearts = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { withAnimation(.easeOut(duration: 0.4)) { hearts = false } }
    }
}

/// Кнопка животных в деревне: красная точка, если кто-то ждет с подарком.
struct PetsButton: View {
    @EnvironmentObject private var store: GameStore
    @State private var open = false

    var body: some View {
        Button {
            Haptics.light()
            open = true
        } label: {
            PixelIcon(key: PetArt.frame("chicken", 0), size: 40)
                .frame(width: 50, height: 50)
                .background(Circle().fill(Theme.card))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                .overlay(alignment: .topTrailing) {
                    let count = store.game.petGiftsReady + (store.game.anyPetAdoptable ? 1 : 0)
                    if count > 0 {
                        Circle().fill(Color(red: 0.86, green: 0.25, blue: 0.3)).frame(width: 14, height: 14)
                    }
                }
        }
        .accessibilityLabel(L10n.t("pets.title"))
        .sheet(isPresented: $open) { PetsSheet() }
    }
}

extension Game {
    var anyPetAdoptable: Bool { Pets.all.contains { canAdopt($0.id) } }
}

struct PetsSheet: View {
    @EnvironmentObject private var store: GameStore
    @State private var frame = 0
    private let tick = Timer.publish(every: 0.14, on: .main, in: .common).autoconnect()

    var body: some View {
        PixelSheet(L10n.t("pets.title")) {
            ScrollView {
                VStack(spacing: 12) {
                    Text(L10n.t("pets.hint"))
                        .font(Pixel.body(13))
                        .multilineTextAlignment(.center)
                        .opacity(0.75)
                    ForEach(Pets.all, id: \.id) { pet in
                        row(pet)
                    }
                }
                .padding(16)
            }
        }
        .onReceive(tick) { _ in frame += 1 }
    }

    private func row(_ pet: PetDef) -> some View {
        let g = store.game
        let owned = g.petOwned(pet.id)
        let open = g.petAvailable(pet.id)
        let ready = g.petGiftReady(pet.id)
        return HStack(spacing: 12) {
            PixelIcon(key: PetArt.frame(pet.id, owned ? frame : 0), size: 48)
                .scaleEffect(x: PetArt.facesRight.contains(pet.id) ? 1 : -1, y: 1)
                .frame(width: 56, height: 56)
                .background(PixelSlice(key: owned ? "ui_paper_green" : "ui_paper", inset: 4))
                .saturation(open ? 1 : 0)
                .opacity(open ? 1 : 0.55)
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.t("pet.\(pet.id)")).font(Pixel.font(17))
                PixelText(String(format: L10n.t("pets.daily"), ShopRewardText.short(pet.gift)), size: 13)
                    .opacity(0.8)
                if !open {
                    HStack(spacing: 5) {
                        PixelIcon(key: "ui_lock", size: 16)
                        Text(String(format: L10n.t("pets.locked"), L10n.t("district.\(pet.district)")))
                            .font(Pixel.body(12)).opacity(0.7)
                    }
                } else if owned {
                    Text(L10n.t("pets.home")).font(Pixel.body(12)).opacity(0.7)
                }
            }
            Spacer(minLength: 0)
            Group {
                if owned {
                    if ready {
                        Button { _ = store.collectPet(pet.id) } label: { PixelText(ShopRewardText.short(pet.gift), size: 15).lineLimit(1).fixedSize() }
                            .buttonStyle(PixelButtonStyle(kind: .green, size: 15, compact: true))
                    } else {
                        PixelIcon(key: "ui_check", size: 28)
                    }
                } else if open {
                    let enough = store.state.coins >= pet.cost
                    Button { store.adoptPet(pet.id) } label: { PixelText("🪙\(pet.cost)", size: 15).lineLimit(1).fixedSize() }
                        .buttonStyle(PixelButtonStyle(kind: enough ? .green : .wood, size: 15, compact: true))
                        .opacity(enough ? 1 : 0.6)
                        .disabled(!enough)
                }
            }
            .frame(minWidth: 70)
        }
        .padding(12)
        .background(PixelSlice(key: ready ? "ui_paper_gold" : "ui_paper", inset: 4))
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: owned)
    }
}
