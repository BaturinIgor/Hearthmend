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
                LinearGradient(colors: [Color(red: 0.42, green: 0.66, blue: 0.36), Color(red: 0.98, green: 0.88, blue: 0.62)],
                               startPoint: .top, endPoint: .bottom)
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
        VStack(spacing: 6) {
            Text(L10n.t("shot.\(name).title"))
                .font(Pixel.font(34))
                .foregroundColor(.white)
                .shadow(color: Color(red: 0.16, green: 0.3, blue: 0.12).opacity(0.6), radius: 0, x: 0, y: 3)
            Text(L10n.t("shot.\(name).sub"))
                .font(Pixel.font(19))
                .foregroundColor(Color.white.opacity(0.95))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.6)
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
