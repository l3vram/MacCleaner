import Foundation

public enum OptimizeStep: String, CaseIterable, Sendable {
    case flushDNS = "Flush DNS cache"
    case rebuildQuickLook = "Rebuild QuickLook cache"
    case rebuildIconCache = "Rebuild icon cache"
    case refreshFinder = "Refresh Finder"
}

public struct OptimizeAction: Equatable, Sendable {
    public let step: OptimizeStep
    public let executable: String
    public let arguments: [String]
    public let requiresSudo: Bool

    public init(step: OptimizeStep, executable: String, arguments: [String], requiresSudo: Bool) {
        self.step = step
        self.executable = executable
        self.arguments = arguments
        self.requiresSudo = requiresSudo
    }

    public var commandString: String {
        ([executable] + arguments).joined(separator: " ")
    }
}

public struct OptimizeResult: Sendable {
    public let action: OptimizeAction
    public let success: Bool
}

public final class Optimizer {
    public init() {}

    public func actions() -> [OptimizeAction] {
        [
            OptimizeAction(step: .flushDNS, executable: "dscacheutil", arguments: ["-flushcache"], requiresSudo: false),
            OptimizeAction(step: .flushDNS, executable: "sudo", arguments: ["killall", "-HUP", "mDNSResponder"], requiresSudo: true),
            OptimizeAction(step: .rebuildQuickLook, executable: "qlmanage", arguments: ["-r"], requiresSudo: false),
            OptimizeAction(step: .rebuildIconCache, executable: "sudo", arguments: ["rm", "-rf", "/Library/Caches/com.apple.iconservices.store"], requiresSudo: true),
            OptimizeAction(step: .rebuildIconCache, executable: "killall", arguments: ["Dock"], requiresSudo: false),
            OptimizeAction(step: .refreshFinder, executable: "killall", arguments: ["Finder"], requiresSudo: false),
        ]
    }

    @discardableResult
    public func run(_ action: OptimizeAction) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [action.executable] + action.arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    public func runAll() -> [OptimizeResult] {
        actions().map { OptimizeResult(action: $0, success: run($0)) }
    }
}
