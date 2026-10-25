import SwiftUI
import Combine

/// View model for the Smart Scan flow: scan targeted roots, categorize,
/// let the user select categories, and trash (or dry-run) the selection.
@MainActor
final class ScanViewModel: ObservableObject {
    @Published var groups: [CategoryGroup] = []
    @Published var selected: Set<Category> = []
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var dryRun = false
    @Published var message: String?
    @Published var errorMessage: String?
    @Published var showConfirm = false
    @Published var showEmptyTrashConfirm = false
    @Published var trashBytes: Int64 = 0

    private let scanner = FileSystemScanner()
    private let log = OperationLog()

    /// Roots scanned by Smart Scan. These map onto the safe-to-delete
    /// categories (caches, logs, trash, dev artifacts) while staying fast.
    static let scanRoots: [URL] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Caches"),
            home.appendingPathComponent("Library/Logs"),
            home.appendingPathComponent(".Trash"),
            home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        ]
    }()

    var selectedURLs: [URL] {
        groups.filter { selected.contains($0.category) }.flatMap { $0.urls }
    }

    var selectedTotalBytes: Int64 {
        groups.filter { selected.contains($0.category) }.reduce(0) { $0 + $1.totalSize }
    }

    var allURLs: [URL] { groups.flatMap { $0.urls } }

    func scan(clearMessage: Bool = true) async {
        isScanning = true
        defer { isScanning = false }
        if clearMessage { message = nil }
        errorMessage = nil

        var collected: [URL] = []
        for root in Self.scanRoots {
            let urls = await scanner.scan(root: root, maxDepth: 12, minSize: 0, includeHidden: true)
            collected.append(contentsOf: urls)
        }
        groups = Categorizer.categorize(urls: Array(Set(collected)))
        // Default-select only safe categories; unsafe ones need explicit opt-in.
        selected = Set(groups.filter { $0.safeToDelete }.map { $0.category })
    }

    /// Moves the selected files to Trash (or previews when dry-run is on).
    func performClean() async {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        isCleaning = true
        defer { isCleaning = false }
        message = nil
        errorMessage = nil
        do {
            if dryRun {
                let plan = Cleaner.preview(urls: urls)
                let bytes = plan.reduce(0) { $0 + $1.bytes }
                message = "Dry run: \(plan.count) items (\(Format.bytes(bytes))) previewed. Nothing was deleted."
            } else {
                // Move to Trash off the main thread to keep the UI responsive.
                let log = self.log
                let moved = try await Task.detached(priority: .userInitiated) {
                    try Cleaner.trash(urls: urls, log: log)
                }.value
                message = "Moved \(moved.count) of \(urls.count) items to Trash."
            }
        } catch {
            errorMessage = "\(error)"
        }
        // Refresh results after cleaning without clobbering the status message.
        if !dryRun { await scan(clearMessage: false) }
    }

    func refreshTrashSize() async {
        trashBytes = await Task.detached(priority: .utility) { Cleaner.trashSize() }.value
    }

    /// Permanently empties the Trash. Only reachable through its own confirmation.
    func performEmptyTrash() async {
        isCleaning = true
        defer { isCleaning = false }
        message = nil
        errorMessage = nil
        do {
            let log = self.log
            let freed = try await Task.detached(priority: .userInitiated) {
                try Cleaner.emptyTrash(confirmationToken: "PERMANENT_DELETE_CONFIRMED", log: log)
            }.value
            message = "Emptied Trash, freed \(Format.bytes(freed))."
        } catch {
            errorMessage = "\(error)"
        }
        await scan(clearMessage: false)
        await refreshTrashSize()
    }
}

