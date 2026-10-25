import Foundation

/// How to remove detected artifacts.
public enum PurgeMode: String, Sendable {
    case trash
    case permanent
}

/// Outcome of removing a single artifact.
public struct PurgeResult: Equatable, Sendable {
    public let url: URL
    public let success: Bool
    public let error: String?

    public init(url: URL, success: Bool, error: String?) {
        self.url = url
        self.success = success
        self.error = error
    }
}

/// Removes detected artifacts by reusing `Cleaner` (trash or permanent).
/// Permanent deletion requires an explicit confirmation token.
public final class ArtifactPurger {
    /// Must match the token enforced by `Cleaner.deletePermanent`.
    public static let permanentConfirmationToken = "PERMANENT_DELETE_CONFIRMED"

    public init() {}

    /// Removes each artifact, returning one `PurgeResult` per artifact so a
    /// single failure does not block the rest.
    @discardableResult
    public func purge(
        _ artifacts: [Artifact],
        mode: PurgeMode,
        confirmationToken: String? = nil,
        log: OperationLog? = nil
    ) -> [PurgeResult] {
        artifacts.map { artifact in
            do {
                switch mode {
                case .trash:
                    _ = try Cleaner.trash(urls: [artifact.url], log: log)
                case .permanent:
                    try Cleaner.deletePermanent(
                        urls: [artifact.url],
                        confirmationToken: confirmationToken ?? "",
                        log: log
                    )
                }
                return PurgeResult(url: artifact.url, success: true, error: nil)
            } catch {
                let message = (error as? CleanerError).map { "\($0)" } ?? "\(error)"
                return PurgeResult(url: artifact.url, success: false, error: message)
            }
        }
    }
}
