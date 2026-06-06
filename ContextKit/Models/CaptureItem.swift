import Foundation

struct CaptureItem: Identifiable {
    let id = UUID()
    let title: String
    let summary: String
    let source: String
    let createdAt = Date()
}
