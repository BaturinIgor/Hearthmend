import SwiftUI
import SpriteKit
import HearthCore

struct ContentView: View {
    @EnvironmentObject private var store: GameStore
    @State private var scene = BoardScene(size: CGSize(width: 350, height: 450))
    @State private var screen: Screen = CommandLine.arguments.contains("-village") ? .village : .board
    @State private var showShop = CommandLine.arguments.contains("-shop")
    @State private var showSettings = false
    @State private var showDaily = false
    @State private var story: String?

    var body: some View {
        ZStack {
            board
            if screen == .village {
                VillageView(screen: $screen)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
            if showDaily {
                DailyRewardView { withAnimation(.spring(response: 0.35)) { showDaily = false } }
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                    .zIndex(3)
            }
            if let c = store.celebration {
                CelebrationView(celebration: c) {
                    withAnimation(.spring(response: 0.35)) { store.celebration = nil }
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .zIndex(2)
            }
            ShortageLayer().zIndex(5)
            if let scene = story {
                StoryView(scene: scene) {
                    store.storySeen(scene)
                    story = nil
                    checkStory()
                }
                .zIndex(4)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: screen)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: showDaily)
        .sheet(isPresented: $showShop) { ShopView() }
        .background(EmptyView().sheet(isPresented: $showSettings) { SettingsView() })
        .onAppear {
            if store.game.dailyRewardReady, store.game.tutorial == .done, !Shot.isActive {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { showDaily = true }
            }
            checkStory()
        }
        .onChange(of: store.celebration) { c in if c == nil { checkStory() } }
        .onChange(of: showDaily) { open in if !open { checkStory() } }
        .onChange(of: store.state.completedTasks.count) { _ in checkStory() }
        .onChange(of: store.state.tutorialStep) { _ in checkStory() }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: store.celebration)
    }

    /// Сцена истории всплывает, когда ничего другого на экране нет.
    private func checkStory() {
        guard !Shot.isActive else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard story == nil, store.celebration == nil, !showDaily, let scene = store.pendingStory else { return }
            withAnimation(.spring(response: 0.4)) { story = scene }
        }
    }

    private var board: some View {
        ZStack(alignment: .bottom) {
            PixelTile(key: "ui_bg").ignoresSafeArea()
            VStack(spacing: 8) {
                TopIcons(openDaily: { withAnimation(.spring(response: 0.35)) { showDaily = true } },
                         openShop: { showShop = true },
                         openVillage: { screen = .village })
                TopBar(openVillage: { screen = .village }, openShop: { showShop = true }, openSettings: { showSettings = true })
                OrdersStrip()
                EventBanner()
                SpriteView(scene: scene, options: [.allowsTransparency])
                    .aspectRatio(CGFloat(store.balance.cols) / CGFloat(store.balance.rows), contentMode: .fit)
                    .padding(10)
                    .background(PixelSlice(key: "ui_panel", inset: 6, scale: 2))
                    .padding(.horizontal, 6)
                SelectedBar()
                    .padding(.bottom, 6)
            }
            .padding(.top, 4)
            TutorialTip(openVillage: { screen = .village })
                .padding(.bottom, 54)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.state.tutorialStep)
            if let toast = store.toast {
                PixelText(toast, size: 15)
                    .font(Pixel.font(15))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .padding(.bottom, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.toast)
        .onAppear {
            scene.store = store
            store.onBoardChange = { [weak scene] in scene?.render() }
            store.onHighlight = { [weak scene] cells in scene?.highlight(cells) }
            scene.render()
        }
        .onChange(of: store.selected) { _ in scene.updateSelection() }
    }
}

/// Карточка праздника: всплывает с пружинкой, закрывается тапом или сама через пару секунд.
private struct CelebrationView: View {
    let celebration: Celebration
    let close: () -> Void
    @State private var glow = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture(perform: close)
            VStack(spacing: 10) {
                Group {
                    if celebration.icon.hasPrefix("npc:") {
                        ResidentIcon(id: String(celebration.icon.dropFirst(4)), size: 72)
                    } else {
                        EmojiIcon(celebration.icon, size: 64)
                    }
                }
                    .scaleEffect(glow ? 1.12 : 0.95)
                    .rotationEffect(.degrees(glow ? 6 : -6))
                Text(celebration.title)
                    .font(Pixel.font(24))
                    .multilineTextAlignment(.center)
                PixelText(celebration.subtitle, size: 16)
                    .multilineTextAlignment(.center)
                    .opacity(0.85)
            }
            .foregroundColor(Theme.text)
            .padding(28)
            .frame(maxWidth: 320)
            .background(PixelSlice(key: "ui_panel", inset: 6))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            .onTapGesture(perform: close)
        }
        .onAppear {
            Haptics.success()
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { glow = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: close)
        }
    }
}

