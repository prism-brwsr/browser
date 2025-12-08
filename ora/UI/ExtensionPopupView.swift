//
//  ExtensionPopupView.swift
//  ora
//
//  View for displaying extension popups
//

import SwiftUI
import WebKit

struct ExtensionPopupView: View {
    let ext: BrowserExtension
    let popupPath: String
    @State private var webView: WKWebView?
    
    var body: some View {
        ExtensionPopupWebView(ext: ext, popupPath: popupPath)
            .frame(width: 400, height: 500)
    }
}

struct ExtensionPopupWebView: NSViewRepresentable {
    let ext: BrowserExtension
    let popupPath: String
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = preferences
        
        // Inject extension APIs
        let contentController = WKUserContentController()
        
        // Inject chrome.runtime and chrome.storage APIs
        let apiScript = createExtensionAPIs(ext: ext)
        let userScript = WKUserScript(source: apiScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(userScript)
        
        config.userContentController = contentController
        
        let webView = WKWebView(frame: .zero, configuration: config)
        
        // Load popup HTML
        let popupURL = ext.directoryURL.appendingPathComponent(popupPath)
        if FileManager.default.fileExists(atPath: popupURL.path) {
            webView.loadFileURL(popupURL, allowingReadAccessTo: ext.directoryURL)
        }
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // No updates needed
    }
    
    private func createExtensionAPIs(ext: BrowserExtension) -> String {
        return """
        (function() {
            // chrome.runtime API
            if (!window.chrome) window.chrome = {};
            if (!window.chrome.runtime) {
                window.chrome.runtime = {
                    id: '\(ext.id)',
                    sendMessage: function(message, callback) {
                        // Send message to background script
                        window.webkit.messageHandlers.extensionMessage.postMessage({
                            extensionId: '\(ext.id)',
                            message: message
                        });
                        if (callback) setTimeout(callback, 0);
                    },
                    onMessage: {
                        addListener: function(callback) {
                            // Store listener for background script messages
                            window._extensionMessageListeners = window._extensionMessageListeners || [];
                            window._extensionMessageListeners.push(callback);
                        }
                    },
                    openOptionsPage: function() {
                        // TODO: Open options page
                        console.log('openOptionsPage called');
                    }
                };
            }
            
            // chrome.storage.local API
            if (!window.chrome.storage) window.chrome.storage = {};
            if (!window.chrome.storage.local) {
                window.chrome.storage.local = {
                    get: function(keys, callback) {
                        window.webkit.messageHandlers.storageGet.postMessage({
                            extensionId: '\(ext.id)',
                            keys: keys
                        });
                        // Return empty result for now
                        if (callback) callback({});
                    },
                    set: function(items, callback) {
                        window.webkit.messageHandlers.storageSet.postMessage({
                            extensionId: '\(ext.id)',
                            items: items
                        });
                        if (callback) setTimeout(callback, 0);
                    }
                };
            }
        })();
        """
    }
}

