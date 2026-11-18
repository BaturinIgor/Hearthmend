import SwiftUI
import HearthCore

/// «Витраж»: окно 6x8 из цветных осколков и верстак на 6 кусочков. Два одинаковых кусочка
/// сливаются в больший; кусочек кладут на осколок своего цвета, и он заполняет ближайшие клетки.
struct MosaicView: View {
    @EnvironmentObject private var store: GameStore
    @State private var selected: Int?
    @State private var pop: Int?
    @State private var flash: Set<Int> = []
    @State private var glow = false
    @State private var celebrate = false
    @State private var showTrack = false
    @State private var showHelp = false

    private let cols = MosaicState.cols
    private let rows = MosaicState.rows

    var body: some View {
        PixelSheet(L10n.t("adv.mosaic.title")) {
            VStack(spacing: 8) {
                AdventureHeader(movesIcon: "ui_glass", help: "adv.mosaic.how", showHelp: $showHelp)
                AdventureTrackBar(icon: "ui_glass") { showTrack = true }
                window
                bench
                controls
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showTrack) { AdventureTrackSheet(icon: "🔷", note: "adv.mosaic.window") }
        .onAppear {
            if (store.state.adventure?.points ?? 0) == 0 { showHelp = true }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { glow = true }
        }
    }

    private var mosaic: MosaicState? { store.state.adventure?.mosaic }
    private var selectedColor: Int? {
        guard let i = selected, let item = mosaic?.bench[i] ?? nil else { return nil }
        return MosaicState.color(of: item)
    }

    // MARK: - Окно

    private var window: some View {
        GeometryReader { geo in
            let side = floor(min(geo.size.width / CGFloat(cols), geo.size.height / CGFloat(rows)))
            let w = side * CGFloat(cols), h = side * CGFloat(rows)
            ZStack {
                if let m = mosaic {
                    VStack(spacing: 0) {
                        ForEach(0..<rows, id: \.self) { r in
                            HStack(spacing: 0) {
                                ForEach(0..<cols, id: \.self) { c in
                                    cell(r * cols + c, m: m, side: side)
                                }
                            }
                        }
                    }
                    LeadLines(regions: m.regions, cols: cols, rows: rows)
                        .allowsHitTesting(false)
                    // свет сквозь стекло
                    LinearGradient(colors: [.white.opacity(0.22), .clear, .white.opacity(0.08)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .allowsHitTesting(false)
                    if celebrate {
                        Color.white.opacity(0.85).transition(.opacity).allowsHitTesting(false)
                    }
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 0.42, green: 0.28, blue: 0.16), lineWidth: 5))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.72, green: 0.52, blue: 0.3), lineWidth: 2).padding(-4))
            .id(m_key)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(6)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if let m = mosaic, m.windows > 0 {
                PixelText("🪟 \(m.windows)", size: 13)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.85)))
            }
        }
    }

    /// Новое окно появляется заново, а не перекрашивает старое.
    private var m_key: Int { mosaic?.windows ?? 0 }

    private func cell(_ i: Int, m: MosaicState, side: CGFloat) -> some View {
        let color = Self.glass(m.colors[i])
        let filled = m.filled[i]
        let target = !filled && selectedColor == m.colors[i]
        return ZStack {
            if filled {
                LinearGradient(colors: [color.lighter(0.25), color, color.darker(0.15)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // блик на части клеток, чтобы стекло не было плоским
                if (i * 7 + m.regions[i] * 3) % 5 == 0 {
                    Path { p in
                        p.move(to: CGPoint(x: side * 0.2, y: side * 0.6))
                        p.addLine(to: CGPoint(x: side * 0.6, y: side * 0.2))
                    }
                    .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            } else {
                Color(red: 0.16, green: 0.14, blue: 0.2)
                color.opacity(target ? (glow ? 0.65 : 0.4) : 0.26)
                Circle().fill(color.opacity(0.7)).frame(width: side * 0.16, height: side * 0.16)
            }
            if flash.contains(i) {
                Color.white.opacity(0.7).transition(.opacity)
            }
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .onTapGesture { tapCell(i, m: m) }
    }

    static func glass(_ color: Int) -> Color {
        switch color {
        case 0: return Color(red: 0.86, green: 0.24, blue: 0.34)
        case 1: return Color(red: 0.98, green: 0.7, blue: 0.22)
        case 2: return Color(red: 0.22, green: 0.72, blue: 0.44)
        default: return Color(red: 0.27, green: 0.5, blue: 0.93)
        }
    }

    // MARK: - Верстак

    private var bench: some View {
        let m = mosaic
        let same: Item? = selected.flatMap { m?.bench[$0] ?? nil }
        return HStack(spacing: 6) {
            ForEach(0..<MosaicState.benchSize, id: \.self) { i in
                let item = m?.bench[i] ?? nil
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.62, green: 0.44, blue: 0.28))
                    RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.74, green: 0.56, blue: 0.36)).padding(3)
                    if let item, let color = MosaicState.color(of: item) {
                        GlassPiece(color: Self.glass(color), tier: item.tier)
                            .scaleEffect(pop == i ? 1.25 : 1)
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                            .id("\(i)-\(item.chain)-\(item.tier)")
                        Text("×\(Mosaic.cover[min(item.tier, Mosaic.maxTier)])")
                            .font(Pixel.digits(11))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(2)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected == i ? Color.white : .clear, lineWidth: 3))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(
                    same != nil && selected != i && item == same && (same?.tier ?? 9) < Mosaic.maxTier ? Theme.accent : .clear,
                    lineWidth: 2.5))
                .contentShape(Rectangle())
                .onTapGesture { tapBench(i, item: item) }
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.5, green: 0.34, blue: 0.2)))
    }

    // MARK: - Касания

    private func tapBench(_ i: Int, item: Item?) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if let from = selected {
                selected = nil
                guard from != i else { return }
                if store.moveGlass(from: from, to: i) { bounce(i) }
            } else if item != nil {
                Haptics.light()
                selected = i
            } else if case .cut(let slot, _) = store.cutGlass() {
                bounce(slot)
            }
        }
    }

    /// Тап по клетке кладет выбранный кусочек. Без выбора берется самый маленький кусочек нужного цвета.
    private func tapCell(_ i: Int, m: MosaicState) {
        guard !m.filled[i] else { return }
        let slot = selected ?? m.bench.indices
            .filter { m.bench[$0].flatMap(MosaicState.color(of:)) == m.colors[i] }
            .min { (m.bench[$0]?.tier ?? 0, $0) < (m.bench[$1]?.tier ?? 0, $1) }
        guard let slot else {
            Haptics.light()
            return
        }
        selected = nil
        let windows = m.windows
        guard let r = store.setGlass(slot: slot, cell: i) else { return }
        if r.windowDone || (store.state.adventure?.mosaic?.windows ?? windows) != windows {
            withAnimation(.easeIn(duration: 0.25)) { celebrate = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeOut(duration: 0.5)) { celebrate = false }
            }
            return
        }
        // клетки загораются по очереди от места, куда положили
        for (n, c) in r.cells.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(n) * 0.04) {
                withAnimation(.easeOut(duration: 0.12)) { _ = flash.insert(c) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.easeOut(duration: 0.3)) { _ = flash.remove(c) }
                }
            }
        }
    }

    private func bounce(_ i: Int) {
        pop = i
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { withAnimation(.spring()) { pop = nil } }
    }

    // MARK: - Кнопки

    private var controls: some View {
        HStack(spacing: 10) {
            if let i = selected {
                Button {
                    withAnimation(.spring(response: 0.3)) { store.shatterGlass(i); selected = nil }
                } label: {
                    PixelText(L10n.t("adv.mosaic.shatter"), size: 14)
                }
                .buttonStyle(PixelButtonStyle(kind: .wood, size: 14))
            }
            Spacer()
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    if case .cut(let slot, _) = store.cutGlass() { bounce(slot) }
                }
            } label: {
                HStack(spacing: 6) {
                    PixelIcon(key: "ui_glass", size: 22)
                    PixelText(L10n.t("adv.mosaic.cut"), size: 16)
                }
            }
            .buttonStyle(PixelButtonStyle(kind: .green, size: 16))
            .opacity((store.state.adventure?.moves ?? 0) > 0 ? 1 : 0.6)
        }
        .padding(8)
        .background(PixelSlice(key: "ui_paper", inset: 4))
    }
}

