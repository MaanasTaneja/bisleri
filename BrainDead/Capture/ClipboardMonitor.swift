import AppKit

enum ClipboardMonitor {
    static func currentText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
}
