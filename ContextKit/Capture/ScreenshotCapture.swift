import AppKit

enum ScreenshotCapture {
    @MainActor
    static func captureAndIngest(state: AppState) async {
        guard let image = ScreenCaptureManager.captureMainDisplay(),
              let data = image.tiffRepresentation else {
            return
        }
        let processor = OCRProcessor()
        if let result = try? await processor.process(imageData: data) {
            _ = try? await state.ingestion.ingest(
                text: result.text,
                collection: result.collection,
                metadata: ["summary": result.summary, "source": "screenshot"]
            )
            state.recentItems.insert(CaptureItem(title: "Screenshot", summary: result.summary, source: "screenshot"), at: 0)
        }
    }
}
