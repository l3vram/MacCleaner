import XCTest
import Foundation
@testable import MacCleaner

final class LargeFilesTests: XCTestCase {
    func testOrderingAndThreshold() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try Data(repeating: 0, count: 100).write(to: tmp.appendingPathComponent("small.txt"))
        try Data(repeating: 0, count: 1000).write(to: tmp.appendingPathComponent("mid.txt"))
        try Data(repeating: 0, count: 5000).write(to: tmp.appendingPathComponent("big.txt"))

        let finder = LargeFileFinder()
        let results = await finder.findLargest(root: tmp, maxDepth: 10, minSize: 500, includeHidden: false, limit: 10)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].size, 5000)
        XCTAssertEqual(results[1].size, 1000)
    }

    func testTopNLimit() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        for i in 0..<5 {
            try Data(repeating: 0, count: 1000 + i * 100).write(to: tmp.appendingPathComponent("f\(i).txt"))
        }

        let finder = LargeFileFinder()
        let results = await finder.findLargest(root: tmp, maxDepth: 10, minSize: 0, includeHidden: false, limit: 2)
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results[0].size >= results[1].size)
    }
}
