import SwiftUI
import AppKit
import LauncherCore

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var apps: [AppItem] = []
    @Published var disabled: Set<String> = []
    @Published var filter: String = ""
    @Published var launchAtLogin: Bool = false

    private let store: Store

    init(store: Store) {
        self.store = store
        let config = store.load()
        self.disabled = config.disabledBundleIDs
        self.launchAtLogin = config.launchAtLogin
        self.apps = AppIndex.scan(directories: AppIndex.defaultSearchPaths)
    }

    var filtered: [AppItem] {
        guard !filter.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    func isEnabled(_ item: AppItem) -> Bool { !disabled.contains(item.id) }

    func toggle(_ item: AppItem) {
        if disabled.contains(item.id) {
            disabled.remove(item.id)
        } else {
            disabled.insert(item.id)
        }
        persist()
    }

    func setLaunchAtLogin(_ value: Bool) {
        launchAtLogin = value
        LoginItem.setEnabled(value)
        persist()
    }

    private func persist() {
        store.save(Config(disabledBundleIDs: disabled, launchAtLogin: launchAtLogin))
    }
}

struct SettingsView: View {
    @StateObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Searchable Apps").font(.headline)
            TextField("Filter", text: $viewModel.filter)
                .textFieldStyle(.roundedBorder)
            List {
                ForEach(viewModel.filtered) { item in
                    Toggle(isOn: Binding(
                        get: { viewModel.isEnabled(item) },
                        set: { _ in viewModel.toggle(item) }
                    )) {
                        HStack(spacing: 8) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                                .resizable()
                                .frame(width: 20, height: 20)
                            Text(item.name)
                        }
                    }
                }
            }
            Divider()
            Toggle("Launch at login", isOn: Binding(
                get: { viewModel.launchAtLogin },
                set: { viewModel.setLaunchAtLogin($0) }
            ))
        }
        .padding(20)
        .frame(width: 420, height: 520)
    }
}
