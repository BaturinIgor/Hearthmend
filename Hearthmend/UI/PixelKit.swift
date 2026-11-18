import SwiftUI
import UIKit

/// Пиксельный интерфейс: один пиксельный шрифт Hearth Pixel на все тексты и цифры (жирная версия
/// Galmuri11 с латиницей, кириллицей, каной, хангылем и иероглифами), иконки вместо эмодзи,
/// деревянные рамки и кнопки (картинки из tools/ui_kit.py, лежат в Resources/UI).
@MainActor
enum Pixel {
    static let fontName = "HearthPixel-Regular"

    /// Единственный шрифт интерфейса. Размер чуть меньше номинального: у шрифта крупные строчные.
    static func font(_ size: CGFloat) -> Font {
        .custom(fontName, size: (size * 0.95).rounded())
    }

    /// Описания и подсказки: тот же пиксельный шрифт.
    static func body(_ size: CGFloat) -> Font { font(size + 1) }

    /// Цифры: тот же шрифт, у него четкие 8, 6, 9 и 0.
    static func digits(_ size: CGFloat) -> Font { font(size + 1) }

    /// Сторона пиксельной картинки в точках, кратная пикселю исходника: все пиксели одинаковые.
    static func crisp(_ size: CGFloat, source: CGFloat) -> CGFloat {
        let scale = UIScreen.main.scale
        let k = max(1, (size * scale / max(1, source)).rounded())
        return k * source / scale
    }

    /// Эмодзи валют в строках заменяются пиксельными иконками.
    static let icons: [String: String] = ["💎": "ui_gem", "🪙": "ui_coin", "⚡️": "ui_energy", "⚡": "ui_energy", "⭐️": "ui_star", "⭐": "ui_star",
                                             "🪴": "ui_plant", "👑": "ui_crown", "🏡": "ui_house", "🎟": "ui_ticket", "🎀": "ui_ribbon", "🖼": "ui_frame", "🧺": "ui_basket", "🎁": "ui_gift", "🫙": "ui_jar", "🏵": "ui_rosette", "❓": "ui_question", "🔒": "ui_lock", "↩": "ui_undo", "👝": "ui_pouch", "🧰": "ui_chest", "💰": "ui_bag", "🏰": "ui_vault", "🛠": "ui_hammer", "🐷": "ui_piggy", "✓": "ui_check", "🎉": "ui_party", "🎊": "ui_confetti", "🌸": "ui_spring", "☀": "ui_summer", "🍂": "ui_autumn", "❄": "ui_winter", "★": "ui_star", "🧱": "debris", "🛒": "ui_wagon", "🏆": "ui_trophy", "💛": "ui_heart", "❤": "ui_heart", "⛏": "ui_pickaxe", "🏮": "ui_lantern", "🚃": "ui_minecart", "🐚": "ui_shell", "🌊": "ui_wave", "🌱": "ui_seeds", "💧": "ui_can"]

    /// Ключ картинки для эмодзи (без вариантов начертания), если она у нас нарисована.
    static func key(for emoji: String) -> String? {
        let bare = emoji.replacingOccurrences(of: "\u{FE0F}", with: "").replacingOccurrences(of: "\u{FE0E}", with: "")
        return icons[emoji] ?? icons[bare]
    }

    private static var scaled: [String: UIImage] = [:]

    /// Иконка нужного размера в точках, увеличенная «по пикселям».
    static func icon(_ key: String, size: CGFloat) -> UIImage? {
        let id = "\(key)@\(Int(size))"
        if let cached = scaled[id] { return cached }
        guard let src = Sprites.image(key) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        // кратное увеличение: иначе пиксели выходят разной ширины и картинка «кривая»
        let side = max(src.size.width, src.size.height)
        let k = crisp(size, source: side) / side
        let w = src.size.width * k, h = src.size.height * k
        let img = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { ctx in
            ctx.cgContext.interpolationQuality = .none
            src.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        scaled[id] = img
        return img
    }

    /// Текст с иконками: "💎 120  ⚡️ 30" -> пиксельные кристалл и молния, числа крупным пиксельным шрифтом.
    static func text(_ string: String, size: CGFloat) -> Text {
        var result = Text("")
        var buffer = ""
        var number = ""
        func flushText() {
            if !buffer.isEmpty { result = result + Text(buffer).font(font(size)); buffer = "" }
        }
        func flushNumber() {
            if !number.isEmpty {
                result = result + Text(number).font(digits(size))
                number = ""
            }
        }
        for ch in string {
            let s = String(ch)
            if let key = key(for: s),
               let image = icon(key, size: (size * 1.3).rounded()) {
                flushText(); flushNumber()
                result = result + Text(Image(uiImage: image)).baselineOffset(-size * 0.22)
            } else if ch.isASCII, ch.isNumber || (!number.isEmpty && (ch == "/" || ch == ":")) || ((ch == "+" || ch == "×") && number.isEmpty) {
                flushText()
                number.append(ch)
            } else if ch == "\u{FE0F}" || ch == "\u{FE0E}" {
                continue
            } else {
                flushNumber()
                buffer.append(ch)
            }
        }
        flushText(); flushNumber()
        return result
    }
}

/// Строка с иконками валют вместо эмодзи и пиксельным шрифтом.
struct PixelText: View {
    let string: String
    var size: CGFloat = 15

