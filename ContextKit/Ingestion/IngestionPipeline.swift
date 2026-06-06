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

    func ingestScreenshot(imageData: Data, mimeType: String = "image/png", metadata: [String: String]) async throws -> Data {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:3847/ingest_screenshot")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ScreenshotIngestPayload(
                imageBase64: imageData.base64EncodedString(),
                mimeType: mimeType,
                metadata: metadata
            )
        )
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    func createScreenshotJob(imageData: Data, mimeType: String = "image/png", metadata: [String: String]) async throws -> ScreenshotJob {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:3847/screenshot_jobs")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ScreenshotIngestPayload(
                imageBase64: imageData.base64EncodedString(),
                mimeType: mimeType,
                metadata: metadata
            )
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data)
        return try JSONDecoder().decode(ScreenshotJob.self, from: data)
    }

    func fetchScreenshotJob(id: String) async throws -> ScreenshotJob {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:3847/screenshot_jobs/\(id)")!)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data)
        return try JSONDecoder().decode(ScreenshotJob.self, from: data)
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard 200..<300 ~= http.statusCode else {
            if let error = try? JSONDecoder().decode(ServerError.self, from: data) {
                throw ScreenshotJobError.server(error.detail)
            }
            throw URLError(.badServerResponse)
        }
    }
}

enum ScreenshotJobStatus: String, Decodable {
    case processing
    case completed
    case failed
}

struct ScreenshotJob: Decodable {
    let id: String
    let status: ScreenshotJobStatus
    let result: ScreenshotJobResult?
    let error: String?
}

struct ScreenshotJobResult: Decodable {
    let collection: String
    let metadata: [String: String]
}

enum ScreenshotJobError: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case .server(let message):
            return message
        }
    }
}

private struct ServerError: Decodable {
    let detail: String
}

private struct IngestPayload: Encodable {
    let text: String
    let collection: String
    let metadata: [String: String]
}

private struct ScreenshotIngestPayload: Encodable {
    let imageBase64: String
    let mimeType: String
    let metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case imageBase64 = "image_base64"
        case mimeType = "mime_type"
        case metadata
    }
}
