import Foundation
import PDFKit

enum PDFParser {
    static func extractText(from url: URL) -> String {
        guard let document = PDFDocument(url: url) else { return "" }
        return (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
    }
}
