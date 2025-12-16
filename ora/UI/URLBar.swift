import AppKit
import SwiftData
import SwiftUI

// MARK: - URLBar

struct URLBar: View {
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var sidebarManager: SidebarManager
    @EnvironmentObject var toolbarManager: ToolbarManager

    @State private var showCopiedAnimation = false
    @State private var startWheelAnimation = false
    @State private var editingURLString: String = ""
    @State private var showCertificateInfo = false
    @FocusState private var isEditing: Bool
    @Environment(\.colorScheme) var colorScheme

    let onSidebarToggle: () -> Void

    private func getForegroundColor(_ tab: Tab) -> Color {
        // Convert backgroundColor to NSColor for luminance calculation
        let nsColor = NSColor(tab.backgroundColor)
        if let ciColor = CIColor(color: nsColor) {
            let luminance = 0.299 * ciColor.red + 0.587 * ciColor.green + 0.114 * ciColor.blue
            let baseColor: Color = luminance < 0.5 ? .white : .black
            return baseColor
        } else {
            // Fallback to black if CIColor conversion fails
            return .black
        }
    }

    private func getUrlFieldColor(_ tab: Tab) -> Color {
        return tabManager.activeTab.map { getForegroundColor($0).opacity(isEditing ? 1.0 : 0.5) } ?? .gray
    }

    private func triggerCopy(_ text: String) {
        ClipboardUtils.triggerCopy(
            text,
            showCopiedAnimation: $showCopiedAnimation,
            startWheelAnimation: $startWheelAnimation
        )
    }

    var buttonForegroundColor: Color {
        return tabManager.activeTab.map { getForegroundColor($0).opacity(0.5) } ?? .gray
    }

    private func getDisplayURL(_ tab: Tab) -> String {
        if toolbarManager.showFullURL {
            return tab.url.absoluteString
        } else {
            return tab.url.host ?? tab.url.absoluteString
        }
    }

    private func shareCurrentPage(tab: Tab, sourceView: NSView, sourceRect: NSRect) {
        let url = tab.url
        let title = tab.title.isEmpty ? "Shared from Prism" : tab.title
        let items: [Any] = [title, url]

        let picker = NSSharingServicePicker(items: items)
        picker.delegate = nil

        DispatchQueue.main.async {
            picker.show(relativeTo: sourceRect, of: sourceView, preferredEdge: .minY)
        }
    }

