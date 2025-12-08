//
//  ExtensionManager.swift
//  ora
//
//  Manages browser extensions installation, loading, and injection
//

import Foundation
import os.log
import WebKit

private let logger = Logger(subsystem: "eu.flareapps.prism", category: "ExtensionManager")

@MainActor
@Observable
class ExtensionManager {
    static let shared = ExtensionManager()
    
    var extensions: [BrowserExtension] = []
    
    private let extensionsDirectory: URL
    private let extensionsMetadataURL: URL
    
    private init() {
        // Set up extensions directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        extensionsDirectory = appSupport.appendingPathComponent("Prism/Extensions", isDirectory: true)
        extensionsMetadataURL = appSupport.appendingPathComponent("Prism/extensions.json")
        
        // Create directories if needed
        try? FileManager.default.createDirectory(at: extensionsDirectory, withIntermediateDirectories: true)
        
        // Load installed extensions
        loadExtensions()
    }
    
    // MARK: - Extension Loading
    
    func loadExtensions() {
        // Load from metadata file
        if let data = try? Data(contentsOf: extensionsMetadataURL),
           let decoded = try? JSONDecoder().decode([BrowserExtension].self, from: data) {
            extensions = decoded
            logger.info("Loaded \(self.extensions.count) extensions from metadata")
        } else {
            // Scan extensions directory for new extensions
            scanExtensionsDirectory()
        }
        
        // Start background scripts for enabled extensions
        for ext in extensions where ext.isEnabled {
            if ext.backgroundScript != nil {
                ExtensionBackgroundRuntime.shared.startBackgroundScript(for: ext)
            }
        }
    }
    
    private func scanExtensionsDirectory() {
        guard let enumerator = FileManager.default.enumerator(
            at: extensionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        
        var foundExtensions: [BrowserExtension] = []
        
        for case let url as URL in enumerator {
            guard let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                  resourceValues.isDirectory == false,
                  url.lastPathComponent == "manifest.json"
            else {
                continue
            }
            
            if let ext = loadExtension(from: url) {
                foundExtensions.append(ext)
            }
        }
        
        extensions = foundExtensions
        saveExtensions()
    }
    
    private func loadExtension(from manifestURL: URL) -> BrowserExtension? {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(ExtensionManifest.self, from: data) else {
            logger.error("Failed to parse manifest at \(manifestURL.path)")
            return nil
        }
        
        let directoryURL = manifestURL.deletingLastPathComponent()
        let extensionId = directoryURL.lastPathComponent
        
        // Check if extension already exists
        if let existing = extensions.first(where: { $0.id == extensionId }) {
            // Update if version changed
            if existing.version != manifest.version {
                existing.version = manifest.version
                existing.updateDate = Date()
                existing.contentScripts = manifest.contentScripts ?? []
                existing.permissions = manifest.permissions ?? []
                existing.hostPermissions = manifest.hostPermissions ?? []
                existing.backgroundScript = manifest.backgroundScriptPath
                existing.popupPath = manifest.popupPath
                existing.optionsPage = manifest.optionsPage
            }
            return existing
        }
        
        // Create new extension
        let ext = BrowserExtension(
            id: extensionId,
            name: manifest.name,
            version: manifest.version,
            description: manifest.description,
            author: manifest.author,
            manifestVersion: manifest.manifestVersion,
            isEnabled: true,
            contentScripts: manifest.contentScripts ?? [],
            permissions: manifest.permissions ?? [],
            hostPermissions: manifest.hostPermissions ?? [],
            backgroundScript: manifest.backgroundScriptPath,
            popupPath: manifest.popupPath,
            optionsPage: manifest.optionsPage,
            directoryURL: directoryURL,
            manifestURL: manifestURL
        )
        
        logger.info("Loaded extension: \(manifest.name) v\(manifest.version)")
        return ext
    }
    
    private func saveExtensions() {
        guard let data = try? JSONEncoder().encode(extensions) else {
            logger.error("Failed to encode extensions")
            return
        }
        
        try? data.write(to: extensionsMetadataURL)
    }
    
    // MARK: - Extension Installation
    
    func installExtension(from url: URL) throws -> BrowserExtension {
        // Validate it's a directory or zip file
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ExtensionError.invalidPath
        }
        
        let sourceURL: URL
        let tempURL: URL?
        
        if url.pathExtension == "zip" {
            // Extract zip file
            tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempURL!, withIntermediateDirectories: true)
            try extractZip(at: url, to: tempURL!)
            sourceURL = tempURL!
        } else if isDirectory.boolValue {
            sourceURL = url
            tempURL = nil
        } else {
            throw ExtensionError.invalidFormat
        }
        
        defer {
            // Clean up temp directory
            if let tempURL = tempURL {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }
        
        // Find manifest.json
        let manifestURL = sourceURL.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ExtensionError.missingManifest
        }
        
        // Parse manifest
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(ExtensionManifest.self, from: data) else {
            throw ExtensionError.invalidManifest
        }
        
        // Generate extension ID
        let extensionId = generateExtensionId(from: manifest.name)
        let destinationURL = extensionsDirectory.appendingPathComponent(extensionId, isDirectory: true)
        