/// Кусочек стекла на верстаке: чем выше ступень, тем крупнее и граненее.
private struct GlassPiece: View {
    let color: Color
    let tier: Int

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) * [0.5, 0.64, 0.76, 0.88][min(max(tier, 0), 3)]
            ZStack {
                Shard(points: 5 + tier)
                    .fill(LinearGradient(colors: [color.lighter(0.3), color, color.darker(0.2)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Shard(points: 5 + tier)
                    .stroke(Color(red: 0.24, green: 0.2, blue: 0.28), lineWidth: 2)
                Path { p in
                    p.move(to: CGPoint(x: s * 0.28, y: s * 0.55))
                    p.addLine(to: CGPoint(x: s * 0.52, y: s * 0.28))
                }
                .stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            .frame(width: s, height: s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .shadow(color: color.opacity(tier >= 2 ? 0.8 : 0), radius: 4)
        }
    }
}

/// Неровный многоугольник осколка.
private struct Shard: Shape {
    let points: Int

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        for k in 0..<points {
            let a = Double(k) / Double(points) * 2 * .pi - .pi / 2 + 0.3
            let r = (k % 2 == 0 ? 0.5 : 0.42) * Double(min(rect.width, rect.height))
            let pt = CGPoint(x: c.x + CGFloat(cos(a) * r), y: c.y + CGFloat(sin(a) * r))
            if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// Свинцовые линии между осколками: толстые на границах областей, тонкие внутри.
private struct LeadLines: View {
    let regions: [Int]
    let cols: Int
    let rows: Int

    var body: some View {
        Canvas { ctx, size in
            let w = size.width / CGFloat(cols), h = size.height / CGFloat(rows)
            var thick = Path(), thin = Path()
            for r in 0..<rows {
                for c in 0..<cols {
                    let i = r * cols + c
                    if c < cols - 1 {
                        let x = CGFloat(c + 1) * w
                        var seg = Path()
                        seg.move(to: CGPoint(x: x, y: CGFloat(r) * h))
                        seg.addLine(to: CGPoint(x: x, y: CGFloat(r + 1) * h))
                        if regions[i] != regions[i + 1] { thick.addPath(seg) } else { thin.addPath(seg) }
                    }
                    if r < rows - 1 {
                        let y = CGFloat(r + 1) * h
                        var seg = Path()
                        seg.move(to: CGPoint(x: CGFloat(c) * w, y: y))
                        seg.addLine(to: CGPoint(x: CGFloat(c + 1) * w, y: y))
                        if regions[i] != regions[i + cols] { thick.addPath(seg) } else { thin.addPath(seg) }
                    }
                }
            }
            let lead = Color(red: 0.2, green: 0.17, blue: 0.24)
            ctx.stroke(thin, with: .color(lead.opacity(0.35)), lineWidth: 1)
            ctx.stroke(thick, with: .color(lead), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        }
    }
}

private extension Color {
    func lighter(_ k: Double) -> Color { blend(.white, k) }
    func darker(_ k: Double) -> Color { blend(.black, k) }

    func blend(_ other: Color, _ k: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(k)
        return Color(red: Double(r1 + (r2 - r1) * t), green: Double(g1 + (g2 - g1) * t), blue: Double(b1 + (b2 - b1) * t))
    }
}
