import Foundation

/// Уровни генераторов (1.1): два одинаковых генератора сливаются в следующий, до 6-го уровня.
/// Чем выше уровень, тем выше ступени предметов, но и тап дороже: выгода растет плавно,
/// а младшие ступени выпадают всегда, чтобы заказы на мелочь не зависали.
extension Balance {
    /// Шансы ступеней предмета по уровню генератора (0 - первый уровень).
    public static let generatorOdds: [[Double]] = [
        [0.90, 0.10],
        [0.75, 0.22, 0.03],
        [0.20, 0.40, 0.30, 0.10],
        [0.12, 0.25, 0.35, 0.25, 0.03],
        [0.10, 0.15, 0.30, 0.33, 0.12],
        [0.08, 0.12, 0.25, 0.35, 0.17, 0.03],
    ]
    /// Сколько энергии стоит тап по генератору каждого уровня.
    public static let generatorCost = [1, 1, 2, 3, 4, 5]
    /// Слияние в предмет этой ступени и выше изредка дарит новый генератор той же цепочки.
    public static let generatorDropMinTier = 5
    public static let generatorDropChance = 0.05

    /// Средняя ценность предмета (в базовых предметах) за 1 энергию.
    public static func generatorValuePerEnergy(level: Int) -> Double {
        let odds = generatorOdds[level]
        let value = odds.enumerated().reduce(0.0) { $0 + $1.element * Double(1 << $1.offset) }
        return value / Double(generatorCost[level])
    }
}

extension Game {
    /// Сколько энергии возьмет тап по генератору сейчас (с учетом ускорения).
    public func spawnCost(_ gen: GeneratorPiece) -> Int {
        let level = min(max(gen.tier, 0), Balance.generatorCost.count - 1)
        return Balance.generatorCost[level] * (boostActive ? 2 : 1)
    }

    /// Самый высокий уровень генератора на поле (0 - первый).
    public var bestGeneratorLevel: Int {
        state.cells.compactMap { piece -> Int? in
            if case .generator(let g)? = piece { return g.tier }
            return nil
        }.max() ?? 0
    }

    func maybeGenerator(_ item: Item) {
        guard item.tier >= Balance.generatorDropMinTier,
              Double.random(in: 0..<1, using: &rng) < Balance.generatorDropChance else { return }
        state.pendingGenerators.append(item.chain)
    }
}
