//
//  ExtensionBackgroundRuntime.swift
//  ora
//
//  Runtime for executing extension background scripts (service workers)
//

import Foundation
import os.log
import WebKit

private let logger = Logger(subsystem: "eu.flareapps.prism", category: "ExtensionBackgroundRuntime")

@MainActor
class ExtensionBackgroundRuntime: NSObject {
    static let shared = ExtensionBackgroundRuntime()
    
    private var backgroundWebViews: [String: WKWebView] = [:]
    private var messageHandlers: [String: [String: (Any) -> Void]] = [:]
    
    private override init() {
        super.init()
    }
    
    /// Start background script for an extension
    func startBackgroundScript(for ext: BrowserExtension) {
        guard let backgroundScript = ext.backgroundScript else { return }
        
        // Don't start if already running
        if backgroundWebViews[ext.id] != nil {
            return
        }
        
        let config = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = preferences
        
        // Create content controller with extension APIs
        let contentController = WKUserContentController()
        
        // Inject extension APIs
        let apiScript = createBackgroundAPIs(ext: ext)
        let userScript = WKUserScript(source: apiScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(userScript)
        
        // Add message handler
        contentController.add(self, name: "backgroundMessage")
        
        config.userContentController = contentController
        
        let webView = WKWebView(frame: .zero, configuration: config)
        backgroundWebViews[ext.id] = webView
        
        // Load background script
        let scriptURL = ext.directoryURL.appendingPathComponent(backgroundScript)
        if let scriptContent = try? String(contentsOf: scriptURL) {
            // Wrap in service worker context
            let wrappedScript = wrapAsServiceWorker(scriptContent)
            webView.evaluateJavaScript(wrappedScript) { result, error in
                if let error = error {
                    logger.error("Failed to load background script for \(ext.name): \(error.localizedDescription)")
                } else {
                    logger.info("Started background script for \(ext.name)")
                }
            }
        }
    }
    
    /// Stop background script for an extension
    func stopBackgroundScript(for extensionId: String) {
        backgroundWebViews.removeValue(forKey: extensionId)
        messageHandlers.removeValue(forKey: extensionId)
    }
    
    /// Send message to background script
    func sendMessage(to extensionId: String, message: Any, completion: @escaping (Any?) -> Void) {
        guard let webView = backgroundWebViews[extensionId] else {
            completion(nil)
            return
        }
        
        let messageJSON = try? JSONSerialization.data(withJSONObject: message)
        let messageString = messageJSON.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        
        let script = """
        if (window._extensionMessageHandler) {
            window._extensionMessageHandler(\(messageString));
        }
        """
        
        webView.evaluateJavaScript(script) { result, error in
            completion(result)
        }
    }
    
    private func createBackgroundAPIs(ext: BrowserExtension) -> String {
        return """
        (function() {
            // chrome.runtime API
            window.chrome = window.chrome || {};
            window.chrome.runtime = {
                id: '\(ext.id)',
                onMessage: {
                    _listeners: [],
                    addListener: function(callback) {
                        this._listeners.push(callback);
                    },
                    removeListener: function(callback) {
                        const index = this._listeners.indexOf(callback);
                        if (index > -1) this._listeners.splice(index, 1);
                    }
                },
                sendMessage: function(message, callback) {
                    // Send message from background to popup/content scripts
                    window.webkit.messageHandlers.backgroundMessage.postMessage({
                        type: 'sendMessage',
                        message: message
                    });
                    if (callback) setTimeout(callback, 0);
                }
            };
            
            // chrome.storage.local API
            window.chrome.storage = window.chrome.storage || {};
            window.chrome.storage.local = {
                get: function(keys, callback) {
                    window.webkit.messageHandlers.backgroundMessage.postMessage({
                        type: 'storageGet',
                        keys: keys
                    });
                    // Return stored data
                    const stored = localStorage.getItem('extension_\(ext.id)_storage') || '{}';
                    const data = JSON.parse(stored);
                    if (callback) callback(data);
                },
                set: function(items, callback) {
                    const stored = localStorage.getItem('extension_\(ext.id)_storage') || '{}';
                    const data = JSON.parse(stored);
                    Object.assign(data, items);
                    localStorage.setItem('extension_\(ext.id)_storage', JSON.stringify(data));
                    window.webkit.messageHandlers.backgroundMessage.postMessage({
                        type: 'storageSet',
                        items: items
                    });
                    if (callback) setTimeout(callback, 0);
                }
            };
            
            // chrome.declarativeNetRequest API (simplified)
            window.chrome.declarativeNetRequest = window.chrome.declarativeNetRequest || {};
            window.chrome.declarativeNetRequest.updateDynamicRules = function(options, callback) {
                window.webkit.messageHandlers.backgroundMessage.postMessage({
                    type: 'updateDynamicRules',
                    options: options
                });
                if (callback) setTimeout(callback, 0);
            };
            
            // Message handler for incoming messages
            window._extensionMessageHandler = function(message) {
                window.chrome.runtime.onMessage._listeners.forEach(listener => {
                    try {
                        listener(message, null, function(response) {
                            // Handle response
                        });
                    } catch (e) {
                        console.error('Error in message listener:', e);
                    }
                });
            };
        })();
        """
    }
    
    private func wrapAsServiceWorker(_ script: String) -> String {
        // Wrap script in a context that mimics service worker environment
        return """
        (function() {
            'use strict';
            \(script)
        })();
        """
    }
}

extension ExtensionBackgroundRuntime: WKScriptMessageHandler {
    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor in
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else {
                return
            }
            
            // Handle different message types
            switch type {
            case "sendMessage":
                // Forward message to popup/content scripts
                break
            case "storageGet", "storageSet":
                // Handle storage operations
                break
            case "updateDynamicRules":
                // Handle declarativeNetRequest rules
                logger.info("updateDynamicRules called")
                break
            default:
                break
            }
        }
    }
}

