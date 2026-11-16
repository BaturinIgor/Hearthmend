import Foundation

/// Время года по календарю (северное полушарие): деревня меняет краски, над ней летят
/// лепестки, светлячки, листья или снег.
public enum Season: String, CaseIterable, Codable {
    case spring, summer, autumn, winter

    public static func of(_ date: Date, calendar: Calendar = .current) -> Season {
        switch calendar.component(.month, from: date) {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .autumn
        default: return .winter
        }
    }

    public var icon: String {
        switch self {
        case .spring: return "🌸"
        case .summer: return "☀️"
        case .autumn: return "🍂"
        case .winter: return "❄️"
        }
    }
}

extension Game {
    public var season: Season { Season.of(now()) }
}
