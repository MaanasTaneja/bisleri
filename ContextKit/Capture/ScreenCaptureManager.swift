import AppKit

enum ScreenCaptureManager {
    static func captureActiveWindow() -> NSImage? {
        let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []

        // Find the first window that isn't from our own process and is in the normal window layer (0)
        let ownPID = NSRunningApplication.current.processIdentifier
        
        for dict in windowList {
            guard let windowLayer = dict[kCGWindowLayer as String] as? Int,
                  windowLayer == 0,
                  let windowPID = dict[kCGWindowOwnerPID as String] as? Int,
                  windowPID != ownPID,
                  let windowID = dict[kCGWindowNumber as String] as? CGWindowID else {
                continue
            }
            
            // Capture this specific window
            if let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, .boundsIgnoreFraming) {
                return NSImage(cgImage: cgImage, size: .zero)
            }
        }
        
        // Fallback to full display if no specific window is found
        guard let displayID = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let cgImage = CGDisplayCreateImage(displayID) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: .zero)
    }
}
