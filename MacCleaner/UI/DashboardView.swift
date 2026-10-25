import SwiftUI

/// Landing view: disk capacity, last scan summary, and quick actions.
struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var selection: SidebarSection?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                storageCard
                lastScanCard
                quickActionsCard
            }
            .padding()
        }
        .navigationTitle("Dashboard")
        .onAppear { appState.refreshDiskSpace() }
        .toolbar {
            Button {
                appState.refreshDiskSpace()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh free space")
        }
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Storage").font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.bytes(appState.freeBytes ?? 0))
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                Text("free").foregroundStyle(.secondary)
            }
            if let total = appState.totalBytes, total > 0 {
                ProgressView(value: usedFraction(of: total))
                Text("\(Format.bytes(total - (appState.freeBytes ?? 0))) used of \(Format.bytes(total))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary))
    }

    private var lastScanCard: some View {
        GroupBox("Last scan") {
            if let date = appState.lastScanAt {
                VStack(alignment: .leading, spacing: 4) {
                    Text(date, style: .date) + Text(" ") + Text(date, style: .time)
                    Text("\(appState.lastScanItemCount ?? 0) items · \(Format.bytes(appState.lastScanTotalBytes ?? 0))")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No scan yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var quickActionsCard: some View {
        GroupBox("Quick actions") {
            VStack(spacing: 2) {
                quickAction("Smart Scan", icon: "sparkles") { selection = .smartScan }
                quickAction("Large Files", icon: "doc") { selection = .largeFiles }
                quickAction("Hidden Files", icon: "eye.slash") { selection = .hiddenFiles }
                quickAction("Purge dev artifacts", icon: "trash") { selection = .purge }
                quickAction("Optimize", icon: "bolt") { selection = .optimize }
            }
        }
    }

    private func quickAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 22)
                    .foregroundStyle(.tint)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func usedFraction(of total: Int64) -> Double {
        let used = total - (appState.freeBytes ?? 0)
        guard total > 0 else { return 0 }
        return min(max(Double(used) / Double(total), 0), 1)
    }
}
