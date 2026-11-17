import SwiftUI
import UIKit

/// Пиксельный интерфейс: шрифт Tiny5, иконки валют вместо эмодзи, деревянные рамки и кнопки
/// (картинки из tools/ui_kit.py, лежат в Resources/UI). Всё увеличивается без сглаживания.
@MainActor
enum Pixel {
    /// Пиксельный шрифт для заголовков, чисел и кнопок. Иероглифы iOS дорисует системным шрифтом.
    static func font(_ size: CGFloat) -> Font {
        .custom("Tiny5", size: size * 1.12)
    }

    /// Эмодзи валют в строках заменяются пиксельными иконками.
    static let icons: [String: String] = ["💎": "ui_gem", "🪙": "ui_coin", "⚡️": "ui_energy", "⚡": "ui_energy", "⭐️": "ui_star", "⭐": "ui_star"]

    private static var scaled: [String: UIImage] = [:]

    /// Иконка нужного размера в точках, увеличенная «по пикселям».
    static func icon(_ key: String, size: CGFloat) -> UIImage? {
        let id = "\(key)@\(Int(size))"
        if let cached = scaled[id] { return cached }
        guard let src = Sprites.image(key) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        let img = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { ctx in
            ctx.cgContext.interpolationQuality = .none
            src.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
        }
        scaled[id] = img
        return img
    }

    /// Текст с иконками: "💎 120  ⚡️ 30" -> пиксельный шрифт и пиксельные кристалл и молния.
    static func text(_ string: String, size: CGFloat) -> Text {
        var result = Text("")
        var buffer = ""
        func flush() {
            if !buffer.isEmpty { result = result + Text(buffer); buffer = "" }
        }
        for ch in string {
            let s = String(ch)
            if let key = icons[s] ?? icons[s.replacingOccurrences(of: "\u{FE0F}", with: "")],
               let image = icon(key, size: (size * 1.3).rounded()) {
                flush()
                result = result + Text(Image(uiImage: image)).baselineOffset(-size * 0.22)
            } else {
                buffer.append(ch)
            }
        }
        flush()
        return result.font(font(size))
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
        } else {
            RoundedRectangle(cornerRadius: 12).fill(Theme.card)
        }
    }

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
