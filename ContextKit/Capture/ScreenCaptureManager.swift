import AppKit

enum ScreenCaptureManager {
    static func captureMainDisplay() -> NSImage? {
        guard let displayID = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let cgImage = CGDisplayCreateImage(displayID) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: .zero)
    }
}
