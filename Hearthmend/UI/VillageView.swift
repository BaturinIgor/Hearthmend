import SwiftUI
import UIKit
import HearthCore

/// Карта деревни: фон из тайлов пака, готовые постройки, стройплощадки текущего района.
/// Тап по стройплощадке открывает карточку задачи, постройка появляется с пружинкой и пылью.
struct VillageView: View {
    @EnvironmentObject private var store: GameStore
    @Binding var screen: Screen
    @State private var picked: VillageTask?
    @State private var justBuilt: String?
    @State private var showDecor = false
    @State private var moveHint = false

    /// Размер карты в пикселях пака (tools/village_map.py: 32 x 134 клеток по 16).
    static let mapSize = CGSize(width: 512, height: 2144)

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.36, green: 0.55, blue: 0.29).ignoresSafeArea()
            GeometryReader { geo in
                // пиксель-арт четкий только при целом числе точек экрана на пиксель карты:
                // 4 на 3x-экранах, 3 на 2x. Карта шире экрана и листается во все стороны.
                let screen = UIScreen.main.scale
                let scale = max(geo.size.width / Self.mapSize.width, (screen * 1.34).rounded() / screen)
                ScrollViewReader { proxy in
                    ScrollView([.vertical, .horizontal], showsIndicators: false) {
                        map(scale: scale)
                            .frame(width: Self.mapSize.width * scale, height: Self.mapSize.height * scale)
                            .padding(.top, 70)
                            .padding(.bottom, 120)
                            // без «резинки» по краям: карта не уезжает за край
                            .background(ScrollBounceOff())
                    }
                    .onAppear {
                        if let focus = focusTask {
                            // ждем раскладку карты: при запуске сразу в деревню прокрутка раньше не срабатывала
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                withAnimation(.easeInOut(duration: 0.6)) { proxy.scrollTo("focus_\(focus.id)", anchor: .center) }
                            }
                        }
                    }
                }
            }
            SeasonParticles(season: store.season)
            VStack(spacing: 6) {
                header
                if moveHint {
                    Label { Text(L10n.t("village.move_hint")) } icon: { PixelIcon(key: "ui_hammer", size: 18) }
                        .font(Pixel.font(14))
                        .foregroundColor(Theme.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(PixelSlice(key: "ui_paper_gold", inset: 4, scale: 2))
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onTapGesture { withAnimation { moveHint = false } }
                }
            }
            VStack {
                Spacer()
                if let task = picked {
                    TaskCard(task: task, close: { withAnimation(.spring(response: 0.35)) { picked = nil } }, build: { build(task) })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    if showDecor { DecorTray(place: placeDecor).transition(.move(edge: .bottom).combined(with: .opacity)) }
                    HStack(spacing: 10) {
                        BackToBoardButton { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { screen = .board } }
                        if Pets.all.contains(where: { store.game.petAvailable($0.id) }) {
                            PetsButton()
                        }
                        if !store.state.decorOwned.isEmpty || !store.state.placedDecor.isEmpty {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showDecor.toggle() }
                                if showDecor { store.seeNewDecor() }
                            } label: {
                                PixelIcon(key: "ui_plant", size: 28)
                                    .frame(width: 50, height: 50)
                                    .background(Circle().fill(showDecor ? Theme.accent : Theme.card))
                                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                                    .overlay(alignment: .topTrailing) { if store.state.newDecor { RedDot() } }
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            SheetToast().padding(.bottom, 70).frame(maxHeight: .infinity, alignment: .bottom)
        }
        .onAppear {
            // один раз подсказать, что постройки можно двигать
            let key = "moveHintShown"
            guard !Shot.isActive, store.state.completedTasks.count >= 4, !UserDefaults.standard.bool(forKey: key) else { return }
            UserDefaults.standard.set(true, forKey: key)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { withAnimation(.spring(response: 0.4)) { moveHint = true } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { withAnimation(.easeOut) { moveHint = false } }
        }
    }

    // MARK: - Карта

    private func map(scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            sprite("map_bg", scale: scale)
                .frame(width: Self.mapSize.width * scale, height: Self.mapSize.height * scale)
                .background(Color(red: 0.45, green: 0.66, blue: 0.33))
            ForEach(tasksByDepth) { task in
                let mode = buildState(task)
                BuildingView(task: task,
                             state: mode,
                             spot: store.game.spot(of: task),
                             scale: scale,
                             affordable: store.state.stars >= task.cost,
                             celebrate: justBuilt == task.id)
                    .id(task.id)
                    .modifier(BuildingMover(task: task, enabled: mode == .built, scale: scale))
                    .onTapGesture {
                        guard mode == .site else { return }
                        Haptics.light()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { picked = task }
                    }
            }
            ForEach(store.state.placedDecor) { decor in
                DecorPiece(decor: decor, scale: scale)
            }
            ForEach(store.state.petsOwned, id: \.self) { pet in
                if let area = store.game.petArea(pet) {
                    PetWalker(pet: pet, area: area, scale: scale)
                }
            }
            // точки для прокрутки: у постройки рамка от верха карты (отступы), а scrollTo
            // целится в середину рамки. Здесь рамка 1x1 ровно на постройке.
            ForEach(store.game.village.allTasks) { task in
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(width: 1, height: max(0, (CGFloat(task.y) - 2) * 16 * scale))
                    HStack(spacing: 0) {
                        Color.clear.frame(width: max(0, CGFloat(task.x) * 16 * scale), height: 1)
                        Color.clear.frame(width: 1, height: 1).id("focus_\(task.id)")
                    }
                }
                .allowsHitTesting(false)
            }
            if let row = store.game.fogRow, row > 0 {
                LockedFog(height: CGFloat(row) * 16 * scale, next: store.game.nextLockedDistrict.map { L10n.t("district.\($0.id)") })
                    .frame(width: Self.mapSize.width * scale)
                    .transition(.opacity)
            }
        }
        .colorMultiply(store.season.tint)
        .saturation(store.season.saturation)
        .overlay(Color.white.opacity(store.season.frost).allowsHitTesting(false))
        .animation(.easeInOut(duration: 1.2), value: store.game.fogRow)
    }

    private var tasksByDepth: [VillageTask] {
        store.game.village.allTasks.sorted { store.game.spot(of: $0).y < store.game.spot(of: $1).y }
    }

    private func buildState(_ task: VillageTask) -> BuildingView.Mode {
        if store.state.completedTasks.contains(task.id) { return .built }
        if store.game.isAvailable(task) { return .site }
        if let d = store.game.village.district(of: task.id), store.game.isDistrictOpen(d) { return .planned }
        return .hidden
    }

    /// Новое украшение ставится у дороги рядом с текущим районом; дальше игрок двигает его пальцем.
    private func placeDecor(_ key: String) {
        let y = Double(focusTask?.y ?? 70) + 2
        let x = 17.5 + Double(store.state.placedDecor.count % 5)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { store.placeDecor(key, x: x, y: y) }
    }

    private var focusTask: VillageTask? {
        if let id = Shot.focus, let task = store.game.village.task(id) { return task }
        return store.game.availableTasks.first ?? store.game.village.allTasks.last
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
                    .font(Pixel.font(18))
                SeasonChip(season: store.season)
                Spacer()
                PixelText("⭐️ \(store.state.stars)", size: 14)
                    .font(Pixel.font(17))
            }
            ProgressBar(value: district == nil ? 1 : Double(done) / Double(total))
                .frame(height: 14)
        }
        .foregroundColor(Theme.text)
        .padding(12)
        .background(PixelSlice(key: "ui_paper", inset: 4))
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}

