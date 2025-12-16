//
//  ContentBlockingManager.swift
//  ora
//
//  Manages WebKit content blocking rules for ad blocking and privacy
//

import Foundation
import os.log
import WebKit

private let logger = Logger(subsystem: "eu.flareapps.prism", category: "ContentBlockingManager")

@MainActor
class ContentBlockingManager {
    static let shared = ContentBlockingManager()
    
    private var contentRuleLists: [String: WKContentRuleList] = [:]
    private var isCompiling = false
    
    private init() {}
    
    /// Load content blocking rules from extension
    func loadRulesForExtension(_ extension: BrowserExtension) async {
        // Look for webkit-rules.json or try to convert existing rules.json
        let webkitRulesURL = `extension`.directoryURL.appendingPathComponent("webkit-rules.json")
        let rulesURL = `extension`.directoryURL.appendingPathComponent("rules.json")
        
        var rulesData: Data?
        var isWebKitFormat = false
        
        if FileManager.default.fileExists(atPath: webkitRulesURL.path) {
            rulesData = try? Data(contentsOf: webkitRulesURL)
            isWebKitFormat = true
            logger.info("Loading WebKit rules for extension: \(`extension`.name)")
        } else if FileManager.default.fileExists(atPath: rulesURL.path) {
            // Try to use Chrome rules and convert on-the-fly
            logger.warning("No webkit-rules.json found, attempting to use rules.json")
            rulesData = try? Data(contentsOf: rulesURL)
            isWebKitFormat = false
        }
        
        guard let data = rulesData else {
            logger.warning("No content blocking rules found for extension: \(`extension`.name)")
            return
        }
        
        // Convert to WebKit format if needed
        var webkitRules: String
        
        if isWebKitFormat {
            webkitRules = String(data: data, encoding: .utf8) ?? "[]"
        } else {
            // Attempt basic conversion from Chrome declarativeNetRequest format
            webkitRules = convertChromeToWebKitRules(data)
        }
        
        // Compile rules
        await compileContentRules(identifier: `extension`.id, rulesJSON: webkitRules)
    }
    
    /// Convert Chrome declarativeNetRequest rules to WebKit format
    private func convertChromeToWebKitRules(_ data: Data) -> String {
        guard let chromeRules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            logger.error("Failed to parse Chrome rules")
            return "[]"
        }
        
        var webkitRules: [[String: Any]] = []
        
        // Convert first 50,000 rules (WebKit can handle more, but be cautious)
        for chromeRule in chromeRules.prefix(50000) {
            guard let condition = chromeRule["condition"] as? [String: Any],
                  let urlFilter = condition["urlFilter"] as? String else {
                continue
            }
            
            // Convert urlFilter from Chrome format (||domain.com) to regex
            var pattern = urlFilter
            if pattern.hasPrefix("||") {
                let domain = pattern.dropFirst(2)
                pattern = "https?://([a-z0-9.-]+\\.)?\(domain.replacingOccurrences(of: ".", with: "\\."))"
            }
            
            let webkitRule: [String: Any] = [
                "action": [
                    "type": "block"
                ],
                "trigger": [
                    "url-filter": pattern,
                    "resource-type": ["document", "image", "style-sheet", "script", "font", "raw", "media", "popup", "ping"]
                ]
            ]
            
            webkitRules.append(webkitRule)
        }
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: webkitRules, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            logger.info("Converted \(webkitRules.count) Chrome rules to WebKit format")
            return jsonString
        }
        
        return "[]"
    }
    
    /// Compile WebKit content blocking rules
    private func compileContentRules(identifier: String, rulesJSON: String) async {
        guard !isCompiling else {
            logger.warning("Already compiling rules, skipping...")
            return
        }
        
        isCompiling = true
        defer { isCompiling = false }
        
        do {
            logger.info("Compiling content blocking rules for: \(identifier)")
            
            let ruleList = try await WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: rulesJSON
            )
            
            contentRuleLists[identifier] = ruleList
            logger.info("✓ Successfully compiled \(identifier) content rules")
            
            // Notify that rules have been updated
            NotificationCenter.default.post(
                name: .contentBlockingRulesUpdated,
                object: identifier
            )
            
        } catch {
            logger.error("Failed to compile content rules for \(identifier): \(error.localizedDescription)")
            
            // If compilation fails, try to load existing rules
            if let existingRuleList = try? await WKContentRuleListStore.default().contentRuleList(forIdentifier: identifier) {
                contentRuleLists[identifier] = existingRuleList
                logger.info("Loaded existing compiled rules for: \(identifier)")
            }
        }
    }
    
    /// Apply content blocking rules to a WKWebView configuration
    func applyRulesToConfiguration(_ configuration: WKWebViewConfiguration) {
        // Check if extension is enabled before applying rules
        for ext in ExtensionManager.shared.extensions {
            guard ext.isEnabled else { continue }
            
            if let ruleList = contentRuleLists[ext.id] {
                configuration.userContentController.add(ruleList)
                logger.debug("Applied content rules: \(ext.id)")
            }
        }
    }
    
    /// Apply content blocking rules to an existing webview
    func applyRulesToWebView(_ webView: WKWebView) {
        // Check if extension is enabled before applying rules
        for ext in ExtensionManager.shared.extensions {
            guard ext.isEnabled else { continue }
            
            if let ruleList = contentRuleLists[ext.id] {
                webView.configuration.userContentController.add(ruleList)
                logger.debug("Applied content rules to existing webview: \(ext.id)")
            }
        }
    }
    
    /// Enable or disable content blocking for an extension
    func setEnabled(_ enabled: Bool, forExtension extensionId: String) {
        // This will be checked when applying rules
        // The actual enable/disable is handled by ExtensionManager.toggleExtension
        logger.info("Content blocking \(enabled ? "enabled" : "disabled") for: \(extensionId)")
    }
    
    /// Remove content blocking rules for an extension
    func removeRulesForExtension(_ extensionId: String) async {
        contentRuleLists.removeValue(forKey: extensionId)
        
        do {
            try await WKContentRuleListStore.default().removeContentRuleList(forIdentifier: extensionId)
            logger.info("Removed content blocking rules for: \(extensionId)")
        } catch {
            logger.error("Failed to remove content rules for \(extensionId): \(error.localizedDescription)")
        }
    }
    
    /// Get compiled rule list for an extension
    func getRuleList(forExtension extensionId: String) -> WKContentRuleList? {
        return contentRuleLists[extensionId]
    }
    
    /// Reload all rules from disk
    func reloadAllRules() async {
        contentRuleLists.removeAll()
        
        for ext in ExtensionManager.shared.extensions where ext.isEnabled {
            await loadRulesForExtension(ext)
        }
    }
    
    /// Get stats about loaded rules
    func getStats() -> [String: Int] {
        return [
            "loaded_rule_lists": contentRuleLists.count,
            "total_extensions": ExtensionManager.shared.extensions.count
        ]
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let contentBlockingRulesUpdated = Notification.Name("contentBlockingRulesUpdated")
}