    init(_ string: String, size: CGFloat = 15) {
        self.string = string
        self.size = size
    }

    var body: some View { Pixel.text(string, size: size) }
}

/// Иконка валюты или интерфейса.
struct PixelIcon: View {
    let key: String
    var size: CGFloat = 20

    var body: some View {
        if let image = Pixel.icon(key, size: size) {
            Image(uiImage: image)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}

/// Растягиваемая пиксельная картинка (9-slice): углы целые, середина тянется.
@MainActor
struct PixelSlice: View {
    let key: String
    /// Края картинки в пикселях исходника, которые не тянутся.
    let inset: CGFloat
    /// Во сколько раз увеличивать пиксели.
    var scale: CGFloat = 3

    var body: some View {
        if let src = Sprites.image(key), let cg = src.cgImage {
            // увеличиваем исходник целиком, потом режем на 9 частей: пиксели остаются квадратными
            let big = UIImage(cgImage: Self.upscale(cg, key: key, by: Int(scale * UIScreen.main.scale)) ?? cg,
                              scale: UIScreen.main.scale, orientation: .up)
            let edge = inset * scale
            Image(uiImage: big)
                .resizable(capInsets: EdgeInsets(top: edge, leading: edge, bottom: edge, trailing: edge), resizingMode: .stretch)
                .interpolation(.none)
                // панели и кнопки чуть приподняты над фоном: жесткая пиксельная тень снизу
                .shadow(color: .black.opacity(Self.flat(key) ? 0 : 0.16), radius: 0, x: 0, y: scale * 0.7)
        } else {
            RoundedRectangle(cornerRadius: 12).fill(Theme.card)
        }
    }

    /// Желоба полосок и клетки лежат в панели, им тень не нужна.
    private static func flat(_ key: String) -> Bool { key.hasPrefix("ui_bar") || key.hasPrefix("ui_cell") }

    private static var cache: [String: CGImage] = [:]

    static func upscale(_ cg: CGImage, key name: String, by k: Int) -> CGImage? {
        let key = "\(name)x\(k)"
        if let c = cache[key] { return c }
        let w = cg.width * k, h = cg.height * k
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let out = ctx.makeImage()
        cache[key] = out
        return out
    }
}

extension View {
    /// Деревянная рамка с пергаментом (карточки, панели).
    func woodPanel(padding: CGFloat = 18) -> some View {
        self.padding(padding).background(PixelSlice(key: "ui_panel", inset: 6))
    }

    /// Пергамент с тонкой рамкой (мелкие плашки, счетчики).
    func paperPanel(padding: CGFloat = 8) -> some View {
        self.padding(padding).background(PixelSlice(key: "ui_paper", inset: 4))
    }
}

/// Кнопка в пиксельном стиле: зеленая, деревянная или розовая, с нажатием вниз.
struct PixelButtonStyle: ButtonStyle {
    enum Kind: String { case green, wood, pink }
    var kind: Kind = .green
    var size: CGFloat = 16
    /// Маленькая кнопка (в карточках заказов).
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Pixel.font(size))
            .foregroundColor(kind == .wood ? Color(red: 1, green: 0.95, blue: 0.85) : .white)
            .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 1.5)
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.top, compact ? 4 : 8)
            .padding(.bottom, compact ? 7 : 12)
            .background(PixelSlice(key: "ui_btn_\(kind.rawValue)", inset: 5, scale: compact ? 2 : 3))
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// Пиксельная картинка плиткой (фон окон).
@MainActor
struct PixelTile: View {
    let key: String
    var scale: CGFloat = 3

