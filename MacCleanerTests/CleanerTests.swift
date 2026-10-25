import XCTest
import Foundation
@testable import MacCleaner

final class CleanerTests: XCTestCase {
    func testValidatorRejectsProtected() {
        XCTAssertThrowsError(try Cleaner.validate(URL(fileURLWithPath: "/System/Library/foo")))
        XCTAssertThrowsError(try Cleaner.validate(URL(fileURLWithPath: "/Applications/X.app")))
    }
    func testValidatorRejectsTraversal() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let link = tmp.appendingPathComponent("escape")
        try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/"))
        XCTAssertThrowsError(try Cleaner.validate(link.appendingPathComponent("etc/passwd")))
    }
    func testValidatorRejectsOutsideRoots() {
        XCTAssertThrowsError(try Cleaner.validate(URL(fileURLWithPath: "/tmp/foo")))
    }
    func testDryRunDoesNotDelete() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let file = tmp.appendingPathComponent("a.txt")
        try Data("hi".utf8).write(to: file)
        // allowed root? temp dir not allowed. Use home? Instead test preview count and file exists.
        let plan = Cleaner.preview(urls: [file])
        XCTAssertEqual(plan.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
    func testTrashMovesFile() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("Library/Caches/MacCleanerTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("a.txt")
        try Data("hi".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try Cleaner.trash(urls: [file])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
    func testLogWritten() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("log-\(UUID().uuidString).log")
        let log = OperationLog(fileURL: tmp)
        log.append(action: "trash", source: URL(fileURLWithPath: "/Users/x/a"), destination: nil, bytes: 5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path))
    }
    func testWhitelistStore() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("wl-\(UUID().uuidString).json")
        let store = WhitelistStore(fileURL: tmp)
        try store.add("/foo")
        XCTAssertEqual(store.load(), ["/foo"])
        try store.remove("/foo")
        XCTAssertEqual(store.load(), [])
    }
    func testEmptyTrashRequiresConfirmation() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try Cleaner.emptyTrash(trash: tmp, confirmationToken: "")) { error in
            XCTAssertEqual(error as? CleanerError, .confirmationRequired)
        }
    }
    func testEmptyTrashRemovesContentsAndReportsBytes() throws {
        let trash = FileManager.default.temporaryDirectory.appendingPathComponent("trash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: trash) }
        try Data(count: 10).write(to: trash.appendingPathComponent("a.bin"))
        try Data(count: 5).write(to: trash.appendingPathComponent("b.bin"))
        XCTAssertEqual(Cleaner.trashSize(trash: trash), 15)
        let freed = try Cleaner.emptyTrash(trash: trash, confirmationToken: "PERMANENT_DELETE_CONFIRMED")
        XCTAssertEqual(freed, 15)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trash.path), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.path))
    }
    func testTrashLogsSizeMeasuredBeforeMove() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("Library/Caches/MacCleanerTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.bin")
        try Data(count: 42).write(to: file)
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("log-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: logURL) }
        let moved = try Cleaner.trash(urls: [file], whitelist: [], log: OperationLog(fileURL: logURL))
        moved.forEach { try? FileManager.default.removeItem(at: $0) }
        let contents = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("bytes=42 "), contents)
    }
}
