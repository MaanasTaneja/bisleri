import Foundation

struct AccessLogEntry: Identifiable {
    let id = UUID()
    let client: String
    let action: String
    let createdAt: Date

    var relativeTime: String {
        RelativeDateTimeFormatter().localizedString(for: createdAt, relativeTo: Date())
    }
}