enum Theme {
    static let background = Color(red: 0.96, green: 0.91, blue: 0.80)
    static let card = Color(red: 1.0, green: 0.97, blue: 0.90)
    static let wood = Color(red: 0.55, green: 0.36, blue: 0.20)
    static let text = Color(red: 0.30, green: 0.20, blue: 0.10)
    static let accent = Color(red: 0.36, green: 0.62, blue: 0.27)
}

private struct TopBar: View {
    @EnvironmentObject private var store: GameStore
    let openVillage: () -> Void
    let openShop: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: openSettings) { LevelBadge() }
            Button(action: openShop) { Counter(icon: "ui_energy", value: "\(store.state.energy)", sub: energyTimer, plus: true) }
            Button { store.show("🪙 \(store.state.coins)") } label: { Counter(icon: "ui_coin", value: Fmt.compact(store.state.coins)) }
            Button(action: openShop) { Counter(icon: "ui_gem", value: Fmt.compact(store.state.gems), plus: true) }
            VillageButton(stars: store.state.stars, ready: store.canBuildSomething, action: openVillage)
        }
        .padding(.horizontal, 8)
    }

    private var energyTimer: String? {
        guard let t = store.nextEnergyIn else { return nil }
        let s = Int(t.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Уровень игрока с кольцом опыта.
private struct LevelBadge: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        let progress = Double(store.state.xp) / Double(max(1, store.game.xpToNextLevel))
        ZStack {
            Circle().fill(Theme.card)
            Circle().stroke(Theme.wood.opacity(0.2), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
            PixelText("\(store.state.level)", size: 16)
                .foregroundColor(Theme.text)
        }
        .frame(width: 38, height: 38)
    }
}

/// Звезды и вход в деревню. Когда хватает звезд на постройку, кнопка покачивается.
private struct VillageButton: View {
    let stars: Int
    let ready: Bool
    let action: () -> Void
    @State private var wiggle = false

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 4) {
                PixelIcon(key: "ui_house", size: 20)
                PixelText("⭐️\(Fmt.compact(stars))", size: 15)
            }
            .foregroundColor(ready ? .white : Theme.text)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(PixelSlice(key: ready ? "ui_btn_green" : "ui_paper", inset: ready ? 5 : 4, scale: 2))
            .rotationEffect(.degrees(ready && wiggle ? 3 : 0))
            .scaleEffect(ready && wiggle ? 1.05 : 1)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { wiggle = true }
        }
    }
}

private struct Counter: View {
    let icon: String
    let value: String
    var sub: String?
    var plus = false

    var body: some View {
        HStack(spacing: 4) {
            PixelIcon(key: icon, size: 22)
            VStack(alignment: .leading, spacing: 0) {
                PixelText(value, size: 17)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let sub {
                    Text(sub).font(Pixel.body(10)).opacity(0.7)
                }
            }
        }
        .foregroundColor(Theme.text)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(PixelSlice(key: "ui_paper", inset: 4))
        .overlay(alignment: .topTrailing) {
            if plus {
                Image(systemName: "plus.circle.fill")
                    .font(Pixel.font(13))
                    .foregroundColor(Theme.accent)
                    .background(Circle().fill(.white))
                    .offset(x: 4, y: -4)
            }
        }
    }
}

private struct OrdersStrip: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                // пока заказы помещаются, они стоят по центру; если нет - листаются
                HStack(alignment: .top, spacing: 8) {
                    if let visit = store.state.merchant {
                        MerchantCard(visit: visit)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                    ForEach(store.state.orders) { order in
                        OrderCard(order: order)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 8)
                .frame(minWidth: geo.size.width)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.state.orders.map(\.id))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.state.merchant)
            }
        }
        .frame(height: 118)
    }
}

private struct OrderCard: View {
    @EnvironmentObject private var store: GameStore
    let order: Order