    var body: some View {
        if let src = Sprites.image(key), let cg = src.cgImage,
           let big = PixelSlice.upscale(cg, key: key, by: Int(scale * UIScreen.main.scale)) {
            Image(uiImage: UIImage(cgImage: big, scale: UIScreen.main.scale, orientation: .up))
                .resizable(resizingMode: .tile)
        } else {
            Theme.background
        }
    }
}

/// Фон экранов: пиксельный луг из пака, сверху и снизу светлая дымка, чтобы шапка и кнопки читались.
struct Backdrop: View {
    var body: some View {
        ZStack {
            PixelTile(key: "bg_meadow", scale: 2)
            Butterflies()
            LinearGradient(colors: [Theme.background.opacity(0.8), Theme.background.opacity(0.0)],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.2))
            LinearGradient(colors: [Theme.background.opacity(0.0), Theme.background.opacity(0.75)],
                           startPoint: UnitPoint(x: 0.5, y: 0.82), endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}

/// Несколько бабочек медленно кружат над лугом. Без анимации, если в системе уменьшено движение.
struct Butterflies: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let flies: [(color: Int, x: Double, y: Double, rx: Double, ry: Double, speed: Double, phase: Double)] = [
        (2, 0.18, 0.22, 0.14, 0.06, 0.11, 0.0),
        (4, 0.78, 0.48, 0.12, 0.09, 0.09, 2.1),
        (0, 0.42, 0.86, 0.2, 0.05, 0.07, 4.2),
    ]

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            GeometryReader { geo in
                TimelineView(.animation(minimumInterval: 1.0 / 20)) { tl in
                    // на скриншотах бабочки замирают в одном и том же месте
                    let t = Shot.isActive ? 7.5 : tl.date.timeIntervalSinceReferenceDate
                    ZStack {
                        ForEach(flies.indices, id: \.self) { i in
                            let f = flies[i]
                            let a = t * f.speed * 2 * .pi / 6 + f.phase
                            let x = (f.x + f.rx * sin(a) + 0.03 * sin(a * 3.1)) * geo.size.width
                            let y = (f.y + f.ry * sin(a * 2) + 0.02 * cos(a * 4.3)) * geo.size.height
                            let frame = Int(t * 6 + f.phase * 3) % 2
                            PixelIcon(key: "fx_bfly_\(f.color)_\(frame)", size: 18)
                                .scaleEffect(x: cos(a) >= 0 ? 1 : -1, y: 1)
                                .position(x: x, y: y)
                        }
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// Полоска прогресса: деревянный желоб и зеленая (или розовая) заливка с бликом.
struct PixelBar: View {
    let value: Double
    var fill = "ui_bar_fill"

    var body: some View {
        GeometryReader { geo in
            let inner = max(0, geo.size.width - 6)
            let v = min(1, max(0, value))
            ZStack(alignment: .leading) {
                PixelSlice(key: "ui_bar_track", inset: 3, scale: 2)
                if v > 0 {
                    PixelSlice(key: fill, inset: 2, scale: 2)
                        .frame(width: max(8, inner * v))
                        .padding(3)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: v)
                }
            }
        }
    }
}

/// Окно-лист в пиксельном стиле: деревянная табличка с заголовком, кнопка закрытия,
/// пергамент фоном. Заменяет системную навигационную панель.
struct PixelSheet<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title)
                    .font(Pixel.font(19))
                    .foregroundColor(Color(red: 1, green: 0.95, blue: 0.85))
                    .shadow(color: .black.opacity(0.4), radius: 0, x: 0, y: 1.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .background(PixelSlice(key: "ui_btn_wood", inset: 5, scale: 3))
                    .padding(.horizontal, 56)
                HStack {
                    Spacer()
                    Button { dismiss() } label: { PixelIcon(key: "ui_close", size: 36) }
                        .accessibilityLabel(L10n.t("common.close"))
                }
                .padding(.trailing, 12)
            }
            .padding(.top, 14)
            .padding(.bottom, 6)
            // содержимое лежит на листе бумаги поверх луга
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PixelSlice(key: "ui_paper", inset: 4, scale: 3).shadow(color: .black.opacity(0.22), radius: 0, x: 0, y: 3))
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
        }
        .foregroundColor(Theme.text)
        .background(Backdrop())
        .overlay(alignment: .bottom) { SheetToast() }
        .overlay { ShortageLayer() }
    }
}

/// Значок по эмодзи: наша пиксельная картинка, если она нарисована (несколько символов подряд,
/// например «💎💎», идут рядом). Неизвестный символ остается текстом.
struct EmojiIcon: View {
    let emoji: String
    var size: CGFloat = 24

    init(_ emoji: String, size: CGFloat = 24) {
        self.emoji = emoji
        self.size = size
    }

    var body: some View {
        HStack(spacing: -size * 0.25) {
            ForEach(Array(emoji.enumerated()), id: \.offset) { _, ch in
                if let key = Pixel.key(for: String(ch)) {
                    PixelIcon(key: key, size: size)
                } else {
                    Text(String(ch)).font(.system(size: size * 0.85))
                }
            }
        }
    }
}

/// Портрет жителя из пака (npc_<id>), запасной вариант - домик.
struct ResidentIcon: View {
    let id: String
    var size: CGFloat = 40

    var body: some View {
        if Sprites.image("npc_\(id)") != nil {
            PixelIcon(key: "npc_\(id)", size: size)
        } else if id == "merchant" {
            PixelIcon(key: "ui_wagon", size: size)
        } else {
            PixelIcon(key: "ui_house", size: size)
        }
    }
}


/// Тост поверх открытого окна: награда за кнопку в окне видна сразу, а не после закрытия.
struct SheetToast: View {
    @EnvironmentObject private var store: GameStore

    var body: some View {
        ZStack {
            if let toast = store.toast {
                PixelText(toast, size: 15)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .padding(.bottom, 30)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: store.toast)
        .allowsHitTesting(false)
    }
}