/// Украшение на карте: перетаскивается пальцем, долгое нажатие убирает в запас.
private struct DecorPiece: View {
    @EnvironmentObject private var store: GameStore
    let decor: PlacedDecor
    let scale: CGFloat
    @State private var drag: CGSize = .zero
    @State private var lifted = false

    var body: some View {
        let image = Sprites.image(decor.key)
        let w = (image?.size.width ?? 16) * scale, h = (image?.size.height ?? 16) * scale
        DecorIcon(key: decor.key, size: max(w, h))
            .frame(width: w, height: h)
            .scaleEffect(lifted ? 1.15 : 1, anchor: .bottom)
            .shadow(color: .black.opacity(lifted ? 0.35 : 0), radius: 4, y: 3)
            .padding(.leading, max(0, CGFloat(decor.x) * 16 * scale - w / 2))
            .padding(.top, max(0, CGFloat(decor.y) * 16 * scale - h))
            .offset(drag)
            .highPriorityGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { v in
                        if !lifted { Haptics.light() }
                        lifted = true
                        drag = v.translation
                    }
                    .onEnded { v in
                        let cell = 16 * scale
                        store.moveDecor(id: decor.id, x: decor.x + Double(v.translation.width / cell),
                                        y: decor.y + Double(v.translation.height / cell))
                        drag = .zero
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { lifted = false }
                    }
            )
            .onLongPressGesture(minimumDuration: 0.6) {
                withAnimation(.spring(response: 0.3)) { store.storeDecor(id: decor.id) }
                store.show(L10n.t("decor.stored"))
            }
    }
}

