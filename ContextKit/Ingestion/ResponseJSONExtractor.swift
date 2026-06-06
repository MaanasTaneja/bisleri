import Foundation

enum ResponseJSONExtractor {
    static func decodeOCRResult(from data: Data) throws -> OCRResult {
        if let direct = try? JSONDecoder().decode(OCRResult.self, from: data) {
            return direct
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["output_text"] as? String,
              let jsonData = text.data(using: .utf8) else {
            throw CocoaError(.coderInvalidValue)
        }
        return try JSONDecoder().decode(OCRResult.self, from: jsonData)
    }
}