/// Smart Scan + results view with per-category checkboxes and a Clean action.
struct ScanView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = ScanViewModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if viewModel.groups.isEmpty && !viewModel.isScanning {
                emptyState
            } else {
                resultsList
            }
        }
        .navigationTitle("Smart Scan")
        .alert("Move selected files to Trash?", isPresented: $viewModel.showConfirm) {
            Button("Cancel", role: .cancel) {}
            Button(viewModel.dryRun ? "Preview" : "Clean", role: .destructive) {
                Task { await viewModel.performClean() }
            }
        } message: {
            Text(viewModel.dryRun
                 ? "Dry run: \(viewModel.selectedURLs.count) items (\(Format.bytes(viewModel.selectedTotalBytes))) would be moved to Trash. Nothing will be deleted."
                 : "This will move \(viewModel.selectedURLs.count) items (\(Format.bytes(viewModel.selectedTotalBytes))) to the Trash.")
        }
        .alert("Empty Trash?", isPresented: $viewModel.showEmptyTrashConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Empty Trash", role: .destructive) {
                Task { await viewModel.performEmptyTrash() }
            }
        } message: {
            Text("This permanently deletes everything in the Trash (\(Format.bytes(viewModel.trashBytes))), including items you trashed before. This cannot be undone.")
        }
        .task { await viewModel.refreshTrashSize() }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                Task { await runScan() }
            } label: {
                Label(viewModel.isScanning ? "Scanning…" : "Scan", systemImage: "sparkles")
            }
            .disabled(viewModel.isScanning)

            if viewModel.isScanning {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Toggle("Dry run", isOn: $viewModel.dryRun)
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Scan for removable files")
                .font(.title2)
            Text("Checks caches, logs, trash, and Xcode DerivedData.")
                .foregroundStyle(.secondary)
            Button("Scan Now") {
                Task { await runScan() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsList: some View {
        List {
            ForEach(viewModel.groups, id: \.category) { group in
                Section {
                    ForEach(group.urls.prefix(150), id: \.self) { url in
                        HStack(spacing: 8) {
                            Image(systemName: group.safeToDelete ? "doc" : "exclamationmark.triangle")
                                .foregroundStyle(group.safeToDelete ? Color.secondary : Color.orange)
                            Text(url.path)
                                .truncationMode(.middle)
                                .lineLimit(1)
                                .font(.caption)
                            Spacer()
                            Text(Format.bytes(fileSize(url)))
                                .monospacedDigit()
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if group.urls.count > 150 {
                        Text("… and \(group.urls.count - 150) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    HStack(spacing: 8) {
                        Toggle("", isOn: categoryBinding(group.category))
                            .labelsHidden()
                        Text(group.category.displayName)
                            .font(.headline)
                        Spacer()
                        Text("\(group.urls.count) · \(Format.bytes(group.totalSize))")
                            .monospacedDigit()
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .bottom) { footer }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(viewModel.selectedURLs.count) items selected · \(Format.bytes(viewModel.selectedTotalBytes))")
                if let message = viewModel.message {
                    Text(message).font(.caption).foregroundStyle(.green)
                }
                if let error = viewModel.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
            Button {
                Task {
                    await viewModel.refreshTrashSize()
                    viewModel.showEmptyTrashConfirm = true
                }
            } label: {
                Label("Empty Trash…", systemImage: "trash.slash")
            }
            .disabled(viewModel.isCleaning)
            Button {
                viewModel.showConfirm = true
            } label: {
                Label(viewModel.dryRun ? "Preview" : "Clean", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedURLs.isEmpty || viewModel.isCleaning)
        }
        .padding()
        .background(.bar)
    }

    private func runScan() async {
        await viewModel.scan()
        appState.recordScan(
            itemCount: viewModel.allURLs.count,
            totalBytes: viewModel.groups.reduce(0) { $0 + $1.totalSize }
        )
    }

    private func categoryBinding(_ category: Category) -> Binding<Bool> {
        Binding(
            get: { viewModel.selected.contains(category) },
            set: { isOn in
                if isOn { viewModel.selected.insert(category) }
                else { viewModel.selected.remove(category) }
            }
        )
    }

    private func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
