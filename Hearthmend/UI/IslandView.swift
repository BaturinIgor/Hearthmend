import SwiftUI
import HearthCore

/// «Остров»: прилив выносит предметы, три одинаковых рядом сливаются в один, пять - в два.
/// Слияния у края разгоняют туман, под ним подарки и клады.
struct IslandView: View {
    @EnvironmentObject private var store: GameStore
    @State private var selected: Int?
    @State private var flash: Set<Int> = []
    @State private var pop: Set<Int> = []
    @State private var showTrack = false
    @State private var showHelp = false

    private let cols = IslandState.cols

    var body: some View {
        PixelSheet(L10n.t("adv.island.title")) {
            VStack(spacing: 8) {
                AdventureHeader(movesIcon: "ui_shell", help: "adv.island.how", showHelp: $showHelp)
                AdventureTrackBar(icon: "ui_shell") { showTrack = true }
                island
                controls
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showTrack) { AdventureTrackSheet(icon: "🐚", note: "adv.island.treasures") }
        .onAppear {
            if (store.state.adventure?.points ?? 0) == 0 { showHelp = true }
        }
    }

    // MARK: - Остров

    private var island: some View {
        let s = store.state.adventure?.island
        let same: Item? = selected.flatMap { s?.cells[$0].item }
        return GeometryReader { geo in
            let side = floor(min((geo.size.width - CGFloat(cols - 1) * 2) / CGFloat(cols),
                                 (geo.size.height - CGFloat(IslandState.rows - 1) * 2) / CGFloat(IslandState.rows)))
            VStack(spacing: 2) {
                ForEach(0..<IslandState.rows, id: \.self) { r in
                    HStack(spacing: 2) {
                        ForEach(0..<cols, id: \.self) { c in
                            let i = r * cols + c
                            cell(i, state: s, side: side, same: same)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8)
        .background(PixelTile(key: "ui_water", scale: 3).clipShape(RoundedRectangle(cornerRadius: 8)))
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func cell(_ i: Int, state s: IslandState?, side: CGFloat, same: Item?) -> some View {
        let c = s?.cells[i]
        ZStack {
            if let c = c, !c.fog {
                PixelTile(key: (i / cols + i % cols) % 2 == 0 ? "ui_cell_a" : "ui_cell_b", scale: side / 16)
                if let item = c.item {
                    FindIcon(item: item, size: side * 0.78)
                        .scaleEffect(pop.contains(i) ? 1.25 : 1)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                        .id("\(i)-\(item.chain)-\(item.tier)")
                }
            } else {
                PixelTile(key: "ui_fog", scale: side / 16)
                if s?.treasureVisible(i) == true {
                    PixelIcon(key: "chest_3_items", size: side * 0.7).opacity(0.75).modifier(IslandGlow())
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(selected == i ? Color.white : .clear, lineWidth: 2.5))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(
            same != nil && selected != i && c?.item == same && c?.fog == false ? Theme.accent.opacity(0.9) : .clear, lineWidth: 2))
        .overlay(flash.contains(i) ? Color.white.opacity(0.7) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { tap(i) }
    }

    private func tap(_ i: Int) {
        guard let s = store.state.adventure?.island, s.cells.indices.contains(i) else { return }
        guard !s.cells[i].fog else {
            Haptics.light()
            store.show(L10n.t("adv.island.fog"))
            return
        }
        if let from = selected {
            if from == i {
                withAnimation(.spring(response: 0.25)) { selected = nil }
                return
            }
            let result = withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                store.moveOnIsland(from: from, to: i)
            }
            selected = nil
            if let r = result, !r.merges.isEmpty { celebrate(r) }
        } else if s.cells[i].item != nil {
            Haptics.light()
            withAnimation(.spring(response: 0.25)) { selected = i }
        }
    }

    private func celebrate(_ r: Game.IslandMove) {
        let born = Set(r.merges.map(\.at))
        flash = Set(r.cleared)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { pop = born }
        withAnimation(.easeOut(duration: 0.6)) { flash = [] }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { pop = [] }
        }
    }

    // MARK: - Кнопки

    private var controls: some View {
        let moves = store.state.adventure?.moves ?? 0
        return HStack(spacing: 10) {
            if let i = selected {
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { store.washAway(i); selected = nil }
                } label: {
                    HStack(spacing: 4) {
                        PixelIcon(key: "ui_wave", size: 20)
                        PixelText(L10n.t("adv.island.wash"), size: 14)
                    }
                }
                .buttonStyle(PixelButtonStyle(kind: .wood, size: 14))
            } else {
                PixelText(L10n.t("adv.island.hint"), size: 12)
                    .opacity(0.8)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    if case .placed(let i, _) = store.tide() {
                        pop = [i]
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { withAnimation(.spring()) { pop = [] } }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    PixelIcon(key: "ui_wave", size: 22)
                    PixelText(L10n.t("adv.island.tide"), size: 16)
                    PixelText("🐚1", size: 14).opacity(0.9)
                }
            }
            .buttonStyle(PixelButtonStyle(kind: .green, size: 16))
            .opacity(moves > 0 ? 1 : 0.6)
        }
        .padding(8)
        .background(PixelSlice(key: "ui_paper", inset: 4))
    }
}

/// Клад мерцает сквозь туман.
private struct IslandGlow: ViewModifier {
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .shadow(color: Color.yellow.opacity(on ? 0.9 : 0.2), radius: on ? 5 : 1)
            .onAppear { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { on = true } }
    }
}
