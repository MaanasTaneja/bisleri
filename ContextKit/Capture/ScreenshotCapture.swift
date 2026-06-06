import AppKit

enum ScreenshotCapture {
    @MainActor
    static func captureAndIngest(state: AppState) async {
        guard let image = ScreenCaptureManager.captureMainDisplay(),
              let data = image.pngData() else {
            return
        }
        do {
            _ = try await state.ingestion.ingestScreenshot(
                imageData: data,
                metadata: ["source": "screenshot"]
            )
            state.recentItems.insert(CaptureItem(title: "Screenshot", summary: "Screenshot saved to memory", source: "screenshot"), at: 0)
        } catch {
            NSLog("ScreenshotCapture: failed to ingest screenshot: \(error)")
        }
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