/// Запас украшений: тап ставит украшение на карту.
private struct DecorTray: View {
    @EnvironmentObject private var store: GameStore
    let place: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("decor.hint"))
                .font(Pixel.font(12))
                .foregroundColor(Theme.text.opacity(0.8))
            if store.state.decorOwned.isEmpty {
                Text(L10n.t("decor.empty"))
                    .font(Pixel.font(13))
                    .foregroundColor(Theme.text)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.state.decorOwned.keys.sorted(), id: \.self) { key in
                            Button { place(key) } label: {
                                ZStack(alignment: .topTrailing) {
                                    DecorIcon(key: key, size: 40)
                                        .frame(width: 52, height: 52)
                                        .background(PixelSlice(key: "ui_paper", inset: 4))
                                    Text("\(store.state.decorOwned[key] ?? 0)")
                                        .font(Pixel.font(11))
                                        .foregroundColor(.white)
                                        .padding(4)
                                        .background(Circle().fill(Theme.wood))
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(PixelSlice(key: "ui_paper", inset: 4))
    }
}

enum Screen: Equatable {
    case board, village
}

/// Спрайт по ключу без сглаживания; пустое место, если спрайтов нет (сборка без пака).
@MainActor
func sprite(_ key: String, scale: CGFloat) -> some View {
    Group {
        if let image = Sprites.image(key) {
            Image(uiImage: image).resizable().interpolation(.none)
        } else {
            Color.clear
        }
    }
}

@MainActor
struct BuildingView: View {
    enum Mode { case built, site, planned, hidden }

    let task: VillageTask
    let mode: Mode
    let spot: (x: Double, y: Double)
    let scale: CGFloat
    let affordable: Bool
    let celebrate: Bool
    @State private var bob = false
    @State private var spin = false
    @State private var dust = false

    init(task: VillageTask, state: Mode, spot: (x: Double, y: Double), scale: CGFloat, affordable: Bool, celebrate: Bool) {
        self.task = task
        self.mode = state
        self.spot = spot
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
        let left = CGFloat(spot.x) * 16 * scale - s.width / 2
        let top = CGFloat(spot.y) * 16 * scale - s.height
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
        PixelText("⭐️\(task.cost)", size: 15)
        .lineLimit(1)
        .fixedSize()
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(PixelSlice(key: affordable ? "ui_btn_green" : "ui_btn_wood", inset: 5, scale: 2))
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        .scaleEffect(affordable ? 1.1 : 0.95)
    }
}

/// Готовую постройку можно передвинуть: удержать и тащить пальцем. Двойной тап по
/// поднятой постройке не нужен: отпустил - встала на новое место.
private struct BuildingMover: ViewModifier {
    @EnvironmentObject private var store: GameStore
    let task: VillageTask
    let enabled: Bool
    let scale: CGFloat
    @State private var drag: CGSize = .zero
    @State private var lifted = false

    func body(content: Content) -> some View {
        if enabled {
            content
                .scaleEffect(lifted ? 1.08 : 1, anchor: .bottom)
                .shadow(color: .black.opacity(lifted ? 0.35 : 0), radius: 6, y: 4)
                .offset(drag)
                .zIndex(lifted ? 10 : 0)
                .gesture(
                    LongPressGesture(minimumDuration: 0.35)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .onChanged { value in
                            guard case .second(true, let d) = value else { return }
                            if !lifted {
                                Haptics.light()
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { lifted = true }
                            }
                            drag = d?.translation ?? .zero
                        }
                        .onEnded { value in
                            if case .second(true, let d?) = value {
                                let cell = 16 * scale
                                let spot = store.game.spot(of: task)
                                store.moveBuilding(task.id, x: spot.x + Double(d.translation.width / cell),
                                                   y: spot.y + Double(d.translation.height / cell))
                            }
                            drag = .zero
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { lifted = false }
                        }
                )
        } else {
            content
        }
    }
}

/// Находит UIScrollView, в котором лежит, и выключает у него пружинку по краям.
private struct ScrollBounceOff: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async {
            var v = view.superview
            while let current = v {
                if let scroll = current as? UIScrollView {
                    scroll.bounces = false
                    break
                }
                v = current.superview
            }
        }
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

@MainActor
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
                        .font(Pixel.font(18))
                    if let resident = task.resident {
                        Text(String(format: L10n.t("task.resident"), L10n.t("resident.\(resident)")))
                            .font(Pixel.font(13))
                            .foregroundColor(Theme.accent)
                    }
                    if let gems = task.gems {
                        PixelText(String(format: L10n.t("task.gems"), gems), size: 13)
                    }
                }
                Spacer()
                Button(action: close) {
                    PixelIcon(key: "ui_close", size: 30)
                }
            }
            Button(action: build) {
                PixelText(enough ? String(format: L10n.t("task.build"), task.cost)
                                 : String(format: L10n.t("task.need_stars"), task.cost - store.state.stars), size: 17)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(PixelSlice(key: "ui_btn_green", inset: 5, scale: 3).saturation(enough ? 1 : 0).opacity(enough ? 1 : 0.6))
            }
            .disabled(!enough)
        }
        .foregroundColor(Theme.text)
        .padding(14)
        .background(PixelSlice(key: "ui_paper", inset: 4))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }
}

