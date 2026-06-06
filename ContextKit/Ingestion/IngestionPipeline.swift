import Foundation

final class IngestionPipeline {
    var endpoint = URL(string: "http://127.0.0.1:3847/ingest")!
    var token = "dev-token"

    func ingest(text: String, collection: String, metadata: [String: String]) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(IngestPayload(text: text, collection: collection, metadata: metadata))
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }
}

private struct IngestPayload: Encodable {
    let text: String
    let collection: String
    let metadata: [String: String]
}
