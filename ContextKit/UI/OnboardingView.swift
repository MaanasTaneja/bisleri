import SwiftUI

struct OnboardingView: View {
    private let defaultFolders = ["Documents", "Desktop", "Downloads"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("ContextKit").font(.title)
            Text("Click the brain icon in the menu bar to capture, search, and inspect your memory.")
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Default folders").font(.subheadline).foregroundStyle(.secondary)
                ForEach(defaultFolders, id: \.self) { name in
                    Label(name, systemImage: "folder")
                        .font(.callout)
                }
                Text("Custom folder permissions are coming soon.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
