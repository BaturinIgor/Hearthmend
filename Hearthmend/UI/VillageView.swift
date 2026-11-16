import SwiftUI
import HearthCore

/// Карта деревни: фон из тайлов пака, готовые постройки, стройплощадки текущего района.
/// Тап по стройплощадке открывает карточку задачи, постройка появляется с пружинкой и пылью.
struct VillageView: View {
    @EnvironmentObject private var store: GameStore
    @Binding var screen: Screen
    @State private var picked: VillageTask?
    @State private var justBuilt: String?

    /// Размер карты в пикселях пака (tools/village_map.py: 32 x 50 клеток по 16).
    static let mapSize = CGSize(width: 512, height: 800)

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.36, green: 0.55, blue: 0.29).ignoresSafeArea()
            GeometryReader { geo in
                let scale = geo.size.width / Self.mapSize.width
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        map(scale: scale)
                            .frame(width: Self.mapSize.width * scale, height: Self.mapSize.height * scale)
                            .padding(.top, 70)
                            .padding(.bottom, 120)
                    }
                    .onAppear {
                        if let focus = focusTask {
                            DispatchQueue.main.async {
                                withAnimation(.easeInOut(duration: 0.6)) { proxy.scrollTo(focus.id, anchor: .center) }
                            }
                        }
                    }
                }
            }
            header
            VStack {
                Spacer()
                if let task = picked {
                    TaskCard(task: task, close: { withAnimation(.spring(response: 0.35)) { picked = nil } }, build: { build(task) })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    BackToBoardButton { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { screen = .board } }
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Карта

    private func map(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            sprite("map_bg", scale: scale)
                .frame(width: Self.mapSize.width * scale, height: Self.mapSize.height * scale)
                .background(Color(red: 0.45, green: 0.66, blue: 0.33))
            ForEach(tasksByDepth) { task in
                BuildingView(task: task,
                             state: buildState(task),
                             scale: scale,
                             affordable: store.state.stars >= task.cost,
                             celebrate: justBuilt == task.id)
                    .id(task.id)
                    .onTapGesture {
                        guard buildState(task) == .site else { return }
                        Haptics.light()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { picked = task }
                    }
            }
        }
    }

    private var tasksByDepth: [VillageTask] {
        store.game.village.allTasks.sorted { $0.y < $1.y }
    }

    private func buildState(_ task: VillageTask) -> BuildingView.Mode {
        if store.state.completedTasks.contains(task.id) { return .built }
        if store.game.isAvailable(task) { return .site }
        if let d = store.game.village.district(of: task.id), store.game.isDistrictOpen(d) { return .planned }
        return .hidden
    }

    private var focusTask: VillageTask? {
        store.game.availableTasks.first ?? store.game.village.allTasks.last
    }

    private func build(_ task: VillageTask) {
        if store.completeTask(task.id) {
            withAnimation(.spring(response: 0.35)) { picked = nil }
            justBuilt = task.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                if justBuilt == task.id { justBuilt = nil }
            }
        }
    }

    // MARK: - Шапка

    private var header: some View {
        let district = store.game.currentDistrict
        let done = district?.tasks.filter { store.state.completedTasks.contains($0.id) }.count ?? 0
        let total = district?.tasks.count ?? 1
        return VStack(spacing: 6) {
            HStack {
                Text(district.map { L10n.t("district.\($0.id)") } ?? L10n.t("village.done"))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                Spacer()
                Text("⭐️ \(store.state.stars)")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
            }
            ProgressBar(value: district == nil ? 1 : Double(done) / Double(total))
                .frame(height: 10)
        }
        .foregroundColor(Theme.text)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card.opacity(0.96)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.wood.opacity(0.5), lineWidth: 1.5))
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}

enum Screen: Equatable {
    case board, village
}

/// Спрайт по ключу без сглаживания; пустое место, если спрайтов нет (сборка без пака).
func sprite(_ key: String, scale: CGFloat) -> some View {
    Group {
        if let image = Sprites.image(key) {
            Image(uiImage: image).resizable().interpolation(.none)
        } else {
            Color.clear
        }
    }
}

struct BuildingView: View {
    enum Mode { case built, site, planned, hidden }

    let task: VillageTask
    let mode: Mode
    let scale: CGFloat
    let affordable: Bool
    let celebrate: Bool
    @State private var bob = false
    @State private var spin = false
    @State private var dust = false

    init(task: VillageTask, state: Mode, scale: CGFloat, affordable: Bool, celebrate: Bool) {
        self.task = task
        self.mode = state
        self.scale = scale
        self.affordable = affordable
        self.celebrate = celebrate
    }

    private var size: CGSize {
        let image = Sprites.image(task.building)
        return CGSize(width: (image?.size.width ?? 32) * scale, height: (image?.size.height ?? 32) * scale)
    }