        // Remove existing extension if present
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
            extensions.removeAll { $0.id == extensionId }
        }
        
        // Copy extension to extensions directory
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        
        // Load the extension
        let newManifestURL = destinationURL.appendingPathComponent("manifest.json")
        guard let ext = loadExtension(from: newManifestURL) else {
            throw ExtensionError.failedToLoad
        }
        
        extensions.append(ext)
        saveExtensions()
        
        // Start background script if present
        if ext.backgroundScript != nil {
            ExtensionBackgroundRuntime.shared.startBackgroundScript(for: ext)
        }
        
        logger.info("Installed extension: \(manifest.name)")
        return ext
    }
    
    func uninstallExtension(_ ext: BrowserExtension) throws {
        // Stop background script
        ExtensionBackgroundRuntime.shared.stopBackgroundScript(for: ext.id)
        
        try FileManager.default.removeItem(at: ext.directoryURL)
        extensions.removeAll { $0.id == ext.id }
        saveExtensions()
        logger.info("Uninstalled extension: \(ext.name)")
    }
    
    func toggleExtension(_ ext: BrowserExtension) {
        ext.isEnabled.toggle()
        saveExtensions()
        
        // Start/stop background script
        if ext.isEnabled, ext.backgroundScript != nil {
            ExtensionBackgroundRuntime.shared.startBackgroundScript(for: ext)
        } else if !ext.isEnabled {
            ExtensionBackgroundRuntime.shared.stopBackgroundScript(for: ext.id)
        }
        
        logger.info("\(ext.isEnabled ? "Enabled" : "Disabled") extension: \(ext.name)")
    }
    
    // MARK: - Script Injection
    
    /// Get all script sources for enabled extensions that match the given URL
    /// Returns an array of JavaScript source strings to inject
    func getUserScripts(for url: URL) -> [String] {
        var scriptSources: [String] = []
        
        for ext in extensions where ext.isEnabled {
            for contentScript in ext.contentScripts {
                if matchesURL(url, patterns: contentScript.matches) {
                    // Inject CSS
                    for cssFile in contentScript.css {
                        let cssURL = ext.directoryURL.appendingPathComponent(cssFile)
                        if let css = try? String(contentsOf: cssURL) {
                            scriptSources.append(injectCSS(css))
                        }
                    }
                    
                    // Inject JavaScript
                    for jsFile in contentScript.js {
                        let jsURL = ext.directoryURL.appendingPathComponent(jsFile)
                        if let js = try? String(contentsOf: jsURL) {
                            scriptSources.append(js)
                        }
                    }
                }
            }
        }
        
        return scriptSources
    }
    
    // MARK: - Helper Methods
    
    private func generateExtensionId(from name: String) -> String {
        let sanitized = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
        return sanitized + "-" + UUID().uuidString.prefix(8)
    }
    
    private func matchesURL(_ url: URL, patterns: [String]) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return false
        }
        
        let host = url.host ?? ""
        let path = url.path
        
        for pattern in patterns {
            if pattern == "<all_urls>" {
                return true
            }
            
            // Parse match pattern (e.g., "*://*.example.com/*")
            if pattern.contains("*://") {
                // Match pattern format: *://host/path or http://host/path
                let components = pattern.components(separatedBy: "://")
                guard components.count == 2 else { continue }
                
                let hostPath = components[1]
                let hostPattern: String
                let pathPattern: String
                
                if let slashIndex = hostPath.firstIndex(of: "/") {
                    hostPattern = String(hostPath[..<slashIndex])
                    pathPattern = String(hostPath[slashIndex...])
                } else {
                    hostPattern = hostPath
                    pathPattern = "/*"
                }
                
                // Match host
                let hostRegex = hostPattern
                    .replacingOccurrences(of: ".", with: "\\.")
                    .replacingOccurrences(of: "*", with: ".*")
                guard host.range(of: "^\(hostRegex)$", options: .regularExpression) != nil else {
                    continue
                }
                
                // Match path
                let pathRegex = pathPattern
                    .replacingOccurrences(of: "*", with: ".*")
                if path.range(of: "^\(pathRegex)$", options: .regularExpression) != nil {
                    return true
                }
            } else if pattern.hasPrefix("http://") || pattern.hasPrefix("https://") {
                // Exact URL match
                if url.absoluteString.hasPrefix(pattern) {
                    return true
                }
            } else if pattern.contains("*") {
                // Simple wildcard pattern
                let regexPattern = pattern
                    .replacingOccurrences(of: ".", with: "\\.")
                    .replacingOccurrences(of: "*", with: ".*")
                if url.absoluteString.range(of: regexPattern, options: .regularExpression) != nil {
                    return true
                }
            } else {
                // Simple substring match
                if url.absoluteString.contains(pattern) {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func injectCSS(_ css: String) -> String {
        return """
        (function() {
            const style = document.createElement('style');
            style.textContent = \(css.escapedForJavaScript);
            (document.head || document.documentElement).appendChild(style);
        })();
        """
    }
    
    private func extractZip(at sourceURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", sourceURL.path, "-d", destinationURL.path]
        process.standardOutput = nil
        process.standardError = nil
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            logger.error("Failed to extract zip: exit code \(process.terminationStatus)")
            throw ExtensionError.failedToExtract
        }
    }
}

// MARK: - Errors

enum ExtensionError: LocalizedError {
    case invalidPath
    case invalidFormat
    case missingManifest
    case invalidManifest
    case failedToLoad
    case failedToExtract
    
    var errorDescription: String? {
        switch self {
        case .invalidPath:
            return "Invalid extension path"
        case .invalidFormat:
            return "Extension must be a directory or zip file"
        case .missingManifest:
            return "manifest.json not found"
        case .invalidManifest:
            return "Invalid manifest.json format"
        case .failedToLoad:
            return "Failed to load extension"
        case .failedToExtract:
            return "Failed to extract zip file"
        }
    }
}

// MARK: - String Extension

private extension String {
    var escapedForJavaScript: String {
        return self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

