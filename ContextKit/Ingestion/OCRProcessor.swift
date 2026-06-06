import Foundation

struct OCRResult: Decodable {
    let text: String
    let collection: String
    let summary: String
}

final class OCRProcessor {
    func process(imageData: Data) async throws -> OCRResult {
        if let apiKey = KeychainStore.string(for: "OPENAI_API_KEY"), !apiKey.isEmpty {
            return try await processWithOpenAI(imageData: imageData, apiKey: apiKey)
        }
        return OCRResult(text: "Screenshot captured. OCR not configured.", collection: "misc", summary: "Screenshot captured without OCR")
    }

    private func processWithOpenAI(imageData: Data, apiKey: String) async throws -> OCRResult {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let base64 = imageData.base64EncodedString()
        let prompt = """
        Extract visible text from this screenshot, classify it as messages, browser, filesystem, or misc, and return compact JSON with text, collection, and summary.
        """
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "input": [[
                "role": "user",
                "content": [
                    ["type": "input_text", "text": prompt],
                    ["type": "input_image", "image_url": "data:image/tiff;base64,\(base64)"]
                ]
            ]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try ResponseJSONExtractor.decodeOCRResult(from: data)
    }
}
