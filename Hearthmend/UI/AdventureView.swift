import SwiftUI
import HearthCore

/// Значок большого события в верхнем ряду: таймер до конца и красная точка, когда есть чем ходить.
struct AdventureIcon: View {
    @EnvironmentObject private var store: GameStore
    @State private var open = false

    var body: some View {
        let g = store.game
        if let s = g.adventureSchedule(at: g.now()) {
            if g.adventureUnlocked, let a = g.adventure {
                TopIcon(icon: AdventureArt.icon(a.kind), label: AdventureArt.timeLeft(s.ends, now: g.now()),
                        dot: g.adventureNeedsAttention) { open = true }
                    .sheet(isPresented: $open) { AdventureSheet() }
            } else {
                TopIcon(icon: AdventureArt.icon(s.kind), label: String(format: L10n.t("top.level"), Balance.adventureLevel),
                        locked: true) {
                    store.show(String(format: L10n.t("adv.locked"), Balance.adventureLevel))
                }
            }
        }
    }
}

enum AdventureArt {
    static func icon(_ kind: AdventureKind) -> String {
        switch kind {
        case .depths: return "ui_pickaxe"
        default: return "ui_gift"
        }
    }

    static func timeLeft(_ ends: Date, now: Date) -> String {
        let s = max(0, Int(ends.timeIntervalSince(now)))
        if s >= 86400 { return String(format: L10n.t("event.days_left"), s / 86400 + (s % 86400 > 0 ? 1 : 0)) }
        return String(format: "%d:%02d", s / 3600, s / 60 % 60)
    }
}

/// Окно события. Пока в круге одни «Глубины», остальные события подключатся сюда же.
struct AdventureSheet: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        switch store.state.adventure?.kind {
        case .depths?: DepthsView()
        default: PixelSheet(L10n.t("adv.title")) { Spacer() }
        }
    }
}

/// «Глубины»: сверху шапка с кирками и дорожкой, посередине шахта, внизу поле находок 5x5.
struct DepthsView: View {
    @EnvironmentObject private var store: GameStore
    @State private var selected: Int?
    @State private var shake: Int?
    @State private var flash: Set<Int> = []
    @State private var showTrack = false
    @State private var showHelp = false

    private let w = DepthsState.width

