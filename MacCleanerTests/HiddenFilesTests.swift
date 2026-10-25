import XCTest
import Foundation
@testable import MacCleaner

final class HiddenFilesTests: XCTestCase {
    func testOnlyHiddenReturned() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try Data(repeating: 0, count: 10).write(to: tmp.appendingPathComponent("visible.txt"))
        try Data(repeating: 0, count: 10).write(to: tmp.appendingPathComponent(".hidden"))
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent(".hiddendir"), withIntermediateDirectories: true)

        let detector = HiddenFileDetector()
        let grouped = detector.detect(root: tmp, maxDepth: 10)
        let all = grouped.values.flatMap { $0 }
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.allSatisfy { $0.lastPathComponent.hasPrefix(".") })
    }

    func testGroupedByParent() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sub = tmp.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data().write(to: tmp.appendingPathComponent(".a"))
        try Data().write(to: sub.appendingPathComponent(".b"))

        let detector = HiddenFileDetector()
        let grouped = detector.detect(root: tmp, maxDepth: 10)
        XCTAssertEqual(grouped.count, 2)
    }
}
