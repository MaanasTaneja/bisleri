import Foundation

enum MetadataExtractor {
    static func metadata(for url: URL) -> [String: String] {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return [
            "path": url.path,
            "source": url.path,
            "modified_at": values?.contentModificationDate?.ISO8601Format() ?? "",
            "file_size": values?.fileSize.map(String.init) ?? ""
        ]
    }
}
