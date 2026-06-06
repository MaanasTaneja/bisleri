import SwiftUI

struct OnboardingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("ContextKit").font(.title)
            Text("Paste your OpenAI API key in the menu bar popover, start the local server, then capture screenshots or clipboard text.")
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
