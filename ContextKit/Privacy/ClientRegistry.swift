import Foundation

final class ClientRegistry {
    func token(for client: ConnectedClient) -> String {
        let key = "contextkit.token.\(client.name)"
        if let existing = KeychainStore.string(for: key) {
            return existing
        }
        let token = UUID().uuidString
        KeychainStore.set(token, for: key)
        return token
    }

    func revoke(_ client: ConnectedClient) {
        KeychainStore.delete("contextkit.token.\(client.name)")
    }
}
