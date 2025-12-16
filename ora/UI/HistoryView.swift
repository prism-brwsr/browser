import AppKit
import SwiftData
import SwiftUI

@MainActor
struct HistoryView: View {
    @Environment(\.theme) var theme
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var historyManager: HistoryManager
    @EnvironmentObject var downloadManager: DownloadManager
    @EnvironmentObject var privacyMode: PrivacyMode

    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool

    private var groupedHistory: [HistoryGroup] {
        guard let containerId = tabManager.activeContainer?.id else { return [] }
        return historyManager.getGroupedHistory(containerId: containerId, searchText: searchText)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Background
            Color.clear
                .ignoresSafeArea(.all)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .background(theme.background.opacity(0.65))
                .background(
                    BlurEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                )

            VStack(spacing: 0) {
                // Header with search bar
                VStack(spacing: 16) {
                    HStack {
                        Text("History")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(theme.foreground)
                        Spacer()
                        
                        // Clear history button
                        if !groupedHistory.isEmpty {
                            Button {
                                showClearHistoryConfirmation()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12, weight: .medium))
                                    Text("Clear History")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundColor(theme.destructive)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(theme.destructive.opacity(0.1))
                                )
                            }
                            .buttonStyle(.plain)
                            .help("Clear all browsing history")
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                    // Search bar
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(theme.foreground.opacity(0.5))
                            .font(.system(size: 14))

                        TextField("Search history", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .foregroundColor(theme.foreground)
                            .focused($isSearchFocused)
                            .onSubmit {
                                // Search is handled automatically via groupedHistory computed property
                            }

                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(theme.foreground.opacity(0.5))
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(theme.mutedBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(
                                        isSearchFocused ? theme.foreground.opacity(0.2) : Color.clear,
                                        lineWidth: 1.5
                                    )
                            )
                    )
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 16)

                // History content
                if groupedHistory.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: searchText.isEmpty ? "clock" : "magnifyingglass")
                            .font(.system(size: 48, weight: .ultraLight))
                            .foregroundColor(theme.foreground.opacity(0.3))

                        Text(searchText.isEmpty ? "No History" : "No Results")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(theme.foreground.opacity(0.7))

                        Text(searchText.isEmpty
                            ? "Your browsing history will appear here"
                            : "No history entries match your search")
                            .font(.system(size: 14))
                            .foregroundColor(theme.foreground.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(groupedHistory) { group in
                                HistorySectionView(
                                    group: group,
                                    onHistoryItemTap: { history in
                                        openHistoryItem(history, inNewTab: false)
                                    },
                                    onHistoryItemCmdTap: { history in
                                        openHistoryItem(history, inNewTab: true)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openHistoryItem(_ history: History, inNewTab: Bool) {
        if inNewTab {
            // Open in new tab
            tabManager.openTab(
                url: history.url,
                historyManager: historyManager,
                downloadManager: downloadManager,
                isPrivate: privacyMode.isPrivate
            )
        } else {
            // Open in current tab
            if let activeTab = tabManager.activeTab {
                activeTab.loadURL(history.url.absoluteString)
            } else {
                // No active tab, create new one
                tabManager.openTab(
                    url: history.url,
                    historyManager: historyManager,
                    downloadManager: downloadManager,
                    isPrivate: privacyMode.isPrivate
                )
            }
        }
    }

    private func showClearHistoryConfirmation() {
        let alert = NSAlert()
        alert.messageText = "Clear Browsing History?"
        alert.informativeText = "This will permanently delete all browsing history for this container. This action cannot be undone."
        alert.alertStyle = .warning
        
        // Add Delete first (primary button, blue) - destructive action
        alert.addButton(withTitle: "Delete")
        // Add Cancel second (secondary button, gray)
        alert.addButton(withTitle: "Cancel")
        
        // Make Cancel respond to Escape key
        alert.buttons[1].keyEquivalent = "\u{1b}" // Escape key
        
        let response = alert.runModal()
        // First button (index 0) is Delete, second button (index 1) is Cancel
        if response == .alertFirstButtonReturn {
            // User clicked "Delete"
            clearHistory()
        }
    }

    private func clearHistory() {
        guard let container = tabManager.activeContainer else { return }
        historyManager.clearContainerHistory(container)
    }
}

// MARK: - History Section View

private struct HistorySectionView: View {
    let group: HistoryGroup
    let onHistoryItemTap: (History) -> Void
    let onHistoryItemCmdTap: (History) -> Void

    @Environment(\.theme) var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text(group.section.displayName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(theme.foreground.opacity(0.7))
                .padding(.horizontal, 4)

            // History items
            VStack(spacing: 0) {
                ForEach(group.items) { history in
                    HistoryItemView(
                        history: history,
                        onTap: {
                            onHistoryItemTap(history)
                        },
                        onCmdTap: {
                            onHistoryItemCmdTap(history)
                        }
                    )
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.mutedBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.border.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

// MARK: - History Item View

private struct HistoryItemView: View {
    let history: History
    let onTap: () -> Void
    let onCmdTap: () -> Void

    @Environment(\.theme) var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            // Check for command key press at the time of click
            if let currentEvent = NSApp.currentEvent, currentEvent.modifierFlags.contains(.command) {
                onCmdTap()
            } else {
                onTap()
            }
        }) {
            HStack(spacing: 12) {
                // Favicon
                Group {
                    AsyncImage(url: history.faviconURL) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        LocalFavIcon(
                            faviconLocalFile: history.faviconLocalFile,
                            textColor: theme.foreground.opacity(0.6)
                        )
                    }
                }
                .frame(width: 20, height: 20)
                .cornerRadius(4)

                // Title and URL
                VStack(alignment: .leading, spacing: 4) {
                    Text(history.title.isEmpty ? history.url.host ?? "Untitled" : history.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(theme.foreground)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(history.url.host ?? history.url.absoluteString)
                            .font(.system(size: 12))
                            .foregroundColor(theme.foreground.opacity(0.6))
                            .lineLimit(1)

                        Text("•")
                            .font(.system(size: 12))
                            .foregroundColor(theme.foreground.opacity(0.4))

                        Text(HistoryDateFormatter.formatTimestamp(history.lastAccessedAt))
                            .font(.system(size: 12))
                            .foregroundColor(theme.foreground.opacity(0.5))
                    }
                }

                Spacer()

                // Visit count
                if history.visitCount > 1 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                        Text("\(history.visitCount)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(theme.foreground.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(theme.foreground.opacity(0.1))
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? theme.foreground.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

