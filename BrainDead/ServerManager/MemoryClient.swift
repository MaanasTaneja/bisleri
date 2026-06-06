import Foundation

final class MemoryClient {
    private let baseURL: URL
    private let token: String

    init(port: Int = 3847, token: String = "dev-token") {
        self.baseURL = URL(string: "http://127.0.0.1:\(port)")!
        self.token = token
    }

    func fetchMemory(collection: String? = nil, limit: Int = 200) async throws -> [MemoryItem] {
        var arguments: [String: Any] = ["limit": limit]
        if let collection { arguments["collection"] = collection }
        let body: [String: Any] = ["arguments": arguments]

        var request = URLRequest(url: baseURL.appendingPathComponent("tools/list_memory"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 5

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([MemoryItem].self, from: data)
    }

    func fetchCollections() async throws -> [String] {
        var request = URLRequest(url: baseURL.appendingPathComponent("collections"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([String].self, from: data)
    }

    func createCollection(name: String) async throws -> CollectionCreateResponse {
        let body: [String: Any] = ["arguments": ["name": name]]

        var request = URLRequest(url: baseURL.appendingPathComponent("collections"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 5

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            if let error = try? JSONDecoder().decode(CollectionCreateError.self, from: data) {
                throw MemoryClientError.server(error.detail)
            }
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(CollectionCreateResponse.self, from: data)
    }
}

enum MemoryClientError: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case .server(let message):
            return message
        }
    }
}

struct CollectionCreateResponse: Decodable {
    let name: String
    let collections: [String]
}

private struct CollectionCreateError: Decodable {
    let detail: String
}
