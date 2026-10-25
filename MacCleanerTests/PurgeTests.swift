import XCTest
import Foundation
@testable import MacCleaner

final class PurgeTests: XCTestCase {

    private func makeRoot() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    func testDetectsKnownArtifactDirs() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let nodeModules = root.appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 1000).write(to: nodeModules.appendingPathComponent("dep.js"))

        let src = root.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 10).write(to: src.appendingPathComponent("main.swift"))

        let results = ArtifactDetector().detect(roots: [root], maxDepth: 10, recencyWindow: 0, includeRecent: true)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.kind, "node_modules")
        XCTAssertGreaterThanOrEqual(results.first?.size ?? 0, 1000)
    }

    func testMatchesAllArtifactNames() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        for name in ArtifactDetector.artifactNames {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(name), withIntermediateDirectories: true
            )
        }

        let results = ArtifactDetector().detect(roots: [root], maxDepth: 10, recencyWindow: 0, includeRecent: true)
        XCTAssertEqual(Set(results.map(\.kind)), ArtifactDetector.artifactNames)
    }

    func testExcludesRecentByDefault() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let recent = root.appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(at: recent, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 100).write(to: recent.appendingPathComponent("a"))

        let now = Date()
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: recent.path)

        let detector = ArtifactDetector()
        let excluded = detector.detect(roots: [root], maxDepth: 10, recencyWindow: 7 * 24 * 60 * 60, includeRecent: false, now: now)
        XCTAssertTrue(excluded.isEmpty)

        let included = detector.detect(roots: [root], maxDepth: 10, recencyWindow: 7 * 24 * 60 * 60, includeRecent: true, now: now)
        XCTAssertEqual(included.count, 1)
    }

    func testIncludesOldArtifactsByDefault() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let old = root.appendingPathComponent("build")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 100).write(to: old.appendingPathComponent("a"))

        let now = Date()
        let oldDate = now.addingTimeInterval(-8 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: old.path)

        let results = ArtifactDetector().detect(roots: [root], maxDepth: 10, recencyWindow: 7 * 24 * 60 * 60, includeRecent: false, now: now)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.kind, "build")
    }

    func testExcludesNestedGitRepo() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let withGit = root.appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(at: withGit.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let results = ArtifactDetector().detect(roots: [root], maxDepth: 10, recencyWindow: 0, includeRecent: true)
        XCTAssertTrue(results.isEmpty)
    }

    func testExcludesDeploymentKeypair() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let withKey = root.appendingPathComponent("build")
        try FileManager.default.createDirectory(at: withKey, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: withKey.appendingPathComponent("deploy.pem"))

        let results = ArtifactDetector().detect(roots: [root], maxDepth: 10, recencyWindow: 0, includeRecent: true)
        XCTAssertTrue(results.isEmpty)
    }

    func testPurgePermanentRequiresConfirmation() {
        let artifact = Artifact(url: URL(fileURLWithPath: "/tmp/does-not-exist"), kind: "build", size: 1, modified: Date())
        let results = ArtifactPurger().purge([artifact], mode: .permanent, confirmationToken: nil)
        XCTAssertEqual(results.count, 1)
        XCTAssertFalse(results[0].success)
    }

    func testPurgePermanentDeletes() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("Library/Caches/MacCleanerPurgeTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let artifact = Artifact(url: dir, kind: "build", size: 0, modified: Date())
        let results = ArtifactPurger().purge([artifact], mode: .permanent, confirmationToken: ArtifactPurger.permanentConfirmationToken)
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].success)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func testPurgeTrashMovesFile() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("Library/Caches/MacCleanerPurgeTrash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("hi".utf8).write(to: dir.appendingPathComponent("a.txt"))
        defer { try? FileManager.default.removeItem(at: dir) }

        let artifact = Artifact(url: dir, kind: "node_modules", size: 2, modified: Date())
        let results = ArtifactPurger().purge([artifact], mode: .trash)
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].success)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }
}
