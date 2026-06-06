import Foundation

enum TextExtractor {
    static func extract(from url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
