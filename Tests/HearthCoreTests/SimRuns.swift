import Foundation
@testable import HearthCore

/// Один прогон бота с настройками по умолчанию на каждое зерно. Проверки баланса разных событий
/// смотрят в одни и те же партии, поэтому считаем их один раз, а не в каждом тесте заново.
enum SimRuns {
    private static var cache: [UInt64: SimReport] = [:]
    private static let lock = NSLock()

    static func standard(_ seed: UInt64) -> SimReport {
        lock.lock()
        defer { lock.unlock() }
        if let r = cache[seed] { return r }
        var config = SimConfig()
        config.seed = seed
        let r = Simulator.run(config)
        cache[seed] = r
        return r
    }
}