    var body: some View {
        let ready = store.canDeliver(order)
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                ResidentIcon(id: Residents.requester(of: order), size: 30)
                    .padding(.trailing, 2)
                ForEach(Array(order.needs.enumerated()), id: \.offset) { _, item in
                    ZStack(alignment: .bottomTrailing) {
                        ItemIcon(item: item, size: 30)
                        TierBadge(tier: item.tier)
                    }
                    .frame(width: 34, height: 34)
                }
            }
            PixelText("🪙\(order.coins) ⭐️\(order.stars)", size: 15)
                .lineLimit(1)
                .fixedSize()
                .foregroundColor(Theme.text)
            Button {
                store.deliver(order)
            } label: {
                Text(L10n.t("orders.give"))
            }
            .buttonStyle(PixelButtonStyle(kind: ready ? .green : .wood, size: 12, compact: true))
            .opacity(ready ? 1 : 0.55)
            .disabled(!ready)
        }
        .padding(8)
        .background(PixelSlice(key: ready ? "ui_paper_green" : "ui_paper", inset: 4))
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.light()
            store.highlight(order)
        }
    }
}

/// Особый заказ странствующего торговца: три предмета, таймер, награда кристаллами.
private struct MerchantCard: View {
    @EnvironmentObject private var store: GameStore
    let visit: MerchantVisit

    var body: some View {
        let ready = store.canDeliverMerchant
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                PixelIcon(key: "ui_wagon", size: 28)
                    .padding(.trailing, 2)
                ForEach(Array(visit.needs.enumerated()), id: \.offset) { _, item in
                    ZStack(alignment: .bottomTrailing) {
                        ItemIcon(item: item, size: 28)
                        TierBadge(tier: item.tier)
                    }
                    .frame(width: 31, height: 34)
                }
            }
            HStack(spacing: 4) {
                PixelText(reward, size: 14).lineLimit(1).fixedSize()
                Text(timeLeft).font(Pixel.digits(11)).opacity(0.7).lineLimit(1).fixedSize()
            }
            .foregroundColor(Theme.text)
            Button {
                store.deliverMerchant()
            } label: {
                Text(L10n.t("orders.give"))
            }
            .buttonStyle(PixelButtonStyle(kind: ready ? .green : .wood, size: 12, compact: true))
            .opacity(ready ? 1 : 0.55)
            .disabled(!ready)
        }
        .padding(8)
        .background(PixelSlice(key: ready ? "ui_paper_green" : "ui_paper_lilac", inset: 4))
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.light()
            store.highlight(Order(id: -1, needs: visit.needs, coins: 0, stars: 0, xp: 0))
            store.show(L10n.t("merchant.about"))
        }
    }

    private var reward: String {
        "💎\(visit.gems)" + (visit.decor != nil ? " 🪴" : visit.energy > 0 ? " ⚡️\(visit.energy)" : "")
    }

    private var timeLeft: String {
        let s = max(0, Int(visit.leavesAt.timeIntervalSince(store.game.now())))
        return String(format: "%d:%02d", s / 3600, (s % 3600) / 60)
    }
}

/// Действия с выбранным предметом: продать или убрать в корзину.
private struct SelectedBar: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        HStack(spacing: 8) {
            if let index = store.selected, let item = store.game.piece(at: index)?.item {
                ItemIcon(item: item, size: 30)
                Text(item.tier == store.catalog.maxTier(of: item.chain) ? L10n.t("selected.max") : "\(item.tier + 1)/\(store.catalog.maxTier(of: item.chain) + 1)")
                    .font(Pixel.font(13))
                    .foregroundColor(Theme.text)
                Spacer()
                ActionButton(title: String(format: L10n.t("selected.sell"), store.game.sellPrice(item))) { store.sellSelected() }
                ActionButton(title: L10n.t("selected.store")) { store.storeSelected() }
            } else {
                JarButton()
                BasketButton()
                PostcardButton()
                JournalButton()
                if store.game.boostUnlocked { BoostToggle() }
                if store.state.level < 2 {
                    Text(L10n.t("hint.start"))
                        .font(Pixel.font(12))
                        .foregroundColor(Theme.text.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if store.canUndo {
                    ActionButton(title: "↩︎ " + L10n.t("selected.undo")) { store.undoSale() }
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.canUndo)
    }
}

/// Ускорение генераторов x2: тратит вдвое больше энергии на предмет ступенью выше.
private struct BoostToggle: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        let on = store.state.boostOn
        Button { store.toggleBoost() } label: {
            HStack(spacing: 2) {
                PixelText("⚡️", size: 14)
                Text("x2").font(Pixel.font(14))
            }
            .foregroundColor(on ? .white : Theme.text)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(PixelSlice(key: on ? "ui_paper_gold" : "ui_paper", inset: 4, scale: 2))
            .shadow(color: on ? .orange.opacity(0.5) : .clear, radius: 6)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: on)
    }
}

