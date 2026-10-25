import XCTest
import Foundation
@testable import MacCleaner

final class SettingsStoreTests: XCTestCase {

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-\(UUID().uuidString).json")
    }

    func testDefaultsWhenMissing() {
        let store = SettingsStore(fileURL: tempFile())
        XCTAssertEqual(store.load(), .default)
    }

    func testPersistAndReloadRoundTrip() throws {
        let url = tempFile()
        let settings = AppSettings(
            protectedPaths: ["/Users/x/keep", "/Users/x/important"],
            largeFileThresholdBytes: 250 * 1024 * 1024
        )
        try SettingsStore(fileURL: url).save(settings)

        let reloaded = SettingsStore(fileURL: url).load()
        XCTAssertEqual(reloaded, settings)
        XCTAssertEqual(reloaded.protectedPaths.count, 2)
        XCTAssertEqual(reloaded.largeFileThresholdBytes, 250 * 1024 * 1024)
    }

    func testAddAndRemoveProtectedPaths() throws {
        let url = tempFile()
        let store = SettingsStore(fileURL: url)
        try store.addProtectedPath("/Users/x/keep")
        try store.addProtectedPath("/Users/x/keep") // de-dupe
        XCTAssertEqual(store.protectedPaths(), ["/Users/x/keep"])

        try store.addProtectedPath("/Users/x/other")
        XCTAssertEqual(store.protectedPaths(), ["/Users/x/keep", "/Users/x/other"])

        try store.removeProtectedPath("/Users/x/keep")
        XCTAssertEqual(store.protectedPaths(), ["/Users/x/other"])
    }

    func testThresholdPersists() throws {
        let url = tempFile()
        let store = SettingsStore(fileURL: url)
        try store.setLargeFileThreshold(bytes: 500 * 1024 * 1024)
        XCTAssertEqual(store.load().largeFileThresholdBytes, 500 * 1024 * 1024)
    }

    func testWhitelistRespectedByCleaner() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let keepDir = home.appendingPathComponent("Library/Caches/keep-\(UUID().uuidString)")

        // Whitelisted path is rejected even though it lies under an allowed root.
        XCTAssertThrowsError(try Cleaner.validate(keepDir, whitelist: [keepDir.path]))
        // Children of a whitelisted directory are also rejected.
        XCTAssertThrowsError(
            try Cleaner.validate(keepDir.appendingPathComponent("child.txt"), whitelist: [keepDir.path])
        )
        // Without the whitelist entry the same path is permitted.
        XCTAssertNoThrow(try Cleaner.validate(keepDir, whitelist: []))
    }
}
