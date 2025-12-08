import AppKit
import Foundation
import SwiftData

struct PasswordImporter {
    struct CSVRow {
        let columns: [String]
    }

    // Chrome export headers are typically:
    // name, url, username, password, (optional extra columns)
    func importChromeCSV(from url: URL, into context: ModelContext) throws -> Int {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            return 0
        }

        let rows = parseCSV(content: content)
        guard !rows.isEmpty else { return 0 }

        // Skip header if it looks like one
        let startIndex: Int
        if let first = rows.first, first.columns.count >= 4,
           first.columns[1].lowercased().contains("url"),
           first.columns[2].lowercased().contains("user"),
           first.columns[3].lowercased().contains("pass")
        {
            startIndex = 1
        } else {
            startIndex = 0
        }

        var imported = 0
        for row in rows[startIndex...] {
            guard row.columns.count >= 4 else { continue }

            let name = row.columns[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let urlString = row.columns[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let username = row.columns[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let password = row.columns[3]

            guard !urlString.isEmpty, !username.isEmpty, !password.isEmpty else { continue }

            let siteName: String
            if !name.isEmpty {
                siteName = name
            } else if let host = URL(string: urlString)?.host {
                siteName = host
            } else {
                siteName = urlString
            }

            let normalizedURL = PasswordImporter.normalize(urlString: urlString)
            let now = Date()

            let predicate = #Predicate<PasswordItem> {
                $0.urlString == normalizedURL && $0.username == username
            }
            let descriptor = FetchDescriptor<PasswordItem>(predicate: predicate)
            let existing = (try? context.fetch(descriptor))?.first

            let item: PasswordItem
            if let existing {
                item = existing
                item.siteName = siteName
                item.updatedAt = now
            } else {
                let keychainID = UUID().uuidString
                item = PasswordItem(
                    siteName: siteName,
                    urlString: normalizedURL,
                    username: username,
                    keychainID: keychainID,
                    notes: nil,
                    createdAt: now,
                    updatedAt: now
                )
                context.insert(item)
            }

            try PasswordKeychain.savePassword(password, for: item.keychainID)
            imported += 1
        }

        if imported > 0 {
            try context.save()
        }

        return imported
    }

    // Very small CSV parser that supports quoted fields with commas and newlines.
    private func parseCSV(content: String) -> [CSVRow] {
        var rows: [CSVRow] = []
        var currentField = ""
        var currentRow: [String] = []
        var insideQuotes = false

        func finishField() {
            currentRow.append(currentField)
            currentField = ""
        }

        func finishRow() {
            if !currentRow.isEmpty || !currentField.isEmpty {
                finishField()
                rows.append(CSVRow(columns: currentRow))
                currentRow = []
            }
        }

        for char in content {
            switch char {
            case "\"":
                insideQuotes.toggle()
            case ",":
                if insideQuotes {
                    currentField.append(char)
                } else {
                    finishField()
                }
            case "\n", "\r\n":
                if insideQuotes {
                    currentField.append(char)
                } else {
                    finishRow()
                }
            default:
                currentField.append(char)
            }
        }

        // Final row if there is trailing data without newline
        if !currentField.isEmpty || !currentRow.isEmpty {
            finishField()
            rows.append(CSVRow(columns: currentRow))
        }

        return rows
    }

    static func normalize(urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url.absoluteString
        }

        if let url = URL(string: "https://\(trimmed)") {
            return url.absoluteString
        }

        return trimmed
    }
}




