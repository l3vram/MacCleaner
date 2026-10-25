import XCTest
@testable import MacCleaner

final class OptimizerTests: XCTestCase {
    func testCommandConstruction() {
        let opt = Optimizer()
        let actions = opt.actions()
        XCTAssertEqual(actions.count, 6)
        XCTAssertEqual(actions[0].executable, "dscacheutil")
        XCTAssertEqual(actions[0].arguments, ["-flushcache"])
        XCTAssertFalse(actions[0].requiresSudo)
        XCTAssertEqual(actions[1].executable, "sudo")
        XCTAssertTrue(actions[1].arguments.contains("mDNSResponder"))
        XCTAssertTrue(actions[1].requiresSudo)
        XCTAssertTrue(actions.contains { $0.executable == "qlmanage" && $0.arguments == ["-r"] })
        XCTAssertTrue(actions.contains { $0.executable == "sudo" && $0.arguments.contains("/Library/Caches/com.apple.iconservices.store") })
        XCTAssertTrue(actions.contains { $0.executable == "killall" && $0.arguments == ["Finder"] })
    }

    func testGracefulFailureOnMissingExecutable() {
        let action = OptimizeAction(step: .flushDNS, executable: "definitely-not-a-real-binary", arguments: [], requiresSudo: false)
        let opt = Optimizer()
        XCTAssertFalse(opt.run(action))
    }
}
