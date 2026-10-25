import SwiftUI

/// The sections shown in the primary sidebar.
enum SidebarSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case smartScan = "Smart Scan"
    case largeFiles = "Large Files"
    case hiddenFiles = "Hidden Files"
    case purge = "Purge"
    case optimize = "Optimize"
    case settings = "Settings"
    case log = "Log"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard: return "gauge"
        case .smartScan: return "sparkles"
        case .largeFiles: return "doc"
        case .hiddenFiles: return "eye.slash"
        case .purge: return "trash"
        case .optimize: return "bolt"
        case .settings: return "gearshape"
        case .log: return "list.bullet"
        }
    }
}

/// Root window: a `NavigationSplitView` with the feature sidebar.
struct RootView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $appState.selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            detailView
        }
        .frame(minWidth: 760, minHeight: 480)
        .environmentObject(appState)
    }

    @ViewBuilder
    private var detailView: some View {
        switch appState.selection ?? .dashboard {
        case .dashboard: DashboardView(selection: $appState.selection)
        case .smartScan: ScanView()
        case .largeFiles: LargeFilesView()
        case .hiddenFiles: HiddenFilesView()
        case .purge: PurgeView()
        case .optimize: OptimizeView()
        case .settings: SettingsView()
        case .log: LogView()
        }
    }
}