    var body: some View {
        HStack {
            if let tab = tabManager.activeTab {
                HStack(spacing: 4) {
                    // Custom window controls hidden - using system traffic light buttons with padding instead
                    // if toolbarManager.isToolbarHidden || sidebarManager.sidebarPosition == .secondary {
                    //     WindowControls(isFullscreen: appState.isFullscreen)
                    // }

                    if sidebarManager.sidebarPosition == .primary {
                        URLBarButton(
                            systemName: "sidebar.left",
                            isEnabled: true,
                            foregroundColor: buttonForegroundColor,
                            action: onSidebarToggle
                        )
                        .oraShortcutHelp("Toggle Sidebar", for: KeyboardShortcuts.App.toggleSidebar)
                    }

                    // Back button
                    URLBarButton(
                        systemName: "chevron.left",
                        isEnabled: tabManager.activeTab?.webView.canGoBack ?? false,
                        foregroundColor: buttonForegroundColor,
                        action: {
                            if let activeTab = tabManager.activeTab {
                                activeTab.goBack()
                            }
                        }
                    )
                    .oraShortcut(KeyboardShortcuts.Navigation.back)
                    .oraShortcutHelp("Go Back", for: KeyboardShortcuts.Navigation.back)

                    // Forward button
                    URLBarButton(
                        systemName: "chevron.right",
                        isEnabled: tabManager.activeTab?.webView.canGoForward ?? false,
                        foregroundColor: buttonForegroundColor,
                        action: {
                            if let activeTab = tabManager.activeTab {
                                activeTab.goForward()
                            }
                        }
                    )
                    .oraShortcut(KeyboardShortcuts.Navigation.forward)
                    .oraShortcutHelp("Go Forward", for: KeyboardShortcuts.Navigation.forward)

                    // Reload button
                    URLBarButton(
                        systemName: "arrow.clockwise",
                        isEnabled: tabManager.activeTab != nil,
                        foregroundColor: buttonForegroundColor,
                        action: {
                            if let activeTab = tabManager.activeTab {
                                activeTab.webView.reload()
                            }
                        }
                    )
                    .oraShortcut(KeyboardShortcuts.Navigation.reload)
                    .oraShortcutHelp("Reload This Page", for: KeyboardShortcuts.Navigation.reload)

                    // URL field
                    HStack(spacing: 8) {
                        // Security indicator
                        if !isEditing {
                            ZStack {
                                if tab.isLoading {
                                    ProgressView()
                                        // .progressViewStyle(CircularProgressViewStyle(tint: getForegroundColor(tab)))
                                        .tint(buttonForegroundColor)
                                        .scaleEffect(0.5)
                                } else {
                                    Button {
                                        if tab.url.scheme == "https" {
                                            showCertificateInfo = true
                                        }
                                    } label: {
                                        Image(systemName: tab.url.scheme == "https" ? "lock.fill" : "globe")
                                            .font(.system(size: 12))
                                            .foregroundColor(tab.url.scheme == "https" ? .green : buttonForegroundColor)
                                    }
                                    .buttonStyle(.plain)
                                    .popover(isPresented: $showCertificateInfo, arrowEdge: .bottom) {
                                        CertificateInfoView(
                                            certificateInfo: tab.certificateInfo,
                                            host: tab.url.host
                                        )
                                    }
                                }
                            }
                            .frame(width: 16, height: 16)
                        }

                        ZStack(alignment: .leading) {
                            TextField("", text: $editingURLString)
                                .textFieldStyle(PlainTextFieldStyle())
                                .focused($isEditing)
                                .onSubmit {
                                    tab.loadURL(editingURLString)
                                    isEditing = false
                                }
                                .opacity(showCopiedAnimation ? 0 : 1)
                                .offset(y: showCopiedAnimation ? (startWheelAnimation ? -12 : 12) : 0)
                                .animation(.easeOut(duration: 0.3), value: showCopiedAnimation)
                                .animation(.easeOut(duration: 0.3), value: startWheelAnimation)

                            CopiedURLOverlay(
                                foregroundColor: getUrlFieldColor(tab),
                                showCopiedAnimation: $showCopiedAnimation,
                                startWheelAnimation: $startWheelAnimation
                            )
                        }
                        .font(.system(size: 14))
                        .foregroundColor(getUrlFieldColor(tab))
                        .onTapGesture {
                            if let activeTab = tabManager.activeTab {
                                editingURLString = activeTab.url.absoluteString
                            }
                            isEditing = true
                        }
                        .onKeyPress(.escape) {
                            isEditing = false
                            return .handled
                        }
                        // Overlay the URL/host when not editing
                        .overlay(
                            Group {
                                if !isEditing, editingURLString.isEmpty {
                                    HStack {
                                        Spacer()
                                        Text(getDisplayURL(tab))
                                            .font(.system(size: 14))
                                            .foregroundColor(getUrlFieldColor(tab))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer()
                                    }
                                }
                            }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            if let activeTab = tabManager.activeTab {
                                triggerCopy(activeTab.url.absoluteString)
                            }
                        } label: {
                            Image(systemName: "link")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(getUrlFieldColor(tab))
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.plain)
                        .oraShortcutHelp("Copy URL", for: KeyboardShortcuts.Address.copyURL)
                        .accessibilityLabel(Text("Copy URL"))

                        if let host = tab.url.host {
                            PasswordFillMenu(
                                host: host,
                                tab: tab,
                                foregroundColor: buttonForegroundColor
                            )
                            .opacity(0.75)
                        }
                    }
                    .frame(height: 30)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(getUrlFieldColor(tab).opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(
                                        isEditing ? getUrlFieldColor(tab).opacity(0.1) : Color.clear,
                                        lineWidth: 1.2
                                    )
                            )
                    )
                    .overlay(
                        // Hidden button for keyboard shortcut
                        Button("") {
                            isEditing = true
                        }
                        .oraShortcut(KeyboardShortcuts.Address.focus)
                        .opacity(0)
                        .allowsHitTesting(false)
                    )

                    ExtensionsMenuButton(foregroundColor: buttonForegroundColor)

                    ShareLinkButton(
                        isEnabled: true,
                        foregroundColor: buttonForegroundColor,
                        onShare: { sourceView, sourceRect in
                            if let activeTab = tabManager.activeTab {
                                shareCurrentPage(tab: activeTab, sourceView: sourceView, sourceRect: sourceRect)
                            }
                        }
                    )

//                    URLBarButton(
//                        systemName: "ellipsis",
//                        isEnabled: true,
//                        foregroundColor: buttonForegroundColor,
//                        action: {}
//                    )

                    if sidebarManager.sidebarPosition == .secondary {
                        URLBarButton(
                            systemName: "sidebar.right",
                            isEnabled: true,
                            foregroundColor: buttonForegroundColor,
                            action: onSidebarToggle
                        )
                        .oraShortcutHelp("Toggle Sidebar", for: KeyboardShortcuts.App.toggleSidebar)
                    }
                }
                .padding(4)
                .onAppear {
                    editingURLString = getDisplayURL(tab)
                    DispatchQueue.main.async {
                        isEditing = false
                    }
                }
                .onChange(of: tab.url) { _, _ in
                    if !isEditing {
                        editingURLString = getDisplayURL(tab)
                    }
                }
                .onChange(of: toolbarManager.showFullURL) { _, _ in
                    if !isEditing, let tab = tabManager.activeTab {
                        editingURLString = getDisplayURL(tab)
                    }
                }
                .onChange(of: tabManager.activeTab?.id) { _, _ in
                    if !isEditing, let tab = tabManager.activeTab {
                        editingURLString = getDisplayURL(tab)
                    }
                }
                .onChange(of: isEditing) { _, newValue in
                    if newValue, let tab = tabManager.activeTab {
                        editingURLString = tab.url.absoluteString
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                        }
                    } else if let tab = tabManager.activeTab {
                        editingURLString = getDisplayURL(tab)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .copyAddressURL)) { _ in
                    if let activeTab = tabManager.activeTab {
                        triggerCopy(activeTab.url.absoluteString)
                    }
                }
                .background(
                    Rectangle()
                        .fill(tab.backgroundColor)
                )
            }
        }
    }
}

