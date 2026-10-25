import SwiftUI
import Combine

/// View model for the Purge (dev-artifact cleanup) feature.
@MainActor
final class PurgeViewModel: ObservableObject {
    @Published var artifacts: [Artifact] = []
    @Published var selected: Set<URL> = []
    @Published var includeRecent = false
    @Published var mode: PurgeMode = .trash
    @Published var isScanning = false
    @Published var isPurging = false
    @Published var results: [PurgeResult] = []
    @Published var message: String?
    @Published var errorMessage: String?
    @Published var showConfirm = false

    var selectedArtifacts: [Artifact] {
        artifacts.filter { selected.contains($0.url) }
    }

    var selectedBytes: Int64 {
        selectedArtifacts.reduce(0) { $0 + $1.size }
    }

    func scan() async {
        isScanning = true
        defer { isScanning = false }
        message = nil
        errorMessage = nil
        let include = includeRecent
        let result = await Task.detached(priority: .userInitiated) {
            ArtifactDetector().detect(includeRecent: include)
        }.value
        artifacts = result
        selected.removeAll()
        results.removeAll()
    }

    func purge() {
        let targets = selectedArtifacts
        guard !targets.isEmpty else { return }
        isPurging = true
        defer { isPurging = false }
        message = nil
        errorMessage = nil
        let mode = self.mode
        let log = OperationLog()
        results = ArtifactPurger().purge(
            targets,
            mode: mode,
            confirmationToken: ArtifactPurger.permanentConfirmationToken,
            log: log
        )
        let succeeded = Set(results.filter { $0.success }.map { $0.url })
        artifacts.removeAll { succeeded.contains($0.url) }
        selected.subtract(succeeded)
        message = "Purged \(succeeded.count) of \(targets.count) artifacts."
    }
}

/// Lists disposable dev-artifact directories and purges the selection.
struct PurgeView: View {
    @StateObject private var viewModel = PurgeViewModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if viewModel.artifacts.isEmpty && !viewModel.isScanning {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Purge")
        .alert(viewModel.mode == .permanent ? "Permanently delete artifacts?" : "Move artifacts to Trash?",
               isPresented: $viewModel.showConfirm) {
            Button("Cancel", role: .cancel) {}
            Button(viewModel.mode == .permanent ? "Delete Permanently" : "Purge", role: .destructive) {
                viewModel.purge()
            }
        } message: {
            Text(viewModel.mode == .permanent
                 ? "This permanently deletes \(viewModel.selectedArtifacts.count) artifacts (\(Format.bytes(viewModel.selectedBytes))). This cannot be undone."
                 : "This moves \(viewModel.selectedArtifacts.count) artifacts (\(Format.bytes(viewModel.selectedBytes))) to the Trash.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.scan() }
            } label: {
                Label(viewModel.isScanning ? "Scanning…" : "Scan", systemImage: "magnifyingglass")
            }
            .disabled(viewModel.isScanning)
            if viewModel.isScanning {
                ProgressView().controlSize(.small)
            }
            Toggle("Include recent", isOn: $viewModel.includeRecent)
            Spacer()
            Picker("Mode", selection: $viewModel.mode) {
                Text("Trash").tag(PurgeMode.trash)
                Text("Permanent").tag(PurgeMode.permanent)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No dev artifacts found")
                .font(.title2)
            Text("Scans project folders for node_modules, build, DerivedData, and more.")
                .foregroundStyle(.secondary)
            Button("Scan Now") { Task { await viewModel.scan() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(viewModel.artifacts, id: \.url) { artifact in
                HStack(spacing: 8) {
                    Toggle("", isOn: selectionBinding(for: artifact.url))
                        .labelsHidden()
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(artifact.kind)
                        Text(artifact.url.path)
                            .truncationMode(.middle)
                            .lineLimit(1)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Format.bytes(artifact.size))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .bottom) { footer }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(viewModel.selected.count) selected · \(Format.bytes(viewModel.selectedBytes))")
                if let message = viewModel.message {
                    Text(message).font(.caption).foregroundStyle(.green)
                }
                if let error = viewModel.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
            Button {
                viewModel.showConfirm = true
            } label: {
                Label(viewModel.mode == .permanent ? "Delete" : "Purge", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selected.isEmpty || viewModel.isPurging)
        }
        .padding()
        .background(.bar)
    }

    private func selectionBinding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { viewModel.selected.contains(url) },
            set: { isOn in
                if isOn { viewModel.selected.insert(url) }
                else { viewModel.selected.remove(url) }
            }
        )
    }
}
