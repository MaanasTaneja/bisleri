import SwiftUI

struct OnboardingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("ContextKit").font(.title)
            Text("Choose folders, connect clients, and keep the local server off until you need it.")
                .foregroundStyle(.secondary)
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()))
            } label: {
                Label("Choose Allowed Folders", systemImage: "folder.badge.plus")
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