/// Открытка: сколько кусочков собрано, по тапу - сама открытка.
private struct PostcardButton: View {
    @EnvironmentObject private var store: GameStore
    @State private var open = false

    var body: some View {
        Button {
            Haptics.light()
            open = true
        } label: {
            HStack(spacing: 3) {
                PixelIcon(key: "ui_frame", size: 20)
                Text("\(store.state.postcardPieces)/\(store.balance.postcardPieces)")
                    .font(Pixel.font(13))
            }
            .foregroundColor(Theme.text)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(PixelSlice(key: "ui_paper", inset: 4, scale: 2))
        }
        .sheet(isPresented: $open) { PostcardSheet() }
    }
}

private struct ActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PixelText(title, size: 13)
        }
        .buttonStyle(PixelButtonStyle(kind: .wood, size: 13, compact: true))
    }
}

/// Корзина одной кнопкой: сколько занято, по тапу окно с полками.
private struct BasketButton: View {
    @EnvironmentObject private var store: GameStore
    @State private var open = false

    var body: some View {
        let used = store.state.basket.count
        Button {
            Haptics.light()
            open = true
        } label: {
            HStack(spacing: 3) {
                PixelIcon(key: "ui_basket", size: 22)
                Text("\(used)/\(store.state.basketSize)").font(Pixel.font(13))
            }
            .foregroundColor(Theme.text)
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(PixelSlice(key: used > 0 ? "ui_paper_gold" : "ui_paper", inset: 4, scale: 2))
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: used)
        .sheet(isPresented: $open) { BasketSheet() }
    }
}

/// Окно корзины: полки с предметами, тап возвращает предмет на поле.
struct BasketSheet: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        PixelSheet(L10n.t("basket.title")) {
            ScrollView {
                VStack(spacing: 14) {
                    Text(L10n.t("basket.about"))
                        .font(Pixel.font(14))
                        .multilineTextAlignment(.center)
                        .opacity(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                        ForEach(0..<store.state.basketSize, id: \.self) { i in
                            let item = i < store.state.basket.count ? store.state.basket[i] : nil
                            Button {
                                store.retrieve(i)
                            } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    if let item {
                                        ItemIcon(item: item, size: 40)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        TierBadge(tier: item.tier).padding(4)
                                    }
                                }
                                .frame(height: 66)
                                .frame(maxWidth: .infinity)
                                .background(PixelSlice(key: item == nil ? "ui_paper" : "ui_paper_gold", inset: 4))
                            }
                            .disabled(item == nil)
                            .transition(.scale)
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: store.state.basket)
                    if let price = store.game.basketSlotPrice {
                        Button {
                            store.buyBasketSlot()
                        } label: {
                            PixelText(String(format: L10n.t("basket.more"), price), size: 16)
                        }
                        .buttonStyle(PixelButtonStyle(kind: .green, size: 16))
                    }
                }
                .padding(16)
            }
        }
    }
}

/// Иконка предмета: спрайт пака без сглаживания или эмодзи, пока спрайтов нет.
struct ItemIcon: View {
    @EnvironmentObject private var store: GameStore
    let item: Item
    let size: CGFloat

    var body: some View {
        if let image = Sprites.image(store.catalog.key(for: item)) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Text(store.catalog.emoji(for: item)).font(.system(size: size * 0.85))
        }
    }
}

/// Номер ступени предмета: четкие пиксельные цифры на светлой плашке.
struct TierBadge: View {
    let tier: Int

    var body: some View {
        Text("\(tier + 1)")
            .font(Pixel.digits(13))
            .foregroundColor(Theme.text)
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
            .background(Color(red: 1, green: 0.96, blue: 0.86).opacity(0.9))
    }
}
