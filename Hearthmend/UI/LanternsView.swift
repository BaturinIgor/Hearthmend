import SwiftUI
import HearthCore

/// «Ночь фонарей»: темная деревня 7x9. Фонарики вешают на пустые клетки, два одинаковых сливаются
/// в более яркий, и свет расходится дальше. В темноте мерцают желания и светлячки.
struct LanternsView: View {
    @EnvironmentObject private var store: GameStore
    @State private var selected: Int?
    @State private var pop: Int?
    @State private var twinkle = false
    @State private var dawn = false
    @State private var showTrack = false
    @State private var showHelp = false

    private let cols = LanternsState.cols
    private let rows = LanternsState.rows

    var body: some View {
        PixelSheet(L10n.t("adv.lanterns.title")) {
            VStack(spacing: 8) {
                AdventureHeader(movesIcon: "ui_lantern", help: "adv.lanterns.how", showHelp: $showHelp)
                AdventureTrackBar(icon: "ui_lantern") { showTrack = true }
                village
                controls
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showTrack) { AdventureTrackSheet(icon: "🏮", note: "adv.lanterns.night") }
        .onAppear {
            if (store.state.adventure?.points ?? 0) == 0 { showHelp = true }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { twinkle = true }
        }
    }

    private var night: LanternsState? { store.state.adventure?.lanterns }
    private var selectedTier: Int? { selected.flatMap { night?.cells[$0].lantern } }

    // MARK: - Деревня

    private var village: some View {
        GeometryReader { geo in
            let side = floor(min(geo.size.width / CGFloat(cols), geo.size.height / CGFloat(rows)))
            ZStack {
                if let s = night {
                    let shining = s.shining
                    VStack(spacing: 0) {
                        ForEach(0..<rows, id: \.self) { r in
                            HStack(spacing: 0) {
                                ForEach(0..<cols, id: \.self) { c in
                                    cell(r * cols + c, s: s, shining: shining, side: side)
                                }
                            }
                        }
                    }
                    if dawn {
                        LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.6).opacity(0.9), .white.opacity(0.6)],
                                       startPoint: .top, endPoint: .bottom)
                            .transition(.opacity).allowsHitTesting(false)
                    }
                }
            }
            .frame(width: side * CGFloat(cols), height: side * CGFloat(rows))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.2, green: 0.2, blue: 0.36), lineWidth: 3))
            .id(night?.nights ?? 0)
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(4)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if let s = night, s.nights > 0 {
                PixelText("🌙 \(s.nights)", size: 13)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.85)))
            }
        }
    }

    private func cell(_ i: Int, s: LanternsState, shining: Set<Int>, side: CGFloat) -> some View {
        let c = s.cells[i]
        let mergeable = selectedTier != nil && selected != i && c.lantern == selectedTier && (selectedTier ?? 9) < Lanterns.maxTier
        return ZStack {
            // темная земля под скругленными клетками: в углах не просвечивает бумага
            Color(red: 0.2, green: 0.32, blue: 0.16)
            PixelTile(key: (i / cols + i % cols) % 2 == 0 ? "ui_cell_a" : "ui_cell_b", scale: side / 16)
            // ночь: где свет фонарей, там светло; где уже бывал свет - сумерки
            Color(red: 0.06, green: 0.07, blue: 0.2).opacity(shining.contains(i) ? 0 : c.lit ? 0.55 : 0.85)
            if !c.lit {
                switch c.secret {
                case .wish?:
                    PixelIcon(key: "ui_star", size: side * 0.45)
                        .opacity(twinkle ? 0.55 : 0.2)
                        .scaleEffect(twinkle ? 1 : 0.8)
                case .fireflies?:
                    HStack(spacing: side * 0.08) {
                        Circle().fill(Color(red: 0.75, green: 1, blue: 0.4)).frame(width: 3, height: 3).offset(y: twinkle ? -3 : 2)
                        Circle().fill(Color(red: 0.75, green: 1, blue: 0.4)).frame(width: 3, height: 3).offset(y: twinkle ? 2 : -2)
                    }
                    .opacity(twinkle ? 0.9 : 0.4)
                default:
                    EmptyView()
                }
            }
            if let tier = c.lantern {
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 1, green: 0.85, blue: 0.4).opacity(0.75), .clear],
                                         center: .center, startRadius: 0, endRadius: side * (0.5 + CGFloat(tier) * 0.12)))
                    .frame(width: side * 1.6, height: side * 1.6)
                    .opacity(twinkle ? 1 : 0.75)
                    .allowsHitTesting(false)
                DecorIcon(key: "decor_lantern", size: side * (0.55 + CGFloat(tier) * 0.1))
                    .scaleEffect(pop == i ? 1.3 : 1)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                    .id("\(i)-\(tier)")
                TierBadge(tier: tier).scaleEffect(0.6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: side, height: side)
        .overlay(Rectangle().stroke(selected == i ? Color.white : .clear, lineWidth: 2.5))
        .overlay(Rectangle().stroke(mergeable ? Color.yellow.opacity(twinkle ? 1 : 0.5) : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { tap(i, cell: c) }
        .zIndex(c.lantern != nil ? 1 : 0)
    }

    // MARK: - Касания

    /// Тап по фонарю выбирает его, по такому же - сливает. Тап по пустой клетке вешает фонарик.
    private func tap(_ i: Int, cell: LanternCell) {
        withAnimation(.easeOut(duration: 0.45)) {
            if let from = selected {
                selected = nil
                guard from != i else { return }
                if cell.lantern != nil {
                    if let r = store.moveLantern(from: from, to: i) { after(r, at: i) }
                    return
                }
            }
            if cell.lantern != nil {
                Haptics.light()
                selected = i
                if !hasPair(i) { store.show(L10n.t("adv.lanterns.pick")) }
            } else if let r = store.hangLantern(i) {
                after(r, at: i)
            }
        }
    }

    private func hasPair(_ i: Int) -> Bool {
        guard let s = night, let t = s.cells[i].lantern, t < Lanterns.maxTier else { return false }
        return s.cells.indices.contains { $0 != i && s.cells[$0].lantern == t }
    }

    private func after(_ r: Game.LanternLight, at i: Int) {
        pop = i
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { withAnimation(.spring()) { pop = nil } }
        if r.nightDone {
            withAnimation(.easeIn(duration: 0.3)) { dawn = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { withAnimation(.easeOut(duration: 0.8)) { dawn = false } }
        }
    }

    // MARK: - Кнопки

    private var controls: some View {
        HStack(spacing: 10) {
            if let s = night {
                PixelText("🌑 \(s.darkLeft)", size: 15)
            }
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.45)) {
                    if let i = store.game.bestLanternSpot, let r = store.hangLantern(i) { after(r, at: i) }
                }
            } label: {
                HStack(spacing: 6) {
                    PixelIcon(key: "ui_lantern", size: 22)
                    PixelText(L10n.t("adv.lanterns.hang"), size: 16)
                }
            }
            .buttonStyle(PixelButtonStyle(kind: .green, size: 16))
            .opacity((store.state.adventure?.moves ?? 0) > 0 ? 1 : 0.6)
        }
        .padding(8)
        .background(PixelSlice(key: "ui_paper", inset: 4))
    }
}
