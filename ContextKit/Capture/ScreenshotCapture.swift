enum ScreenshotCapture {
    @MainActor
    static func captureAndIngest(state: AppState) async {
        state.captureScreenshot()
    }
}
