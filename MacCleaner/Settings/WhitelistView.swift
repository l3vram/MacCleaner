import SwiftUI
import Foundation

/// Observable view model backing the whitelist editor.
public final class WhitelistViewModel: ObservableObject {
    @Published public private(set) var protectedPaths: [String]
    @Published public var newPath: String = ""

    private let store: SettingsStore

    public init(store: SettingsStore = SettingsStore()) {
        self.store = store
        self.protectedPaths = store.protectedPaths()
    }

    /// Adds the entered path, ignoring empty/duplicate entries.
    public func add() {
        let trimmed = newPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? store.addProtectedPath(trimmed)
        reload()
        newPath = ""
    }

    public func remove(_ path: String) {
        try? store.removeProtectedPath(path)
        reload()
    }

    private func reload() {
        protectedPaths = store.protectedPaths()
    }
}

/// SwiftUI view to add/remove protected (whitelisted) paths.
public struct WhitelistView: View {
    @StateObject private var viewModel: WhitelistViewModel

    public init(viewModel: WhitelistViewModel = WhitelistViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Path to protect (e.g. ~/Downloads/keep)", text: $viewModel.newPath)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewModel.add() }
                Button("Add") { viewModel.add() }
                    .disabled(viewModel.newPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if viewModel.protectedPaths.isEmpty {
                Text("No protected paths yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                List {
                    ForEach(viewModel.protectedPaths, id: \.self) { path in
                        HStack {
                            Text(path)
                                .textSelection(.enabled)
                            Spacer()
                            Button(role: .destructive) {
                                viewModel.remove(path)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove from whitelist")
                        }
                    }
                }
                .listStyle(.inset)
            }

            Text("Protected paths are never deleted, even outside the trash operation.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
