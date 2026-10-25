import XCTest
import Foundation
@testable import MacCleaner

final class ScannerTests: XCTestCase {
    func testScanCountsAndSizes() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let small = tmp.appendingPathComponent("small.txt")
        let big = tmp.appendingPathComponent("big.txt")
        try Data(repeating: 0, count: 100).write(to: small)
        try Data(repeating: 0, count: 1000).write(to: big)

        let scanner = FileSystemScanner()
        let results = await scanner.scan(root: tmp, maxDepth: 10, minSize: 500, includeHidden: false)
        XCTAssertEqual(results.count, 1)
        // size check via resource values
        let size = (try? results.first?.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        XCTAssertEqual(size, 1000)
    }

    func testHiddenFiles() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let hidden = tmp.appendingPathComponent(".hidden")
        try Data(repeating: 0, count: 600).write(to: hidden)

        let scanner = FileSystemScanner()
        let without = await scanner.scan(root: tmp, maxDepth: 10, minSize: 0, includeHidden: false)
        XCTAssertEqual(without.count, 0)
        let withHidden = await scanner.scan(root: tmp, maxDepth: 10, minSize: 0, includeHidden: true)
        XCTAssertEqual(withHidden.count, 1)
    }

    func testProtectedPathSkipped() async {
        let scanner = FileSystemScanner()
        let results = await scanner.scan(root: URL(fileURLWithPath: "/System"), maxDepth: 2, minSize: 0, includeHidden: true)
        XCTAssertTrue(results.isEmpty)
    }
}
