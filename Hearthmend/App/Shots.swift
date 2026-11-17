import SwiftUI
import HearthCore

/// Скриншоты для App Store. Запуск: -demo -shot <board|village|north|event|postcard|shop>.
/// С подписью (все, кроме shop) экран игры уменьшен и стоит под заголовком,
/// подпись берется из строк shot.<имя>.title / .sub на языке системы.
enum Shot {
    static let name: String? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-shot"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()

    static var isLate: Bool { name == "north" }
    /// Постройка в центре кадра на скриншотах деревни: самое живое место.
    static var focus: String? {
        switch name {
        case "village": return "square_stalls"
        case "north": return "orchard_market"
        default: return nil
        }
    }
    static var hasCaption: Bool { name != nil && name != "shop" }
}

struct ShotFrame: View {
    @EnvironmentObject private var store: GameStore
    let name: String

    var body: some View {
        GeometryReader { geo in
            let full = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            let width = geo.size.width
            let top = full * 0.225
            let scale = (full - top - 18) / full
            ZStack(alignment: .top) {
                // фон: сама деревня, приглушенная, чтобы подпись и экран читались
                Group {
                    if let map = Sprites.image("map_bg") {
                        // кусок карты вокруг площади, 2 точки на пиксель
                        Image(uiImage: map).resizable().interpolation(.none)
                            .frame(width: map.size.width * 2, height: map.size.height * 2)
                            .offset(x: width / 2 - map.size.width, y: full / 2 - 72 * 16 * 2)
                            .frame(width: width, height: full, alignment: .topLeading)
                            .clipped()
                    } else {
                        Color(red: 0.36, green: 0.55, blue: 0.29)
                    }
                }
                LinearGradient(colors: [Color.black.opacity(0.15), Color.black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                caption
                    .frame(width: width - 44, height: top - 58)
                    .padding(.top, 54)
                screen
                    .frame(width: width, height: full)
                    .clipShape(RoundedRectangle(cornerRadius: 46, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 46, style: .continuous).stroke(Color(red: 0.2, green: 0.14, blue: 0.08), lineWidth: 9))
                    .scaleEffect(scale, anchor: .top)
                    .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
                    .offset(y: top)
                    .allowsHitTesting(false)
            }
            .frame(width: width, height: full)
        }
        .ignoresSafeArea()
        .statusBar(hidden: true)
    }

    private var caption: some View {
        VStack(spacing: 8) {
            Text(L10n.t("shot.\(name).title"))
                .font(Pixel.font(33))
                .foregroundColor(Theme.text)
            Text(L10n.t("shot.\(name).sub"))
                .font(Pixel.font(17))
                .foregroundColor(Theme.text.opacity(0.8))
        }
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(PixelSlice(key: "ui_panel", inset: 6, scale: 4))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
    }

    @ViewBuilder private var screen: some View {
        switch name {
        case "event":
            if let def = store.game.activeEvent { EventSheet(def: def) } else { ContentView() }
        case "postcard":
            PostcardSheet()
        default:
            ContentView()
        }
    }
}
