import Foundation
import os.log
import SwiftData

private let logger = Logger(subsystem: "eu.flareapps.prism", category: "HistoryManager")

// MARK: - History Section

enum HistorySection: String, CaseIterable {
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case older

    var displayName: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This Week"
        case .thisMonth: return "This Month"
        case .older: return "Older"
        }
    }

    var sortOrder: Int {
        switch self {
        case .today: return 0
        case .yesterday: return 1
        case .thisWeek: return 2
        case .thisMonth: return 3
        case .older: return 4
        }
    }
}

// MARK: - History Group

struct HistoryGroup: Identifiable {
    let id: UUID
    let section: HistorySection
    let items: [History]

    init(section: HistorySection, items: [History]) {
        self.id = UUID()
        self.section = section
        self.items = items
    }
}

@MainActor
class HistoryManager: ObservableObject {
    let modelContainer: ModelContainer
    let modelContext: ModelContext

    init(modelContainer: ModelContainer, modelContext: ModelContext) {
        self.modelContainer = modelContainer
        self.modelContext = modelContext
    }

    func record(
        title: String,
        url: URL,
        faviconURL: URL? = nil,
        faviconLocalFile: URL? = nil,
        container: TabContainer
    ) {
        let urlString = url.absoluteString

        // Check if a history record already exists for this URL
        let descriptor = FetchDescriptor<History>(
            predicate: #Predicate {
                $0.urlString == urlString
            },
            sortBy: [.init(\.lastAccessedAt, order: .reverse)]
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            existing.visitCount += 1
            existing.lastAccessedAt = Date() // update last visited time
            // Update title if it has changed and the new title is not empty or a domain name
            if !title.isEmpty && title != existing.title {
                // Only update if the new title seems like a real title (not just a domain)
                let urlHost = url.host ?? ""
                let cleanHost = urlHost.hasPrefix("www.") ? String(urlHost.dropFirst(4)) : urlHost
                // Update title if it's different from the domain name
                if title != urlHost && title != cleanHost {
                    existing.title = title
                }
            }
        } else {
            let now = Date()
            let defaultFaviconURL =
                URL(string: "https://www.google.com/s2/favicons?domain=\(url.host ?? "google.com")&sz=64")
            let fallbackURL = URL(fileURLWithPath: "")
            let resolvedFaviconURL = faviconURL ?? defaultFaviconURL ?? fallbackURL
            modelContext.insert(History(
                url: url,
                title: title,
                faviconURL: resolvedFaviconURL,
                faviconLocalFile: faviconLocalFile,
                createdAt: now,
                lastAccessedAt: now,
                visitCount: 1,
                container: container
            ))
        }

        try? modelContext.save()
        
        // Notify HistoryMenuManager to refresh
        Task { @MainActor in
            HistoryMenuManager.shared.refreshRecentHistory()
        }
    }

    func search(_ text: String, activeContainerId: UUID) -> [History] {
        let trimmedText = text.trimmingCharacters(in: .whitespaces)

        // Define the predicate for searching
        let predicate: Predicate<History>
        if trimmedText.isEmpty {
            // If the search text is empty, return all records
            predicate = #Predicate { _ in true }
        } else {
            // Case-insensitive substring search on url and title
            predicate = #Predicate { history in
                (history.urlString.localizedStandardContains(trimmedText) ||
                    history.title.localizedStandardContains(trimmedText)
                ) && history.container != nil && history.container!.id == activeContainerId
            }
        }

        // Create fetch descriptor with predicate and sorting
        let descriptor = FetchDescriptor<History>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.lastAccessedAt, order: .reverse)]
        )

        do {
            // Fetch matching history records
            return try modelContext.fetch(descriptor)
        } catch {
            logger.error("Error fetching history: \(error.localizedDescription)")
            return []
        }
    }

    func clearContainerHistory(_ container: TabContainer) {
        let containerId = container.id
        let descriptor = FetchDescriptor<History>(
            predicate: #Predicate { $0.container?.id == containerId }
        )

        do {
            let histories = try modelContext.fetch(descriptor)

            for history in histories {
                modelContext.delete(history)
            }

            try modelContext.save()
        } catch {
            logger.error("Failed to clear history for container \(container.id): \(error.localizedDescription)")
        }
    }

    // MARK: - History Grouping

    func getGroupedHistory(containerId: UUID, searchText: String = "") -> [HistoryGroup] {
        let trimmedText = searchText.trimmingCharacters(in: .whitespaces).lowercased()

        // Fetch all history for the container (filter by container only, do text search in memory)
        let descriptor = FetchDescriptor<History>(
            predicate: #Predicate { history in
                history.container?.id == containerId
            },
            sortBy: [SortDescriptor(\.lastAccessedAt, order: .reverse)]
        )

        let allHistories: [History]
        do {
            allHistories = try modelContext.fetch(descriptor)
        } catch {
            logger.error("Error fetching history for grouping: \(error.localizedDescription)")
            return []
        }

        // Filter by search text in memory (more reliable than SwiftData predicate)
        let filteredHistories: [History]
        if trimmedText.isEmpty {
            filteredHistories = allHistories
        } else {
            filteredHistories = allHistories.filter { history in
                history.urlString.lowercased().contains(trimmedText) ||
                history.title.lowercased().contains(trimmedText)
            }
        }

        // Group by date section
        var grouped: [HistorySection: [History]] = [:]

        for history in filteredHistories {
            let section = categorizeDate(history.lastAccessedAt)
            if grouped[section] == nil {
                grouped[section] = []
            }
            grouped[section]?.append(history)
        }

        // Convert to HistoryGroup array, sorted by section order
        let groups = HistorySection.allCases.compactMap { section -> HistoryGroup? in
            guard let items = grouped[section], !items.isEmpty else { return nil }
            return HistoryGroup(section: section, items: items)
        }

        return groups
    }

    private func categorizeDate(_ date: Date) -> HistorySection {
        let calendar = Calendar.current
        let now = Date()

        // Check if today
        if calendar.isDateInToday(date) {
            return .today
        }

        // Check if yesterday
        if calendar.isDateInYesterday(date) {
            return .yesterday
        }

        // Check if this week (last 7 days, excluding today and yesterday)
        let daysAgo = calendar.dateComponents([.day], from: date, to: now).day ?? 0
        if daysAgo <= 7 {
            return .thisWeek
        }

        // Check if this month
        let monthsAgo = calendar.dateComponents([.month], from: date, to: now).month ?? 0
        if monthsAgo == 0 {
            return .thisMonth
        }

        // Older
        return .older
    }
}
