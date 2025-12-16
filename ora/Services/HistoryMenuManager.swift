import Foundation
import os.log
import SwiftData

private let logger = Logger(subsystem: "eu.flareapps.prism", category: "HistoryMenuManager")

@MainActor
class HistoryMenuManager: ObservableObject {
    static let shared = HistoryMenuManager()
    
    @Published var recentHistory: [History] = []
    
    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?
    private var currentContainerId: UUID?
    
    private init() {}
    
    func configure(container: ModelContainer, context: ModelContext, containerId: UUID? = nil) {
        self.modelContainer = container
        self.modelContext = context
        self.currentContainerId = containerId
        // Only refresh if we have a valid containerId
        if containerId != nil {
            refreshRecentHistory()
        }
    }
    
    func updateContainer(_ containerId: UUID?) {
        guard let containerId = containerId else {
            recentHistory = []
            return
        }
        self.currentContainerId = containerId
        refreshRecentHistory()
    }
    
    func refreshRecentHistory() {
        guard let modelContext = modelContext,
              let containerId = currentContainerId else {
            recentHistory = []
            return
        }
        
        let descriptor = FetchDescriptor<History>(
            predicate: #Predicate { history in
                history.container?.id == containerId
            },
            sortBy: [SortDescriptor(\.lastAccessedAt, order: .reverse)]
        )
        
        do {
            let allHistory = try modelContext.fetch(descriptor)
            recentHistory = Array(allHistory.prefix(10))
        } catch {
            logger.error("Error fetching recent history: \(error.localizedDescription)")
            recentHistory = []
        }
    }
    
    func getRecentHistory(limit: Int = 10) -> [History] {
        return Array(recentHistory.prefix(limit))
    }
}