private struct PasswordFillMenu: View {
    let host: String
    let tab: Tab
    let foregroundColor: Color

    @Environment(\.modelContext) private var modelContext
    @State private var isPresented = false
    @State private var cachedItems: [PasswordItem] = []
    @State private var isLoadingItems = false
    
    private var matches: [PasswordItem] {
        cachedItems.filter { item in
            guard let itemHost = item.url?.host else { return false }
            return PasswordFillMenu.baseDomain(from: itemHost) == PasswordFillMenu.baseDomain(from: host)
        }
    }
    
    private func loadPasswordItems() {
        // Prevent multiple simultaneous fetches
        guard !isLoadingItems, cachedItems.isEmpty else { return }
        isLoadingItems = true
        
        // Defer the fetch until after the current view update cycle to avoid SwiftData conflicts
        DispatchQueue.main.async {
            let descriptor = FetchDescriptor<PasswordItem>(
                sortBy: [SortDescriptor(\.siteName)]
            )
            if let items = try? modelContext.fetch(descriptor) {
                cachedItems = items
            }
            isLoadingItems = false
        }
    }

    var body: some View {
        Group {
            if matches.isEmpty {
                EmptyView()
            } else {
                Button {
                    isPresented = true
                } label: {
                    Image(systemName: "key.fill")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(foregroundColor)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Fill Password"))
                .popover(isPresented: $isPresented) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(matches) { item in
                        Button {
                            Task {
                                await fill(item: item)
                                isPresented = false
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.username)
                                    .font(.headline)
                                Text(item.siteName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .frame(minWidth: 220)
            }
            }
        }
        .onAppear {
            if cachedItems.isEmpty {
                loadPasswordItems()
            }
        }
    }

    private static func baseDomain(from host: String) -> String {
        let components = host.split(separator: ".")
        guard components.count >= 2 else { return host }
        let base = components.suffix(2)
        return base.joined(separator: ".")
    }

    private func fill(item: PasswordItem) async {
        await tab.fillPassword(from: item)
    }
}
