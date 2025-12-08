//
//  Extension.swift
//  ora
//
//  Extension model for browser extensions
//

import Foundation

/// Represents a browser extension
@Observable
class BrowserExtension: Identifiable, Codable {
    var id: String
    var name: String
    var version: String
    var description: String?
    var author: String?
    var manifestVersion: Int
    var isEnabled: Bool
    var installDate: Date
    var updateDate: Date
    
    // Manifest data
    var contentScripts: [ContentScript]
    var permissions: [String]
    var hostPermissions: [String]
    
    // Manifest V3 fields
    var backgroundScript: String? // service_worker or background.scripts[0]
    var popupPath: String? // action.default_popup or browser_action.default_popup
    var optionsPage: String? // options_page
    
    // File paths
    var directoryURL: URL
    var manifestURL: URL
    
    init(
        id: String,
        name: String,
        version: String,
        description: String? = nil,
        author: String? = nil,
        manifestVersion: Int = 2,
        isEnabled: Bool = true,
        installDate: Date = Date(),
        updateDate: Date = Date(),
        contentScripts: [ContentScript] = [],
        permissions: [String] = [],
        hostPermissions: [String] = [],
        backgroundScript: String? = nil,
        popupPath: String? = nil,
        optionsPage: String? = nil,
        directoryURL: URL,
        manifestURL: URL
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.author = author
        self.manifestVersion = manifestVersion
        self.isEnabled = isEnabled
        self.installDate = installDate
        self.updateDate = updateDate
        self.contentScripts = contentScripts
        self.permissions = permissions
        self.hostPermissions = hostPermissions
        self.backgroundScript = backgroundScript
        self.popupPath = popupPath
        self.optionsPage = optionsPage
        self.directoryURL = directoryURL
        self.manifestURL = manifestURL
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id, name, version, description, author
        case manifestVersion, isEnabled, installDate, updateDate
        case contentScripts, permissions, hostPermissions
        case backgroundScript, popupPath, optionsPage
        case directoryURL, manifestURL
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        manifestVersion = try container.decode(Int.self, forKey: .manifestVersion)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        installDate = try container.decode(Date.self, forKey: .installDate)
        updateDate = try container.decode(Date.self, forKey: .updateDate)
        contentScripts = try container.decode([ContentScript].self, forKey: .contentScripts)
        permissions = try container.decode([String].self, forKey: .permissions)
        hostPermissions = try container.decode([String].self, forKey: .hostPermissions)
        backgroundScript = try container.decodeIfPresent(String.self, forKey: .backgroundScript)
        popupPath = try container.decodeIfPresent(String.self, forKey: .popupPath)
        optionsPage = try container.decodeIfPresent(String.self, forKey: .optionsPage)
        
        let directoryString = try container.decode(String.self, forKey: .directoryURL)
        directoryURL = URL(fileURLWithPath: directoryString)
        
        let manifestString = try container.decode(String.self, forKey: .manifestURL)
        manifestURL = URL(fileURLWithPath: manifestString)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encode(manifestVersion, forKey: .manifestVersion)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(installDate, forKey: .installDate)
        try container.encode(updateDate, forKey: .updateDate)
        try container.encode(contentScripts, forKey: .contentScripts)
        try container.encode(permissions, forKey: .permissions)
        try container.encode(hostPermissions, forKey: .hostPermissions)
        try container.encodeIfPresent(backgroundScript, forKey: .backgroundScript)
        try container.encodeIfPresent(popupPath, forKey: .popupPath)
        try container.encodeIfPresent(optionsPage, forKey: .optionsPage)
        try container.encode(directoryURL.path, forKey: .directoryURL)
        try container.encode(manifestURL.path, forKey: .manifestURL)
    }
}

/// Represents a content script configuration
struct ContentScript: Codable, Equatable {
    var matches: [String]
    var js: [String]
    var css: [String]
    var runAt: RunAt
    
    enum RunAt: String, Codable {
        case documentStart = "document_start"
        case documentEnd = "document_end"
        case documentIdle = "document_idle"
    }
    
