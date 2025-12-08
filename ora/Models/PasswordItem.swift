import Foundation
import SwiftData

@Model
final class PasswordItem {
    var id: UUID
    var siteName: String
    var urlString: String
    var username: String
    var keychainID: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?

    var url: URL? {
        URL(string: urlString)
    }

    init(
        id: UUID = UUID(),
        siteName: String,
        urlString: String,
        username: String,
        keychainID: String,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.siteName = siteName
        self.urlString = urlString
        self.username = username
        self.keychainID = keychainID
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
    }
}