private struct BackToBoardButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(L10n.t("nav.board"), systemImage: "square.grid.3x3.fill")
                .font(Pixel.font(17))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .frame(minHeight: 50)
                .background(PixelSlice(key: "ui_btn_wood", inset: 5, scale: 2))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        }
    }
}

struct ProgressBar: View {
    let value: Double
    var fill = "ui_bar_fill"

    var body: some View { PixelBar(value: value, fill: fill) }
}

/// Туман над закрытыми районами: облака и название района, который откроется следующим.
private struct LockedFog: View {
    let height: CGFloat
    let next: String?
    @State private var drift = false

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(stops: [
                .init(color: Color(red: 0.93, green: 0.95, blue: 0.97), location: 0),
                .init(color: Color(red: 0.93, green: 0.95, blue: 0.97).opacity(0.92), location: 0.82),
                .init(color: Color(red: 0.93, green: 0.95, blue: 0.97).opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            // облака по нижнему краю тумана медленно плывут
            HStack(spacing: -18) {
                ForEach(0..<7, id: \.self) { i in
                    Ellipse()
                        .fill(Color.white)
                        .frame(width: 90 + CGFloat(i % 3) * 22, height: 46 + CGFloat(i % 2) * 14)
                        .offset(y: CGFloat((i * 13) % 20) - 4)
                }
            }
            .blur(radius: 6)
            .offset(x: drift ? 16 : -16, y: 6)
            .opacity(0.9)
            if let next {
                Label { Text(String(format: L10n.t("village.fog_next"), next)) } icon: { PixelIcon(key: "ui_lock", size: 18) }
                    .font(Pixel.font(14))
                    .foregroundColor(Theme.text.opacity(0.75))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(PixelSlice(key: "ui_paper", inset: 4, scale: 2))
                    .padding(.bottom, 40)
            }
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}