    var body: some View {
        PixelSheet(L10n.t("adv.depths.title")) {
            VStack(spacing: 8) {
                header
                trackBar
                mine
                board
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showTrack) { DepthsTrack() }
        .onAppear {
            if store.state.adventure?.depths?.cells.contains(where: \.isOpen) == false { showHelp = true }
        }
    }

    // MARK: - Шапка

    private var header: some View {
        let g = store.game
        let moves = store.state.adventure?.moves ?? 0
        return HStack(spacing: 8) {
            HStack(spacing: 4) {
                PixelIcon(key: "ui_pickaxe", size: 26)
                Text("\(moves)").font(Pixel.digits(20))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(PixelSlice(key: "ui_paper", inset: 4, scale: 2))
            if g.adventureDailyReady {
                Button { store.claimAdventureDaily() } label: {
                    HStack(spacing: 4) {
                        PixelIcon(key: "ui_gift", size: 20)
                        PixelText("+\(Balance.adventureDailyMoves)", size: 14)
                    }
                }
                .buttonStyle(PixelButtonStyle(kind: .pink, size: 14, compact: true))
                .overlay(alignment: .topTrailing) { RedDot().offset(x: 4, y: -4) }
            }
            Spacer()
            if let ends = g.adventureEndsAt {
                PixelText("⏳ " + AdventureArt.timeLeft(ends, now: g.now()), size: 13).opacity(0.75)
            }
            Button { showHelp.toggle() } label: { PixelIcon(key: "ui_question", size: 24) }
        }
        .overlay(alignment: .top) {
            if showHelp {
                PixelText(L10n.t("adv.depths.how"), size: 13)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .background(PixelSlice(key: "ui_paper_gold", inset: 4))
                    .offset(y: 40)
                    .onTapGesture { withAnimation { showHelp = false } }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .zIndex(2)
            }
        }
        .zIndex(2)
    }

    private var trackBar: some View {
        let a = store.state.adventure
        let track = store.game.adventureTrack(a?.kind ?? .depths)
        let claimed = a?.claimed ?? 0
        let points = a?.points ?? 0
        let prev = claimed > 0 ? track[min(claimed, track.count) - 1].points : 0
        let next = claimed < track.count ? track[claimed] : nil
        return Button { showTrack = true } label: {
            HStack(spacing: 8) {
                PixelIcon(key: "ui_minecart", size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        PixelText(L10n.t("adv.track"), size: 12)
                        Spacer()
                        if let next = next {
                            PixelText("\(points)/\(next.points)", size: 12)
                        } else {
                            PixelText(L10n.t("adv.track_done"), size: 12)
                        }
                    }
                    ProgressBar(value: next.map { Double(points - prev) / Double(max(1, $0.points - prev)) } ?? 1, fill: "ui_bar_fill")
                        .frame(height: 12)
                        .animation(.easeOut(duration: 0.4), value: points)
                }
                if let next = next { PrizeIcon(prize: next.prize, size: 30) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(PixelSlice(key: "ui_paper", inset: 4))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Шахта

    private var mine: some View {
        GeometryReader { geo in
            let side = floor((geo.size.width - CGFloat(w - 1) * 2) / CGFloat(w))
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        // вход в шахту
                        HStack(spacing: 4) {
                            PixelIcon(key: "ui_lantern", size: 18)
                            PixelText(L10n.t("adv.depths.entrance"), size: 12)
                        }
                        .frame(height: 22)
                        ForEach(0..<DepthsState.depth, id: \.self) { r in
                            HStack(spacing: 2) {
                                ForEach(0..<w, id: \.self) { c in
                                    cell(r * w + c, side: side)
                                }
                            }
                            .id(r)
                            .overlay(alignment: .leading) {
                                if (r + 1) % 6 == 0 {
                                    Text("\(r + 1)").font(Pixel.digits(10))
                                        .foregroundColor(.white.opacity(0.7))
                                        .offset(x: -1, y: side / 2 - 6)
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .onAppear {
                    let row = max(0, (store.state.adventure?.depths?.reached ?? 0) - 1)
                    proxy.scrollTo(row, anchor: .top)
                }
                .onChange(of: store.state.adventure?.depths?.reached ?? -1) { row in
                    withAnimation(.easeInOut(duration: 0.5)) { proxy.scrollTo(max(0, row - 2), anchor: .top) }
                }
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.2, green: 0.14, blue: 0.12)))
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func cell(_ i: Int, side: CGFloat) -> some View {
        let d = store.state.adventure?.depths
        let c = d?.cells[i] ?? DepthCell(hardness: -1, content: nil)
        let can = d?.diggable(i) ?? false
        ZStack {
            if c.isOpen {
                PixelTile(key: "ui_mine_open", scale: side / 16)
                if case .find(let item)? = c.content {
                    FindIcon(item: item, size: side * 0.7)
                        .modifier(Bob())
                }
            } else if c.isRock {
                PixelTile(key: "ui_mine_3", scale: side / 16).brightness(-0.25)
                PixelIcon(key: "depth_rock", size: side * 0.7)
            } else {
                PixelTile(key: "ui_mine_\(min(3, c.hardness))", scale: side / 16)
                    .brightness(can ? 0.05 : -0.18)
                content(c, index: i, side: side, can: can, treasure: d?.treasureVisible(i) ?? false)
                if c.hardness >= 2 {
                    Cracks(level: 3 - c.hardness).frame(width: side, height: side)
                }
            }
        }
        .frame(width: side, height: side)
        .clipped()
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.white.opacity(can ? 0.55 : 0), lineWidth: 1.5))
        .overlay(flash.contains(i) ? Color.white.opacity(0.6) : Color.clear)
        .offset(x: shake == i ? 3 : 0)
        .contentShape(Rectangle())
        .onTapGesture { tap(i) }
    }

    /// Что видно сквозь породу: фонарь мерцает, клад показывается заранее, остальное скрыто.
    @ViewBuilder
    private func content(_ c: DepthCell, index: Int, side: CGFloat, can: Bool, treasure: Bool) -> some View {
        switch c.content {
        case .lantern? where can:
            PixelIcon(key: "ui_lantern", size: side * 0.55).opacity(0.85).modifier(Glow())
        case .treasure? where treasure:
            PixelIcon(key: "chest_3_items", size: side * 0.75).modifier(Glow())
        default:
            EmptyView()
        }
    }

    private func tap(_ i: Int) {
        guard let c = store.state.adventure?.depths?.cells[i] else { return }
        if c.isOpen {
            if case .find? = c.content { withAnimation(.spring(response: 0.3)) { store.collectDepth(i) } }
            return
        }
        guard store.state.adventure?.depths?.diggable(i) == true else {
            Haptics.light()
            withAnimation(.default) { shake = i }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { withAnimation(.spring(response: 0.2)) { shake = nil } }
            return
        }
        let result = store.dig(i)
        switch result {
        case .chipped:
            withAnimation(.easeOut(duration: 0.06)) { shake = i }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) { shake = nil } }
        case .opened(_, _, let opened):
            flash = Set(opened)
            withAnimation(.easeOut(duration: 0.45)) { flash = [] }
        default:
            break
        }
    }

    // MARK: - Поле находок

    private var board: some View {
        let items = store.state.adventure?.depths?.board ?? []
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                PixelText(L10n.t(selected == nil ? "adv.board_hint" : "adv.board_selected"), size: 12)
                    .opacity(0.8)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer()
                Button {
                    if let s = selected {
                        withAnimation(.spring(response: 0.3)) { store.deliverFind(s); selected = nil }
                    }
                } label: {
                    HStack(spacing: 4) {
                        PixelIcon(key: "ui_minecart", size: 20)
                        if let s = selected, let item = items.indices.contains(s) ? items[s] : nil {
                            PixelText("+\(Depths.points(item))", size: 14)
                        }
                    }
                }
                .buttonStyle(PixelButtonStyle(kind: .green, size: 14, compact: true))
                .opacity(selected == nil ? 0.5 : 1)
                .disabled(selected == nil)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 4) {
                ForEach(0..<DepthsState.boardSize, id: \.self) { i in
                    slot(i, item: items.indices.contains(i) ? items[i] : nil)
                }
            }
        }
        .padding(8)
        .background(PixelSlice(key: "ui_paper", inset: 4))
    }

    private func slot(_ i: Int, item: Item?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.86, green: 0.78, blue: 0.62))
            if let item = item {
                FindIcon(item: item, size: 34)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    .overlay(alignment: .bottomTrailing) { TierBadge(tier: item.tier).scaleEffect(0.75).offset(x: 4, y: 4) }
            }
        }
        .frame(height: 42)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(selected == i ? Theme.accent : .clear, lineWidth: 2.5))
        .scaleEffect(selected == i ? 1.06 : 1)
        .contentShape(Rectangle())
        .onTapGesture { tapSlot(i, item: item) }
    }

    /// Тап выбирает находку, тап по другой клетке переносит или сливает, второй тап по той же сдает в вагонетку.
    private func tapSlot(_ i: Int, item: Item?) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if let s = selected {
                if s == i {
                    store.deliverFind(i)
                    selected = nil
                } else {
                    let merged = store.moveFind(from: s, to: i)
                    selected = merged ? i : nil
                }
            } else if item != nil {
                Haptics.light()
                selected = i
            }
        }
    }
}

