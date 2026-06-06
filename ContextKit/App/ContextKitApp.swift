import SwiftUI

@main
struct ContextKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            OnboardingView()
        }
        Window("Memory Map", id: "memory-viewer") {
            MemoryViewerView()
        }
        .windowResizability(.contentSize)
    }
}
