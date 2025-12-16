//
//  TabScriptHandler.swift
//  ora
//
//  Created by keni on 7/21/25.
//
import os.log
import WebKit

private let logger = Logger(subsystem: "eu.flareapps.prism", category: "TabScriptHandler")

class TabScriptHandler: NSObject, WKScriptMessageHandler {
    var onChange: ((String) -> Void)?
    var tab: Tab?
    weak var mediaController: MediaController?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "listener" {
            guard let jsonString = message.body as? String,
                  let jsonData = jsonString.data(using: .utf8)
            else {
                return
            }

            do {
                let update = try JSONDecoder().decode(URLUpdate.self, from: jsonData)
                DispatchQueue.main.async {
                    guard let tab = self.tab else { return }
                    let oldTitle = tab.title
                    // Only update title if there's no custom name set
                    if tab.customName == nil {
                        tab.title = update.title
                    }
                    tab.url = URL(string: update.href) ?? tab.url
                    tab
                        .setFavicon(
                            faviconURLDefault: URL(string: update.favicon)
                        )
                    tab.updateHistory()

                    // If title changed and there are active media sessions, update them
                    if oldTitle != update.title, !update.title.isEmpty {
                        self.mediaController?.syncTitleForTab(tab.id, newTitle: update.title)
                    }
                }

            } catch {
                logger.error("Failed to decode JS message: \(error.localizedDescription)")
            }
        } else if message.name == "linkHover" {
            // Expect a String body with the hovered URL or empty string to clear
            let hovered = message.body as? String
            DispatchQueue.main.async {
                guard let tab = self.tab else { return }
                let trimmed = (hovered ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                tab.hoveredLinkURL = trimmed.isEmpty ? nil : trimmed
            }
        } else if message.name == "mediaEvent" {
            guard let body = message.body as? String,
                  let data = body.data(using: .utf8),
                  let tab = self.tab
            else { return }
            if let payload = try? JSONDecoder().decode(MediaEventPayload.self, from: data) {
                DispatchQueue.main.async { [weak self] in
                    self?.mediaController?.receive(event: payload, from: tab)
                }
            }
        } else if message.name == "passwordFieldFocus" {
            guard let body = message.body as? String,
                  let data = body.data(using: .utf8),
                  let tab = self.tab
            else { return }
            
            struct PasswordFieldFocus: Decodable {
                let focused: Bool?
                let x: Double?
                let y: Double?
                let width: Double?
                let height: Double?
                let inputValue: String?
            }
            
            if let payload = try? JSONDecoder().decode(PasswordFieldFocus.self, from: data) {
                DispatchQueue.main.async {
                    if let focused = payload.focused {
                        tab.passwordFieldFocused = focused
                        if focused, let x = payload.x, let y = payload.y,
                           let width = payload.width, let height = payload.height {
                            tab.passwordFieldRect = CGRect(x: x, y: y, width: width, height: height)
                        } else {
                            tab.passwordFieldRect = .zero
                            tab.passwordFieldInputValue = ""
                        }
                    }
                    if let inputValue = payload.inputValue {
                        tab.passwordFieldInputValue = inputValue
                    }
                }
            }
        }
    }

    func customWKConfig(containerId: UUID, temporaryStorage: Bool = false) -> WKWebViewConfiguration {
        // Configure WebView for performance
        let configuration = WKWebViewConfiguration()
        let userAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0.1 Safari/605.1.15"
        configuration.applicationNameForUserAgent = userAgent

        // Enable JavaScript
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        configuration.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
        configuration.preferences.setValue(true, forKey: "javaScriptEnabled")
        configuration.preferences.setValue(true, forKey: "javaScriptCanOpenWindowsAutomatically")
        if temporaryStorage {
            configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        } else {
            configuration.websiteDataStore = WKWebsiteDataStore(
                forIdentifier: containerId
            )
        }

        // Performance optimizations
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        // Enable process pool for better memory management
        let processPool = WKProcessPool()
        configuration.processPool = processPool
        // video shit
        configuration.preferences.isElementFullscreenEnabled = true
        if #unavailable(macOS 10.12) {
            // Picture in picture not available on older macOS versions
        } else {
//            configuration.allowsPictureInPictureMediaPlaybook = true
        }

        // Enable media playback without user interaction
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // GPU acceleration settings
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        // injecting listners
        let contentController = WKUserContentController()
        contentController.add(self, name: "listener")
        contentController.add(self, name: "linkHover")
        contentController.add(self, name: "mediaEvent")
        contentController.add(self, name: "passwordFieldFocus")
        configuration.userContentController = contentController

        return configuration
    }
    
    /// Inject extension scripts for the given URL
    func injectExtensionScripts(for url: URL?, into webView: WKWebView) {
        guard let url = url else { return }
        
        Task { @MainActor in
            let scriptSources = ExtensionManager.shared.getUserScripts(for: url)
            
            for scriptSource in scriptSources {
                webView.evaluateJavaScript(scriptSource) { _, error in
                    if let error = error {
                        logger.error("Failed to inject extension script: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    deinit {
        // Optional cleanup
        logger.debug("TabScriptHandler deinitialized")
    }
}
