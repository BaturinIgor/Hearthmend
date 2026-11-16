import SwiftUI
import SpriteKit
import HearthCore

struct ContentView: View {
    @EnvironmentObject private var store: GameStore
    @State private var scene = BoardScene(size: CGSize(width: 350, height: 450))

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 8) {
                TopBar()
                OrdersStrip()
                SpriteView(scene: scene, options: [.allowsTransparency])
                    .aspectRatio(CGFloat(store.balance.cols) / CGFloat(store.balance.rows), contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 8)
                SelectedBar()
                BasketBar()
            }
            .padding(.top, 4)
            if let toast = store.toast {
                Text(toast)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
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
            scene.render()
        }
        .onChange(of: store.selected) { _ in scene.render() }
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

    var body: some View {
        HStack(spacing: 8) {
            Counter(icon: "⚡️", value: "\(store.state.energy)", sub: energyTimer)
            Counter(icon: "🪙", value: "\(store.state.coins)")
            Counter(icon: "💎", value: "\(store.state.gems)")
            Counter(icon: "⭐️", value: "\(store.state.stars)")
        }
        .padding(.horizontal, 8)
    }

    private var energyTimer: String? {
        guard let t = store.nextEnergyIn else { return nil }
        let s = Int(t.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct Counter: View {
    let icon: String
    let value: String
    var sub: String?

    var body: some View {
        HStack(spacing: 4) {
            Text(icon)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(size: 16, weight: .heavy, design: .rounded))
                if let sub {
                    Text(sub).font(.system(size: 10, weight: .semibold, design: .rounded)).opacity(0.7)
                }
            }
        }
        .foregroundColor(Theme.text)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.wood.opacity(0.5), lineWidth: 1.5))
    }
}

private struct OrdersStrip: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.state.orders) { order in
                    OrderCard(order: order)
                }
            }
            .padding(.horizontal, 8)
        }
    }
}

private struct OrderCard: View {
    @EnvironmentObject private var store: GameStore
    let order: Order

    var body: some View {
        let ready = store.canDeliver(order)
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(Array(order.needs.enumerated()), id: \.offset) { _, item in
                    ZStack(alignment: .bottomTrailing) {
                        Text(store.catalog.emoji(for: item)).font(.system(size: 26))
                        Text("\(item.tier + 1)")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundColor(Theme.text)
                    }
                    .frame(width: 34, height: 34)
                }
            }
            Text("🪙\(order.coins) ⭐️\(order.stars)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.text)
            Button {
                store.deliver(order)
            } label: {
                Text(L10n.t("orders.give"))
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(ready ? Theme.accent : Color.gray.opacity(0.5)))
            }
            .disabled(!ready)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ready ? Theme.accent : Theme.wood.opacity(0.4), lineWidth: ready ? 2.5 : 1.5))
    }
}

/// Действия с выбранным предметом: продать или убрать в корзину.
private struct SelectedBar: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        HStack(spacing: 8) {
            if let index = store.selected, let item = store.game.piece(at: index)?.item {
                Text(store.catalog.emoji(for: item)).font(.system(size: 26))
                Text(item.tier == store.catalog.maxTier(of: item.chain) ? L10n.t("selected.max") : "\(item.tier + 1)/\(store.catalog.maxTier(of: item.chain) + 1)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.text)
                Spacer()
                ActionButton(title: String(format: L10n.t("selected.sell"), store.game.sellPrice(item))) { store.sellSelected() }
                ActionButton(title: L10n.t("selected.store")) { store.storeSelected() }
            } else {
                Text(L10n.t("hint.start"))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.text.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
    }
}

private struct ActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.wood))
        }
    }
}

private struct BasketBar: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        HStack(spacing: 6) {
            Text("🧺").font(.system(size: 22))
            ForEach(0..<store.state.basketSize, id: \.self) { i in
                let item = i < store.state.basket.count ? store.state.basket[i] : nil
                Button {
                    store.retrieve(i)
                } label: {
                    Text(item.map { store.catalog.emoji(for: $0) } ?? "")
                        .font(.system(size: 22))
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.wood.opacity(0.4), lineWidth: 1))
                }
                .disabled(item == nil)
            }
        }
        .padding(.bottom, 8)
    }
}