    var body: some View {
        let s = size
        // x, y в village.json - середина нижнего края постройки в клетках по 16 пикселей
        let left = CGFloat(task.x) * 16 * scale - s.width / 2
        let top = CGFloat(task.y) * 16 * scale - s.height
        ZStack {
            if mode != .hidden {
                building(s)
                if mode == .site { badge.offset(y: -s.height / 2 - 8 + (bob ? -4 : 2)) }
                if celebrate { DustBurst(width: s.width).offset(y: s.height / 2 - 6) }
            }
        }
        .frame(width: s.width, height: s.height)
        // отступы, а не offset: тогда ScrollViewReader прокручивает к самой постройке
        .padding(.leading, max(0, left))
        .padding(.top, max(0, top))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { bob = true }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { spin = true }
        }
    }

    @ViewBuilder
    private func building(_ s: CGSize) -> some View {
        let img = sprite(task.building, scale: scale)
            .frame(width: s.width, height: s.height)
        switch mode {
        case .built:
            ZStack(alignment: .topLeading) {
                img
                if task.building == "bld_windmill", Sprites.image("bld_windmill_blades") != nil {
                    // ось крыльев: WINDMILL_HUB из tools/village_map.py
                    sprite("bld_windmill_blades", scale: scale)
                        .frame(width: 64 * scale, height: 64 * scale)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .offset(x: (22 - 32) * scale, y: (40 - 32) * scale)
                }
            }
            .transition(.scale(scale: 0.4, anchor: .bottom).combined(with: .opacity))
            .modifier(PopIn(active: celebrate))
        case .site:
            img
                .saturation(0)
                .brightness(0.25)
                .opacity(0.45)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: s.width + 6, height: max(10, s.height * 0.25))
                        .offset(y: s.height * 0.38)
                )
        case .planned:
            img.saturation(0).opacity(0.18)
        case .hidden:
            EmptyView()
        }
    }

    private var badge: some View {
        HStack(spacing: 2) {
            Text("⭐️").font(.system(size: 12))
            Text("\(task.cost)").font(.system(size: 13, weight: .heavy, design: .rounded))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(affordable ? Theme.accent : Theme.wood))
        .overlay(Capsule().stroke(.white, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        .scaleEffect(affordable ? 1.1 : 0.95)
    }
}

/// Пружинка при появлении новой постройки.
private struct PopIn: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 1 + (1 - phase) * 0.5, y: phase, anchor: .bottom)
            .onAppear { if active { pop() } }
            .onChange(of: active) { on in if on { pop() } }
    }

    private func pop() {
        phase = 0.55
        withAnimation(.spring(response: 0.45, dampingFraction: 0.45)) { phase = 1 }
    }
}

/// Клубы пыли и искры у основания постройки.
private struct DustBurst: View {
    let width: CGFloat
    @State private var go = false

    var body: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { i in
                let angle = Double(i) / 10 * .pi * 2
                Circle()
                    .fill(i.isMultiple(of: 3) ? Color.yellow.opacity(0.9) : Color.white.opacity(0.85))
                    .frame(width: i.isMultiple(of: 3) ? 6 : 12, height: i.isMultiple(of: 3) ? 6 : 12)
                    .offset(x: go ? cos(angle) * width * 0.6 : 0, y: go ? sin(angle) * 18 - 10 : 0)
                    .opacity(go ? 0 : 1)
                    .scaleEffect(go ? 1.6 : 0.4)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { go = true } }
        .allowsHitTesting(false)
    }
}

private struct TaskCard: View {
    @EnvironmentObject private var store: GameStore
    let task: VillageTask
    let close: () -> Void
    let build: () -> Void

    var body: some View {
        let enough = store.state.stars >= task.cost
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                sprite(task.building, scale: 1)
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("task.\(task.id)"))
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                    if let resident = task.resident {
                        Text(String(format: L10n.t("task.resident"), L10n.t("resident.\(resident)")))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.accent)
                    }
                    if let gems = task.gems {
                        Text(String(format: L10n.t("task.gems"), gems))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                }
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 24)).foregroundColor(Theme.wood.opacity(0.6))
                }
            }
            Button(action: build) {
                Text(enough ? String(format: L10n.t("task.build"), task.cost)
                            : String(format: L10n.t("task.need_stars"), task.cost - store.state.stars))
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 12).fill(enough ? Theme.accent : Color.gray.opacity(0.55)))
            }
            .disabled(!enough)
        }
        .foregroundColor(Theme.text)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.wood.opacity(0.5), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }
}

private struct BackToBoardButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(L10n.t("nav.board"), systemImage: "square.grid.3x3.fill")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .frame(minHeight: 50)
                .background(Capsule().fill(Theme.wood))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        }
    }
}

struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.wood.opacity(0.2))
                Capsule().fill(Theme.accent)
                    .frame(width: max(8, geo.size.width * min(1, max(0, value))))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: value)
            }
        }
    }
}
