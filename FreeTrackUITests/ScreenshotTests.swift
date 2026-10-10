import XCTest

/// Walks every screen in demo mode and saves a PNG per screen.
/// Run on CI with `TEST_RUNNER_SCREENSHOT_DIR=<dir>`; the PNGs also land in the .xcresult as attachments.
final class ScreenshotTests: XCTestCase {
    private var outputDirectory: URL? {
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty else { return nil }
        return URL(fileURLWithPath: dir, isDirectory: true)
    }

    override func setUpWithError() throws {
        continueAfterFailure = true
        if let outputDirectory {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        }
    }

    func testCaptureAllScreens() throws {
        capture("01-onboarding", arguments: ["--show-onboarding"])
        capture("02-today")
        capture("03-add-menu", arguments: ["--open", "menu"])
        capture("04-snap", arguments: ["--open", "snap"])
        capture("05-scan", arguments: ["--open", "scan"])
        capture("06-search", arguments: ["--open", "search"])
        capture("07-quick-add", arguments: ["--open", "quickAdd"])
        capture("08-history", tab: "History")
        capture("09-settings", tab: "Settings")
        capture("10-today-dark", arguments: ["--dark"])
        capture("11-history-dark", arguments: ["--dark"], tab: "History")
        capture("12-add-menu-dark", arguments: ["--dark", "--open", "menu"])
    }

    // MARK: - Helpers

    private func capture(_ name: String, arguments: [String] = [], tab: String? = nil, settle: TimeInterval = 2.5) {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + arguments
        app.launch()

        if let tab {
            let button = app.tabBars.buttons[tab]
            if button.waitForExistence(timeout: 5) { button.tap() }
        }
        // Let springs, async loads and chart animations finish.
        Thread.sleep(forTimeInterval: settle)

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        if let outputDirectory {
            let url = outputDirectory.appendingPathComponent("\(name).png")
            do {
                try screenshot.pngRepresentation.write(to: url, options: .atomic)
            } catch {
                XCTFail("Could not write \(url.path): \(error)")
            }
        }
        app.terminate()
    }
}
