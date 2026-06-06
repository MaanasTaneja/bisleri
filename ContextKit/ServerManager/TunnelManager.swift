import Foundation

final class TunnelManager {
    private var process: Process?

    func start(config: TunnelConfig) {
        guard process == nil else { return }
        let process = Process()
        process.executableURL = Bundle.main.url(forResource: "tunnel-client", withExtension: nil)
        process.arguments = ["start", "--tunnel-id", config.tunnelID, "--target", config.localURL.absoluteString]
        try? process.run()
        self.process = process
    }

    func stop() {
        process?.terminate()
        process = nil
    }
}