    enum CodingKeys: String, CodingKey {
        case matches, js, css
        case runAt = "run_at"
    }
    
    init(matches: [String] = [], js: [String] = [], css: [String] = [], runAt: RunAt = .documentIdle) {
        self.matches = matches
        self.js = js
        self.css = css
        self.runAt = runAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matches = try container.decode([String].self, forKey: .matches)
        js = try container.decode([String].self, forKey: .js)
        css = try container.decodeIfPresent([String].self, forKey: .css) ?? []
        
        if let runAtString = try? container.decode(String.self, forKey: .runAt),
           let runAt = RunAt(rawValue: runAtString) {
            self.runAt = runAt
        } else {
            self.runAt = .documentIdle // Default
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(matches, forKey: .matches)
        try container.encode(js, forKey: .js)
        try container.encode(css, forKey: .css)
        try container.encode(runAt.rawValue, forKey: .runAt)
    }
}

/// Extension manifest structure
struct ExtensionManifest: Codable {
    var manifestVersion: Int
    var name: String
    var version: String
    var description: String?
    var author: String?
    var contentScripts: [ContentScript]?
    var permissions: [String]?
    var hostPermissions: [String]?
    
    // Manifest V2 fields
    var browserAction: BrowserAction?
    
    // Manifest V3 fields
    var action: BrowserAction?
    var background: BackgroundConfig?
    var optionsPage: String?
    
    enum CodingKeys: String, CodingKey {
        case manifestVersion = "manifest_version"
        case name, version, description, author
        case contentScripts = "content_scripts"
        case permissions
        case hostPermissions = "host_permissions"
        case browserAction = "browser_action"
        case action
        case background
        case optionsPage = "options_page"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        manifestVersion = try container.decode(Int.self, forKey: .manifestVersion)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        contentScripts = try container.decodeIfPresent([ContentScript].self, forKey: .contentScripts)
        permissions = try container.decodeIfPresent([String].self, forKey: .permissions)
        hostPermissions = try container.decodeIfPresent([String].self, forKey: .hostPermissions)
        browserAction = try container.decodeIfPresent(BrowserAction.self, forKey: .browserAction)
        action = try container.decodeIfPresent(BrowserAction.self, forKey: .action)
        background = try container.decodeIfPresent(BackgroundConfig.self, forKey: .background)
        optionsPage = try container.decodeIfPresent(String.self, forKey: .optionsPage)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(manifestVersion, forKey: .manifestVersion)
        try container.encode(name, forKey: .name)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encodeIfPresent(contentScripts, forKey: .contentScripts)
        try container.encodeIfPresent(permissions, forKey: .permissions)
        try container.encodeIfPresent(hostPermissions, forKey: .hostPermissions)
        try container.encodeIfPresent(browserAction, forKey: .browserAction)
        try container.encodeIfPresent(action, forKey: .action)
        try container.encodeIfPresent(background, forKey: .background)
        try container.encodeIfPresent(optionsPage, forKey: .optionsPage)
    }
    
    // Helper to get popup path (works for both V2 and V3)
    var popupPath: String? {
        return action?.defaultPopup ?? browserAction?.defaultPopup
    }
    
    // Helper to get background script (works for both V2 and V3)
    var backgroundScriptPath: String? {
        if let serviceWorker = background?.serviceWorker {
            return serviceWorker
        }
        if let scripts = background?.scripts, let first = scripts.first {
            return first
        }
        return nil
    }
}

struct BrowserAction: Codable {
    var defaultPopup: String?
    var defaultTitle: String?
    var defaultIcon: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case defaultPopup = "default_popup"
        case defaultTitle = "default_title"
        case defaultIcon = "default_icon"
    }
}

struct BackgroundConfig: Codable {
    var scripts: [String]?
    var serviceWorker: String?
    
    enum CodingKeys: String, CodingKey {
        case scripts
        case serviceWorker = "service_worker"
    }
}

