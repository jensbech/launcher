import SwiftUI
import SiftCore

struct SubActionsList: View {
    let parentTitle: String
    let bookmarkName: String
    let expansion: ActionExpansion
    let selectedIndex: Int
    let copyFlashID: String?
    let onSelect: (Int) -> Void
    let onActivate: () -> Void

    @ObservedObject private var cache = GitHubActionCache.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(bookmarkName)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.6))
                Text(parentTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text("← to go back")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.05))

            content
        }
        .onAppear { cache.ensure(expansion.cacheKey) }
    }

    @ViewBuilder
    private var content: some View {
        switch cache.snapshot(expansion.cacheKey) ?? .loading {
        case .loading:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Loading…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)

        case .failed(let message):
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)

        case .loaded(let items):
            if items.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                SubActionRow(
                                    item: item,
                                    selected: index == selectedIndex,
                                    copyFlashing: copyFlashID == "sub:\(item.id)"
                                )
                                .id(item.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onSelect(index)
                                    onActivate()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: selectedIndex) { _, newIndex in
                        if items.indices.contains(newIndex) {
                            proxy.scrollTo(items[newIndex].id)
                        }
                    }
                }
            }
        }
    }

    private var emptyMessage: String {
        switch expansion.kind {
        case .prs: return "No open pull requests."
        case .branches: return "No branches."
        case .runs: return "No recent workflow runs."
        }
    }
}

struct SubActionRow: View {
    let item: SubItem
    let selected: Bool
    let copyFlashing: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundTint)
                Image(systemName: item.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(foregroundTint)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer()
            if copyFlashing {
                CopiedBadge()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(selected ? Color.accentColor.opacity(0.35) : Color.clear)
    }

    private var backgroundTint: Color {
        switch item.tint {
        case .neutral: return Color.primary.opacity(0.10)
        case .running: return Color.blue.opacity(0.28)
        case .success: return Color.green.opacity(0.28)
        case .failure: return Color.red.opacity(0.28)
        case .warn:    return Color.orange.opacity(0.30)
        case .info:    return Color.accentColor.opacity(0.25)
        }
    }

    private var foregroundTint: Color {
        switch item.tint {
        case .neutral: return .primary.opacity(0.85)
        case .running: return .blue
        case .success: return .green
        case .failure: return .red
        case .warn:    return .orange
        case .info:    return .primary.opacity(0.95)
        }
    }
}
