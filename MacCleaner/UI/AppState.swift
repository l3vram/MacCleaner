import Foundation
import Combine

/// App-wide state shared across views via the SwiftUI environment:
/// disk capacity, sidebar selection, and the summary of the most recent Smart Scan.
@MainActor
final class AppState: ObservableObject {
    @Published var freeBytes: Int64?
    @Published var totalBytes: Int64?
    @Published var lastScanAt: Date?
    @Published var lastScanItemCount: Int?
    @Published var lastScanTotalBytes: Int64?
    @Published var selection: SidebarSection? = .dashboard

    init() {
        refreshDiskSpace()
    }

    /// Reads available/total capacity of the user's home volume.
    func refreshDiskSpace() {
        let url = FileManager.default.homeDirectoryForCurrentUser
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey
        ]) else {
            freeBytes = nil
            totalBytes = nil
            return
        }
        freeBytes = values.volumeAvailableCapacityForImportantUsage
        totalBytes = values.volumeTotalCapacity.map { Int64($0) }
    }

    /// Records the outcome of a Smart Scan for the dashboard.
    func recordScan(itemCount: Int, totalBytes: Int64) {
        lastScanAt = Date()
        lastScanItemCount = itemCount
        lastScanTotalBytes = totalBytes
    }
}
