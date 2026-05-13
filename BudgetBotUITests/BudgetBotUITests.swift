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

    func test_settings_reachableFromAccountsToolbar_andShowsAIModelPicker() {
        let app = launchApp()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Accounts"].tap()

        // Use the explicit identifier rather than the label — NavigationLink's
        // button representation differs between iOS 18 and 26.
        let settingsLink = app.buttons["settings.link"]
        XCTAssertTrue(settingsLink.waitForExistence(timeout: 3))
        settingsLink.tap()

        // Avoid the "AI model" section header (uppercased on iOS 18). The
        // Picker's label "Model" and the always-present "Sign out" button
        // are stable across versions.
        XCTAssertTrue(app.staticTexts["Model"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Sign out"].exists)
    }

    func test_accountsTab_showsEmptyStateAndAddButton() {
        let app = launchApp()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Accounts"].tap()

        // Avoid asserting on the "Net Worth" Section header — iOS uppercases
        // section headers in some styles/versions ("NET WORTH"), so match the
        // row body text instead, which is case-stable across iOS releases.
        XCTAssertTrue(app.staticTexts["Total in USD"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Add account"].exists)
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
