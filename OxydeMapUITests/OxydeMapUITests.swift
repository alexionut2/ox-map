import XCTest

/// Smoke tests for the main flows. They run on the simulator in CI with a fresh install
/// state (`-uiTestingReset`) and don't depend on network results.
final class OxydeMapUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestingReset"]
        addUIInterruptionMonitor(withDescription: "Location") { alert in
            for label in ["Allow While Using App", "Allow Once", "Don’t Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap(); return true
            }
            return false
        }
        app.launch()
    }

    private func finishOnboarding() {
        let start = app.buttons["onboarding.start"]
        guard start.waitForExistence(timeout: 5) else { return }
        start.tap()
        app.buttons["Continue"].firstMatch.tap()
        if app.buttons["Not Now"].waitForExistence(timeout: 2) { app.buttons["Not Now"].tap() }
        else { app.buttons["Continue"].firstMatch.tap() }
        let finish = app.buttons["onboarding.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        finish.tap()
    }

    func testOnboardingReachesMap() {
        finishOnboarding()
        XCTAssertTrue(app.buttons["main.search"].waitForExistence(timeout: 5))
    }

    func testSwitchThemeInMapStudio() {
        finishOnboarding()
        app.buttons["main.studio"].tap()
        let classic = app.buttons["studio.theme.oxyde.classic"]
        XCTAssertTrue(classic.waitForExistence(timeout: 5))
        classic.tap()
        let apply = app.buttons["Apply Oxyde Classic"]
        if apply.waitForExistence(timeout: 3) { apply.tap() }
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["main.search"].waitForExistence(timeout: 3))
    }

    func testDiagnosticsOpensFromSettings() {
        finishOnboarding()
        app.buttons["main.settings"].tap()
        let diagnostics = app.buttons["settings.diagnostics"]
        if !diagnostics.waitForExistence(timeout: 3) { app.swipeUp() }
        diagnostics.tap()
        XCTAssertTrue(app.navigationBars["Diagnostics"].waitForExistence(timeout: 3))
    }
}
