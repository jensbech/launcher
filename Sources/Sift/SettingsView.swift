import SwiftUI
import AppKit
import SiftCore

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var apps: [AppItem] = []
    @Published var disabled: Set<String> = []
    @Published var filter: String = ""
    @Published var launchAtLogin: Bool = false
    @Published var panelPosition: PanelPosition = .topCenter
    @Published var backdropEnabled: Bool = false
    @Published var backdropIntensity: Double = Config.defaultBackdropIntensity

    private let store: Store

    init(store: Store) {
        self.store = store
        let config = store.load()
        self.disabled = config.disabledBundleIDs
        self.launchAtLogin = config.launchAtLogin
        self.panelPosition = config.panelPosition
        self.backdropEnabled = config.backdropEnabled
        self.backdropIntensity = config.backdropIntensity
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

    func setPanelPosition(_ value: PanelPosition) {
        panelPosition = value
        persist()
    }

    func setBackdropEnabled(_ value: Bool) {
        backdropEnabled = value
        persist()
    }

    func setBackdropIntensity(_ value: Double) {
        backdropIntensity = max(0, min(1, value))
        persist()
    }

    private func persist() {
        store.save(Config(
            disabledBundleIDs: disabled,
            launchAtLogin: launchAtLogin,
            panelPosition: panelPosition,
            backdropEnabled: backdropEnabled,
            backdropIntensity: backdropIntensity
        ))
    }
}

struct SettingsView: View {
    @StateObject var viewModel: SettingsViewModel

    var body: some View {
        TabView {
            AppsTab(viewModel: viewModel)
                .tabItem { Label("Apps", systemImage: "square.grid.2x2") }
            PositionTab(viewModel: viewModel)
                .tabItem { Label("Position", systemImage: "rectangle.3.group") }
            GeneralTab(viewModel: viewModel)
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 460, height: 560)
    }
}

private struct AppsTab: View {
    @ObservedObject var viewModel: SettingsViewModel

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
        }
        .padding(20)
    }
}

private struct GeneralTab: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("General").font(.headline)
            Toggle("Launch at login", isOn: Binding(
                get: { viewModel.launchAtLogin },
                set: { viewModel.setLaunchAtLogin($0) }
            ))
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Blur and dim background when open", isOn: Binding(
                    get: { viewModel.backdropEnabled },
                    set: { viewModel.setBackdropEnabled($0) }
                ))
                Text("Adds a frosted, slightly darkened overlay across the rest of the screen while Sift is visible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Text("Intensity")
                        .font(.callout)
                        .foregroundStyle(viewModel.backdropEnabled ? .primary : .secondary)
                        .frame(width: 70, alignment: .leading)
                    Image(systemName: "circle.dotted")
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { viewModel.backdropIntensity },
                            set: { viewModel.setBackdropIntensity($0) }
                        ),
                        in: 0...1
                    )
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.secondary)
                    Text("\(Int(viewModel.backdropIntensity * 100))%")
                        .monospacedDigit()
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
                .disabled(!viewModel.backdropEnabled)
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding(20)
    }
}

private struct PositionTab: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Panel Position").font(.headline)
            Text("Choose where Sift appears on your screen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            PositionPicker(
                selection: Binding(
                    get: { viewModel.panelPosition },
                    set: { viewModel.setPanelPosition($0) }
                )
            )
            .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text(label(for: viewModel.panelPosition))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Spacer()
        }
        .padding(20)
    }

    private func label(for position: PanelPosition) -> String {
        positionLabel(position)
    }
}

private func positionLabel(_ position: PanelPosition) -> String {
    let rows = ["Top", "Top-mid", "Upper", "Middle", "Lower", "Bottom-mid", "Bottom"]
    let cols = ["left", "left-mid", "inner-left", "center", "inner-right", "right-mid", "right"]
    if position == .center { return "Center" }
    return "\(rows[position.row]) \(cols[position.column])"
}

private struct PositionPicker: View {
    @Binding var selection: PanelPosition

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let panelWidth = size.width * 0.42
            let panelHeight: CGFloat = 22

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .controlBackgroundColor).opacity(0.9),
                                Color(nsColor: .windowBackgroundColor).opacity(0.6)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )

                MenuBarMock()
                    .frame(height: 10)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, 1)
                    .padding(.top, 1)
                    .frame(maxHeight: .infinity, alignment: .top)

                MiniSiftPanel(width: panelWidth, height: panelHeight)
                    .position(
                        panelCenter(for: selection, in: size, panelWidth: panelWidth, panelHeight: panelHeight)
                    )
                    .animation(.spring(response: 0.32, dampingFraction: 0.78), value: selection)

                GridButtons(selection: $selection)
            }
        }
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
    }

    private func panelCenter(for position: PanelPosition, in size: CGSize, panelWidth: CGFloat, panelHeight: CGFloat) -> CGPoint {
        let insetX: CGFloat = 14
        let topInset: CGFloat = 18
        let bottomInset: CGFloat = 14

        let leftX = insetX + panelWidth / 2
        let rightX = size.width - insetX - panelWidth / 2
        let xs = PanelPosition.interpolatedSteps(start: leftX, center: size.width / 2, end: rightX)

        let topY = topInset + panelHeight / 2
        let bottomY = size.height - bottomInset - panelHeight / 2
        let ys = PanelPosition.interpolatedSteps(start: topY, center: size.height / 2, end: bottomY)

        return CGPoint(x: xs[position.column], y: ys[position.row])
    }
}

private struct MenuBarMock: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.primary.opacity(0.18)).frame(width: 4, height: 4)
            Circle().fill(Color.primary.opacity(0.18)).frame(width: 4, height: 4)
            Spacer()
            Circle().fill(Color.primary.opacity(0.18)).frame(width: 4, height: 4)
            Circle().fill(Color.primary.opacity(0.18)).frame(width: 4, height: 4)
            Circle().fill(Color.primary.opacity(0.18)).frame(width: 4, height: 4)
        }
        .padding(.horizontal, 8)
    }
}

private struct MiniSiftPanel: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.85), lineWidth: 1.5)
            )
            .overlay(
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.15))
                        .frame(height: 4)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
            )
            .frame(width: width, height: height)
            .shadow(color: Color.accentColor.opacity(0.35), radius: 6, x: 0, y: 2)
    }
}

private struct GridButtons: View {
    @Binding var selection: PanelPosition

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<PanelPosition.gridSize, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<PanelPosition.gridSize, id: \.self) { col in
                        let position = PanelPosition(row: row, column: col)
                        Button {
                            selection = position
                        } label: {
                            ZStack {
                                Color.clear
                                Circle()
                                    .fill(selection == position ? Color.accentColor : Color.primary.opacity(0.22))
                                    .frame(width: selection == position ? 6 : 3,
                                           height: selection == position ? 6 : 3)
                                    .animation(.easeOut(duration: 0.15), value: selection)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(positionLabel(position))
                    }
                }
            }
        }
        .padding(8)
    }
}
