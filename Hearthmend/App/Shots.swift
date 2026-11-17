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
    static var isFar: Bool { name == "qa_far" || name == "qa_story" }
    static var isActive: Bool { name != nil }
    /// Постройка в центре кадра на скриншотах деревни: самое живое место.
    static var focus: String? {
        switch name {
        case "village": return "square_stalls"
        case "north": return "orchard_market"
        case "qa_far": return "mine_crystals"
        default: return nil
        }
    }
    static var hasCaption: Bool { name != nil && name != "shop" && !isQA }
    /// Кадры для проверки интерфейса (не для App Store): -shot qa_<экран>.
    static var isQA: Bool { name?.hasPrefix("qa_") == true }
}

/// Экраны для проверки глазами: окна и состояния, которых нет на скриншотах App Store.
struct QAScreen: View {
    @EnvironmentObject private var store: GameStore
    let name: String

    var body: some View {
        switch name {
        case "qa_quests": JournalSheet(tab: .quests)
        case "qa_album": JournalSheet(tab: .album)
        case "qa_friends": JournalSheet(tab: .friends)
        case "qa_achievements": JournalSheet(tab: .achievements)
        case "qa_settings": SettingsView()
        case "qa_daily":
            ZStack { ContentView(); DailyRewardView {} }
        case "qa_basket": BasketSheet()
        case "qa_jar": JarSheet()
        case "qa_story":
            ZStack { ContentView(); StoryView(scene: "mine.intro") {} }
        default:
            ContentView()
                .onAppear {
                    switch name {
                    case "qa_selected": store.selected = 26
                    case "qa_celebrate":
                        store.celebration = Celebration(icon: "npc:mila",
                                                        title: String(format: L10n.t("resident.arrived"), L10n.t("resident.mila")),
                                                        subtitle: String(format: L10n.t("resident.chain"), L10n.t("chain.orchard")))
                    case "qa_toast": store.show(String(format: L10n.t("toast.order_done"), 24, 1))
                    default: break
                    }
                }
        }
    }
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
                            .offset(x: width / 2 - map.size.width, y: full / 2 - 112 * 16 * 2)
                            .frame(width: width, height: full, alignment: .topLeading)
                            .clipped()
                    } else {
                        Color(red: 0.36, green: 0.55, blue: 0.29)
                    }
                }
                LinearGradient(colors: [Color.black.opacity(0.3), Color.black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                caption
                    .frame(maxWidth: width - 40, maxHeight: top - 50)
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
        .padding(.horizontal, 30)
        .padding(.vertical, 22)
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