/// Находка события: спрайт из пака.
struct FindIcon: View {
    let item: Item
    let size: CGFloat

    var body: some View {
        PixelIcon(key: "\(item.chain)_\(item.tier)", size: size)
    }
}

/// Награда дорожки: ресурс, ящик, генератор или украшение.
struct PrizeIcon: View {
    @EnvironmentObject private var store: GameStore
    let prize: AdventurePrize
    var size: CGFloat = 30

    var body: some View {
        switch prize {
        case .chest(let c):
            ZStack(alignment: .bottomTrailing) {
                PixelIcon(key: BoardScene.resourceArt(c).0, size: size)
                if c.kind != .items {
                    Text(Fmt.compact(c.amount)).font(Pixel.digits(11))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 0, x: 1, y: 1)
                        .offset(x: 4, y: 3)
                }
            }
        case .generator(let chain):
            ZStack {
                PixelIcon(key: "ui_crate", size: size)
                ItemIcon(item: Item(chain: chain, tier: 0), size: size * 0.6)
            }
        case .decor(let key):
            DecorIcon(key: key, size: size)
        }
    }
}

/// Дорожка наград целиком.
struct DepthsTrack: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        let a = store.state.adventure
        let track = store.game.adventureTrack(a?.kind ?? .depths)
        PixelSheet(L10n.t("adv.track")) {
            ScrollView {
                VStack(spacing: 6) {
                    PixelText(L10n.t("adv.track_hint"), size: 13)
                        .multilineTextAlignment(.center)
                        .opacity(0.8)
                        .padding(.bottom, 4)
                    ForEach(Array(track.enumerated()), id: \.offset) { i, m in
                        let done = i < (a?.claimed ?? 0)
                        HStack(spacing: 10) {
                            PixelText("🚃 \(m.points)", size: 15).frame(width: 80, alignment: .leading)
                            PrizeIcon(prize: m.prize, size: 30)
                            PixelText(GameStore.describe(m.prize), size: 13)
                            Spacer()
                            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(done ? Theme.accent : Theme.wood.opacity(0.4))
                        }
                        .padding(10)
                        .background(PixelSlice(key: done ? "ui_paper_green" : "ui_paper", inset: 4))
                    }
                    PixelText(L10n.t("adv.depths.treasures"), size: 13)
                        .multilineTextAlignment(.center)
                        .opacity(0.8)
                        .padding(.top, 6)
                }
                .padding(16)
            }
        }
    }
}

