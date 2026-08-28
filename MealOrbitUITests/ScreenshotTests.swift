import XCTest

@MainActor
final class ScreenshotTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
    }

    func testCaptureKeyScreens() {
        if app.buttons["Skip with defaults"].firstMatch.waitForExistence(timeout: 6) {
            ShotIO.save("09-onboarding")
            app.buttons["Skip with defaults"].firstMatch.tap()
        }
        _ = app.staticTexts["Today's burn"].firstMatch.waitForExistence(timeout: 12)
            || tap("Command Deck")
        pause(2.2)
        ShotIO.save("01-today")

        for _ in 0..<4 { app.swipeUp(); pause(0.2) }
        if !tap("Sweep catalog", timeout: 3) {
            openRoute("Catalog Sweep")
        }
        pause(0.4)
        tap("Try Apogee Eggs")
        _ = app.staticTexts["Apogee Eggs"].waitForExistence(timeout: 10)
            || tapContaining("Eggs")
        ShotIO.save("02-search")

        tapContaining("Eggs")
        pause(0.6)
        ShotIO.save("03-detail")
        tap("Lock into a window")
        pause(0.5)
        ShotIO.save("04-assign")
        tap("Confirm lock")
        pause(1.0)

        openRoute("Command Deck")
        pause(0.5)
        ShotIO.save("01-today")

        openRoute("Burn Log")
        pause(0.5)
        ShotIO.save("05-daylog")

        openRoute("Fourteen-Day Horizon")
        pause(0.6)
        ShotIO.save("06-plan")

        openRoute("Acquisition List")
        pause(0.5)
        ShotIO.save("07-wish")

        openRoute("Mass Targets")
        pause(0.5)
        ShotIO.save("08-goals")

        openRoute("Telemetry Scan")
        pause(0.6)
        ShotIO.save("10-scan")
    }

    func openRoute(_ title: String) {
        if tap(title, timeout: 1.5) { return }
        revealSidebar()
        _ = tap(title, timeout: 3)
    }

    func revealSidebar() {
        if tap("Show Sidebar", timeout: 1) { return }
        if tap("Toggle Sidebar", timeout: 0.6) { return }
        let navButton = app.navigationBars.buttons.firstMatch
        if navButton.exists { navButton.tap(); pause(0.3) }
    }

    @discardableResult
    func tap(_ label: String, timeout: TimeInterval = 3) -> Bool {
        let button = app.buttons[label].firstMatch
        guard button.waitForExistence(timeout: timeout) else { return false }
        let frame = button.frame
        let bounds = app.frame
        guard frame.height > 0, frame.minY >= 0, frame.maxY <= bounds.maxY + 1 else { return false }
        button.tap()
        return true
    }

    @discardableResult
    func tapContaining(_ token: String) -> Bool {
        let hit = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", token))
            .firstMatch
        if hit.waitForExistence(timeout: 5) { hit.tap(); return true }
        return false
    }

    func typeField(_ label: String, _ text: String) {
        let field = app.textFields[label].firstMatch
        if field.waitForExistence(timeout: 4) {
            field.tap()
            field.typeText(text)
            pause(0.8)
        }
    }

    func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}

enum ShotIO {
    @MainActor
    static func save(_ name: String) {
        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? ""
        let idiom = device.localizedCaseInsensitiveContains("iPad") ? "ipad" : "iphone"
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("screenshots", isDirectory: true)
            .appendingPathComponent(idiom, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
