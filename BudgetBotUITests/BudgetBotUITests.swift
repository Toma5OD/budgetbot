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
        for tab in ["Home", "Activity", "Capture", "Analytics", "Ask"] {
            XCTAssertTrue(
                app.tabBars.buttons[tab].exists,
                "Tab \(tab) should exist"
            )
        }
    }

    func test_home_isFirstTab_andShowsGreeting() {
        let app = launchApp()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        // Home tab should already be selected on launch. Greeting starts with "Good ".
        let predicate = NSPredicate(format: "label BEGINSWITH 'Good'")
        XCTAssertTrue(app.staticTexts.element(matching: predicate).waitForExistence(timeout: 3))
    }

    func test_headerToolbar_hasProfileBellAndSettings_onEveryTab() {
        let app = launchApp()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))

        for tab in ["Home", "Activity", "Analytics", "Ask"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.buttons["Profile"].waitForExistence(timeout: 3),
                          "Profile button should exist on \(tab) tab")
            XCTAssertTrue(app.buttons["Notifications"].exists,
                          "Notifications bell should exist on \(tab) tab")
            XCTAssertTrue(app.buttons["Settings"].exists,
                          "Settings gear should exist on \(tab) tab")
        }
    }

    func test_settings_reachableFromAnyTabsToolbar() {
        let app = launchApp()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        // Settings opens as a sheet. Sign out row is always visible at the top
        // of the Account section.
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 5))
    }

    func test_notificationsCenter_opensFromBell() {
        let app = launchApp()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.buttons["Notifications"].tap()
        // Empty state title or the navigation bar title — either is fine.
        let appeared = app.staticTexts["You're all caught up"].waitForExistence(timeout: 3)
            || app.navigationBars["Notifications"].waitForExistence(timeout: 3)
        XCTAssertTrue(appeared, "Notifications sheet should open")
    }

    func test_captureTab_showsInputTiles() {
        let app = launchApp()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Capture"].tap()

        XCTAssertTrue(app.buttons["Scan Receipt"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Camera"].exists)
        XCTAssertTrue(app.buttons["Add PDF"].exists)
    }

    func test_askTab_showsSuggestedQuestions() {
        let app = launchApp()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Ask"].tap()

        XCTAssertTrue(app.staticTexts["Try:"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["Question"].exists)
    }

    func test_addAccount_fromHomeStrip() {
        let app = launchApp()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        // Home is the default tab on launch.

        // Add-account button in the Accounts strip header on Home.
        let addButton = app.buttons["home.addAccount"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 3))
        addButton.tap()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        if app.keyboards.firstMatch.waitForExistence(timeout: 1) == false {
            nameField.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        nameField.typeText("Wallet")

        app.navigationBars["New account"].buttons["Save"].tap()

        // Account should now appear as a tile on Home.
        XCTAssertTrue(app.staticTexts["Wallet"].waitForExistence(timeout: 3))
    }
}
