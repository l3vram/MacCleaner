import XCTest
import Foundation
@testable import MacCleaner

final class CategorizerTests: XCTestCase {
    func testKnownPaths() {
        let cases: [(String, MacCleaner.Category)] = [
            ("/Users/x/Library/Caches/foo", .userCache),
            ("/Users/x/Library/Caches/com.apple.Safari", .browserCache),
            ("/Users/x/project/node_modules", .devArtifact),
            ("/Users/x/.hidden", .hiddenFile),
            ("/Users/x/app.log", .log),
            ("/Users/x/.Trash/file", .trash),
            ("/Users/x/Library/Application Support/OldApp", .orphanedAppData),
        ]
        for (p, expected) in cases {
            let url = URL(fileURLWithPath: p)
            XCTAssertEqual(Categorizer.classify(url: url), expected, "path \(p)")
        }
    }

    func testCategorizeGroups() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cache = tmp.appendingPathComponent("Library/Caches/foo")
        try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(repeating: 0, count: 10).write(to: cache)
        let groups = Categorizer.categorize(urls: [cache])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.category, .userCache)
    }

    func testAllCategoriesRepresented() {
        XCTAssertEqual(MacCleaner.Category.allCases.count, 9)
    }
}
