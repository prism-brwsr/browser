import Foundation

@MainActor
struct HistoryDateFormatter {
    static func formatTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()

        // For today, show relative time
        if calendar.isDateInToday(date) {
            let timeInterval = now.timeIntervalSince(date)
            let minutes = Int(timeInterval / 60)
            let hours = Int(timeInterval / 3600)

            if minutes < 1 {
                return "Just now"
            } else if minutes < 60 {
                return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
            } else if hours < 24 {
                return "\(hours) hour\(hours == 1 ? "" : "s") ago"
            }
        }

        // For same day (yesterday), show time only
        if calendar.isDateInYesterday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }

        // For this week, show day name and time
        let daysAgo = calendar.dateComponents([.day], from: date, to: now).day ?? 0
        if daysAgo <= 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, h:mm a"
            return formatter.string(from: date)
        }

        // For this month, show date and time
        let monthsAgo = calendar.dateComponents([.month], from: date, to: now).month ?? 0
        if monthsAgo == 0 {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, h:mm a"
            return formatter.string(from: date)
        }

        // For older entries, show full date and time
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}




