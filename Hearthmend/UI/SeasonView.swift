import SwiftUI
import HearthCore

/// Краски и частицы времени года над картой деревни. Частицы рисуются одним Canvas,
/// без отдельных view на каждую: на старых iPhone это держит 60 кадров.
extension Season {
    /// Цвет, на который умножается карта: зимой холоднее, осенью теплее.
    var tint: Color {
        switch self {
        case .spring: return Color(red: 1.0, green: 0.98, blue: 1.0)
        case .summer: return Color(red: 1.0, green: 1.0, blue: 0.94)
        case .autumn: return Color(red: 1.0, green: 0.88, blue: 0.72)
        case .winter: return Color(red: 0.86, green: 0.92, blue: 1.0)
        }
    }

    var saturation: Double {
        switch self {
        case .winter: return 0.7
        case .autumn: return 1.1
        default: return 1.0
        }
    }

    /// Белая дымка: зимой карта будто припорошена.
    var frost: Double { self == .winter ? 0.16 : 0 }
}

struct SeasonParticles: View {
    let season: Season
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Flake {
        let x: Double, speed: Double, sway: Double, phase: Double, size: Double, spin: Double
    }

    private static let flakes: [Flake] = {
        var rng = SystemRandomNumberGenerator()
        return (0..<34).map { _ in
            Flake(x: .random(in: 0...1, using: &rng), speed: .random(in: 0.035...0.08, using: &rng),
                  sway: .random(in: 8...26, using: &rng), phase: .random(in: 0...(2 * .pi), using: &rng),
                  size: .random(in: 0.7...1.3, using: &rng), spin: .random(in: -1.5...1.5, using: &rng))
        }
    }()

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            TimelineView(.animation) { timeline in
                Canvas { ctx, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    for (i, f) in Self.flakes.enumerated() {
                        draw(f, index: i, t: t, in: size, ctx: &ctx)
                    }
                }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
    }

    private func draw(_ f: Flake, index: Int, t: Double, in size: CGSize, ctx: inout GraphicsContext) {
        switch season {
        case .summer:
            // светлячки: висят на месте, плавают по кругу и мерцают
            let x = f.x * size.width + sin(t * 0.4 + f.phase) * f.sway * 1.5
            let y = (Double(index) / Double(Self.flakes.count)) * size.height + cos(t * 0.3 + f.phase) * f.sway
            let glow = 0.35 + 0.65 * max(0, sin(t * 1.3 + f.phase * 3))
            let r = 2.6 * f.size
            ctx.opacity = glow
            ctx.fill(Path(ellipseIn: CGRect(x: x - r * 3, y: y - r * 3, width: r * 6, height: r * 6)),
                     with: .color(Color.yellow.opacity(0.18)))
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                     with: .color(Color(red: 1, green: 0.97, blue: 0.6)))
            ctx.opacity = 1
        default:
            // падающие частицы: путь сверху вниз по кругу, с покачиванием
            let travel = size.height + 40
            let y = (t * f.speed * travel + f.phase / (2 * .pi) * travel).truncatingRemainder(dividingBy: travel) - 20
            let x = f.x * size.width + sin(t * 0.9 + f.phase) * f.sway
            var c = ctx
            c.translateBy(x: x, y: y)
            c.rotate(by: .radians(t * f.spin + f.phase))
            switch season {
            case .winter:
                let r = 2.2 * f.size
                c.opacity = 0.85
                c.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: .color(.white))
            case .autumn:
                let colors = [Color(red: 0.9, green: 0.45, blue: 0.15), Color(red: 0.85, green: 0.65, blue: 0.2), Color(red: 0.7, green: 0.3, blue: 0.15)]
                let w = 7 * f.size, h = 4 * f.size
                c.fill(Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h)), with: .color(colors[index % colors.count]))
            default:
                let w = 5.5 * f.size, h = 3.5 * f.size
                c.opacity = 0.9
                c.fill(Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h)),
                       with: .color(index.isMultiple(of: 3) ? .white : Color(red: 1, green: 0.75, blue: 0.85)))
            }
        }
    }
}

/// Значок сезона в шапке деревни.
struct SeasonChip: View {
    let season: Season

    var body: some View {
        HStack(spacing: 3) {
            Text(season.icon)
            Text(L10n.t("season.\(season.rawValue)"))
        }
        .font(Pixel.font(13))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.6)))
    }
}