/// Красная точка уведомления.
struct RedDot: View {
    var body: some View {
        Circle().fill(Color(red: 0.86, green: 0.25, blue: 0.3))
            .frame(width: 11, height: 11)
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
    }
}

/// Трещины на твердой породе после удара.
private struct Cracks: View {
    let level: Int

    var body: some View {
        Canvas { ctx, size in
            guard level > 0 else { return }
            var p = Path()
            let w = size.width, h = size.height
            p.move(to: CGPoint(x: w * 0.3, y: h * 0.2))
            p.addLine(to: CGPoint(x: w * 0.45, y: h * 0.45))
            p.addLine(to: CGPoint(x: w * 0.35, y: h * 0.7))
            if level > 1 {
                p.move(to: CGPoint(x: w * 0.45, y: h * 0.45))
                p.addLine(to: CGPoint(x: w * 0.75, y: h * 0.55))
                p.addLine(to: CGPoint(x: w * 0.7, y: h * 0.85))
            }
            ctx.stroke(p, with: .color(.black.opacity(0.45)), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
    }
}

/// Легкое покачивание находки, которая ждет места на поле.
private struct Bob: ViewModifier {
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .offset(y: up ? -2 : 1)
            .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { up = true } }
    }
}

/// Мерцание фонаря и клада сквозь породу.
private struct Glow: ViewModifier {
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .shadow(color: Color.yellow.opacity(on ? 0.9 : 0.2), radius: on ? 5 : 1)
            .onAppear { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { on = true } }
    }
}
