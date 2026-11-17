import XCTest
import HearthCore

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
        let a = Array(s)
        var result: [String] = []
        var i = 0
        while i < a.count - 1 {
            if a[i] == "%" {
                result.append(String(a[i + 1]))
                i += 2
            } else {
                i += 1
            }
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

    func testParallelLinesHaveText() throws {
        let en = try load("en.json")
        for r in Friends.all {
            XCTAssertNotNil(en["friends.about.\(r)"], r)
            XCTAssertNotNil(en["resident.\(r)"], r)
        }
        for kind in AchievementKind.allCases {
            XCTAssertEqual(specifiers(en["achievements.\(kind.rawValue)"] ?? ""), ["d"], kind.rawValue)
        }
        for key in ["merchant.arrived", "merchant.thanks", "merchant.about", "friends.title", "achievements.title"] {
            XCTAssertNotNil(en[key], key)
        }
    }
}
