import Foundation

/// Цепочка слияния: предметы снизу вверх и генератор, из которого они падают.
/// Описание лежит в Resources/chains.json, чтобы новые цепочки добавлялись без правки кода.
public struct ChainDef: Codable, Equatable {
    public let id: String
    /// Ключи предметов по ступеням. По ним потом подбираются спрайты пака.
    public let items: [String]
    /// Временная графика, пока нет спрайтов.
    public let emoji: [String]
    public let generator: String
    public let generatorEmoji: String
    /// Сколько ступеней у генератора (два одинаковых сливаются в следующий).
    public let generatorTiers: Int
    /// Выше этой ступени заказы и торговец не просят: верхние ступени для альбома, достижений и гордости.
    public let orderMaxTier: Int?

    public var maxTier: Int { items.count - 1 }
    public var orderTop: Int { min(orderMaxTier ?? maxTier, maxTier) }
}

public struct Catalog: Codable, Equatable {
    public let chains: [ChainDef]

    public init(chains: [ChainDef]) {
        self.chains = chains
    }

    public func chain(_ id: String) -> ChainDef? {
        chains.first { $0.id == id }
    }

    public func maxTier(of chain: String) -> Int {
        self.chain(chain)?.maxTier ?? 0
    }

    public func orderTop(of chain: String) -> Int {
        self.chain(chain)?.orderTop ?? 0
    }

    /// Следующая ступень предмета или nil, если ступень последняя.
    public func next(_ item: Item) -> Item? {
        guard let def = chain(item.chain), item.tier < def.maxTier else { return nil }
        return Item(chain: item.chain, tier: item.tier + 1)
    }

    public func emoji(for item: Item) -> String {
        guard let def = chain(item.chain), def.emoji.indices.contains(item.tier) else { return "?" }
        return def.emoji[item.tier]
    }

    public func key(for item: Item) -> String {
        guard let def = chain(item.chain), def.items.indices.contains(item.tier) else { return "unknown" }
        return def.items[item.tier]
    }

    public static func load(from data: Data) throws -> Catalog {
        try JSONDecoder().decode(Catalog.self, from: data)
    }

    /// Каталог из ресурсов пакета.
    public static let bundled: Catalog = {
        guard let url = Bundle.module.url(forResource: "chains", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? load(from: data) else {
            fatalError("chains.json не найден или поврежден")
        }
        return catalog
    }()
}
