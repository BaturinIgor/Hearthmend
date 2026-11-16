import XCTest

/// Строки интерфейса на всех языках: те же ключи, что в английском, и те же %d / %@.
/// Иначе String(format:) в игре упадет или покажет мусор.
final class StringsTests: XCTestCase {
    private var dir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Hearthmend/Resources/Strings")
    }

    private func load(_ name: String) throws -> [String: String] {
        let data = try Data(contentsOf: dir.appendingPathComponent(name))
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    private func specifiers(_ s: String) -> [String] {
        var result: [String] = []
        var chars = Array(s)[...]
        while let i = chars.firstIndex(of: "%") {
            let next = chars.index(after: i)
            if next < chars.endIndex { result.append(String(chars[next])) }
            chars = chars[chars.index(after: next < chars.endIndex ? next : i)...]
        }
        return result.sorted()
    }

    func testAllLanguagesMatchEnglish() throws {
        let en = try load("en.json")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".json") }
        XCTAssertGreaterThanOrEqual(files.count, 13)
        for file in files where file != "en.json" {
            let lang = try load(file)
            XCTAssertEqual(Set(lang.keys), Set(en.keys), "\(file): ключи как в en.json")
            for (key, value) in en {
                guard let translated = lang[key] else { continue }
                XCTAssertEqual(specifiers(translated), specifiers(value), "\(file) \(key)")
            }
        }
    }

    func testEveryTaskAndEventHasText() throws {
        let en = try load("en.json")
        let village = try JSONSerialization.jsonObject(with: Data(contentsOf: dir
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/HearthCore/Resources/village.json"))) as? [String: Any]
        let districts = village?["districts"] as? [[String: Any]] ?? []
        for d in districts {
            XCTAssertNotNil(en["district.\(d["id"] as? String ?? "")"])
            for t in d["tasks"] as? [[String: Any]] ?? [] {
                XCTAssertNotNil(en["task.\(t["id"] as? String ?? "")"], "\(t["id"] ?? "")")
            }
        }
    }
}
