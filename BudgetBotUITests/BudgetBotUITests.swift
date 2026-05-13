import XCTest

final class BudgetBotUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-test-mode", "--ui-test-reset"]
        app.launch()
        return app
    }

    func test_tabBarIsVisible_andAllTabsExist() {
        let app = launchApp()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        for tab in ["Capture", "Activity", "Ask", "Accounts", "Analytics"] {
            XCTAssertTrue(
                app.tabBars.buttons[tab].exists,
                "Tab \(tab) should exist"
            )
        }
    }

    func test_captureTab_showsInputTiles() {
        let app = launchApp()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Capture"].tap()

        // The four input tiles are buttons in the LazyVGrid.
        XCTAssertTrue(app.buttons["Scan Receipt"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Camera"].exists)
        XCTAssertTrue(app.buttons["Add PDF"].exists)
    }

    func test_settings_reachableFromAccountsToolbar() {
        let app = launchApp()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Accounts"].tap()

        // Use the explicit identifier rather than the label.
        let settingsLink = app.buttons["settings.link"]
        XCTAssertTrue(settingsLink.waitForExistence(timeout: 3))
        settingsLink.tap()

        // Anchor on the always-visible top of Settings, not on any picker
        // that may have scrolled out of view as the screen grew.
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 5),
                      "Settings screen should reach the Sign out row at the top")
    }

    func test_accountsTab_showsEmptyStateAndAddButton() {
        let app = launchApp()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Accounts"].tap()

        // Avoid asserting on "Total in USD" or "Net Worth" — both vary across
        // locales and iOS section-header styles. The Add-account button is the
        // canonical proof we landed on the right screen.
        XCTAssertTrue(app.buttons["Add account"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Settings"].exists,
                      "Gear in accounts toolbar should reach Settings")
    }

    func test_askTab_showsSuggestedQuestions() {
        let app = launchApp()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Ask"].tap()

        XCTAssertTrue(app.staticTexts["Try:"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["Question"].exists)
    }

    func test_addAccount_endToEnd() {
        let app = launchApp()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Accounts"].tap()
        app.buttons["Add account"].tap()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))

        // Force focus reliably across simulator + hardware-keyboard combos.
        nameField.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        // Retry if focus didn't take.
        if app.keyboards.firstMatch.waitForExistence(timeout: 1) == false {
            nameField.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        nameField.typeText("Wallet")

        // The Save button title can collide with toolbar Save in other forms;
        // scope to the navigation bar of the modal.
        app.navigationBars["New account"].buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["Wallet"].waitForExistence(timeout: 3))
    }
}
