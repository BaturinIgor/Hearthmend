import SwiftUI
import HearthCore

/// «Теплица»: грядки 4x5, растения растут по настоящему времени. Две одинаковых сливаются в одно
/// следующей ступени и дозревают быстрее, спелое собирается за очки, лейка раз в 4 часа ускоряет все.
struct GreenhouseView: View {
    @EnvironmentObject private var store: GameStore
    @State private var selected: Int?
    @State private var pop: Int?
    @State private var showTrack = false
    @State private var showHelp = false

    private let cols = GreenhouseState.cols

    var body: some View {
        PixelSheet(L10n.t("adv.greenhouse.title")) {
            VStack(spacing: 8) {
                AdventureHeader(movesIcon: "ui_seeds", help: "adv.greenhouse.how", showHelp: $showHelp)
                AdventureTrackBar(icon: "ui_seeds") { showTrack = true }
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    beds(now: store.game.now())
                }
                controls
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showTrack) { AdventureTrackSheet(icon: "🌱", note: "adv.greenhouse.golden") }
        .onAppear {
            if (store.state.adventure?.points ?? 0) == 0 { showHelp = true }
        }
    }

    // MARK: - Грядки

    private func beds(now: Date) -> some View {
        let g = store.state.adventure?.greenhouse
        let same: Item? = selected.flatMap { g?.beds[$0]?.item }
        return GeometryReader { geo in
            let side = floor(min((geo.size.width - CGFloat(cols - 1) * 6) / CGFloat(cols),
                                 (geo.size.height - CGFloat(GreenhouseState.rows - 1) * 6) / CGFloat(GreenhouseState.rows)))
            VStack(spacing: 6) {
                ForEach(0..<GreenhouseState.rows, id: \.self) { r in
                    HStack(spacing: 6) {
                        ForEach(0..<cols, id: \.self) { c in
                            bed(r * cols + c, plant: g?.beds[r * cols + c] ?? nil, side: side, now: now, same: same)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.78, green: 0.9, blue: 0.84).opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.8), lineWidth: 2))
        .frame(maxHeight: .infinity)
    }

    private func bed(_ i: Int, plant: Plant?, side: CGFloat, now: Date, same: Item?) -> some View {
        let ripe = plant?.ripe(at: now) ?? false
        return ZStack(alignment: .bottom) {
            PixelTile(key: "ui_soil", scale: side / 16)
            if let p = plant {
                FindIcon(item: p.item, size: side * 0.8)
                    .scaleEffect(pop == i ? 1.2 : 1)
                    .modifier(RipeBounce(on: ripe))
                    .frame(maxHeight: .infinity)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                    .id("\(i)-\(p.item.chain)-\(p.item.tier)")
                if ripe {
                    PixelIcon(key: "ui_check", size: 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(2)
                } else {
                    Text(Self.left(p.readyAt.timeIntervalSince(now)))
                        .font(Pixel.digits(10))
                        .foregroundColor(.white)
                        .padding(.horizontal, 3)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                        .padding(.bottom, 2)
                }
                TierBadge(tier: p.item.tier).scaleEffect(0.7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(selected == i ? Color.white : .clear, lineWidth: 2.5))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(
            same != nil && selected != i && plant?.item == same ? Theme.accent : .clear, lineWidth: 2))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(ripe && selected != i ? Color.yellow.opacity(0.8) : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { tap(i, plant: plant, ripe: ripe) }
    }

    static func left(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return s >= 3600 ? String(format: "%d:%02d", s / 3600, s / 60 % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Тап выбирает растение; тап по такому же сливает, по другой грядке переносит. Спелое без выбора собирается.
    private func tap(_ i: Int, plant: Plant?, ripe: Bool) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if let from = selected {
                selected = nil
                guard from != i else { return }
                if store.movePlant(from: from, to: i) { bounce(i) }
            } else if plant == nil {
                if case .planted = store.plantSeed(at: i) { bounce(i) }
            } else if ripe, !hasPair(i) {
                store.harvest(i)
            } else {
                Haptics.light()
                selected = i
            }
        }
    }

    private func hasPair(_ i: Int) -> Bool {
        guard let beds = store.state.adventure?.greenhouse?.beds, let item = beds[i]?.item, item.tier < Greenhouse.maxTier else { return false }
        return beds.indices.contains { $0 != i && beds[$0]?.item == item }
    }

    private func bounce(_ i: Int) {
        pop = i
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { withAnimation(.spring()) { pop = nil } }
    }

    // MARK: - Кнопки

    private var controls: some View {
        let g = store.state.adventure?.greenhouse
        return HStack(spacing: 10) {
            if let i = selected, g?.beds[i]?.ripe(at: store.game.now()) == true {
                Button {
                    withAnimation(.spring(response: 0.3)) { store.harvest(i); selected = nil }
                } label: {
                    PixelText(L10n.t("adv.greenhouse.harvest"), size: 14)
                }
                .buttonStyle(PixelButtonStyle(kind: .pink, size: 14))
            } else {
                waterButton
            }
            Spacer()
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    if case .planted(let i, _) = store.plantSeed() { bounce(i) }
                }
            } label: {
                HStack(spacing: 6) {
                    PixelIcon(key: "ui_seeds", size: 22)
                    PixelText(L10n.t("adv.greenhouse.plant"), size: 16)
                }
            }
            .buttonStyle(PixelButtonStyle(kind: .green, size: 16))
            .opacity((store.state.adventure?.moves ?? 0) > 0 ? 1 : 0.6)
        }
        .padding(8)
        .background(PixelSlice(key: "ui_paper", inset: 4))
    }

    private var waterButton: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let g = store.state.adventure?.greenhouse
            let ready = (g.map { store.game.now() >= $0.waterAt } ?? false)
            Button { withAnimation { store.water() } } label: {
                HStack(spacing: 4) {
                    PixelIcon(key: "ui_can", size: 20)
                    if ready {
                        PixelText(L10n.t("adv.greenhouse.water"), size: 14)
                    } else if let g = g {
                        Text(Self.left(g.waterAt.timeIntervalSince(store.game.now()))).font(Pixel.digits(13))
                    }
                }
            }
            .buttonStyle(PixelButtonStyle(kind: .wood, size: 14))
            .opacity(ready ? 1 : 0.6)
            .overlay(alignment: .topTrailing) {
                if ready && g?.beds.contains(where: { $0 != nil }) == true { RedDot().offset(x: 4, y: -4) }
            }
        }
    }
}

/// Спелое растение подпрыгивает: его можно собрать.
private struct RipeBounce: ViewModifier {
    let on: Bool
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .offset(y: on && up ? -3 : 0)
            .onAppear { withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { up = true } }
    }
}
