import Foundation

final class PermissionManager {
    private(set) var allowedFolders: [URL] = []

    func allow(_ url: URL) {
        guard !allowedFolders.contains(url) else { return }
        allowedFolders.append(url)
    }

    func revoke(_ url: URL) {
        allowedFolders.removeAll { $0 == url }
    }
}
