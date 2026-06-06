import Foundation

final class AccessLoggerClient {
    func fetch(token: String) async throws -> [AccessLogEntry] {
        var components = URLComponents(string: "http://127.0.0.1:3847/access-log")!
        components.queryItems = [URLQueryItem(name: "limit", value: "25")]
        var request = URLRequest(url: components.url!)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let rows = try JSONDecoder().decode([AccessLogRow].self, from: data)
        return rows.map { AccessLogEntry(client: $0.client, action: $0.tool, createdAt: ISO8601DateFormatter().date(from: $0.timestamp) ?? Date()) }
    }
}

private struct AccessLogRow: Decodable {
    let timestamp: String
    let client: String
    let tool: String
}
