import Foundation

struct ConnectedClient: Identifiable {
    enum Status: String {
        case connected = "Connected"
        case disconnected = "Disconnected"
    }

    let id = UUID()
    let name: String
    var status: Status
}
