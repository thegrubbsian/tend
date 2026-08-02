import XCTest

final class AlmanacShellUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testColdLaunchShowsTodaySelectedWithoutNativeTabBar() {
    let app = launchFreshApp()
    let todayTab = app.buttons["shell.tab.today"]
    let habitsTab = app.buttons["shell.tab.habits"]

    XCTAssertTrue(app.otherElements["shell.destination.today"].waitForExistence(timeout: 5))
    XCTAssertTrue(todayTab.exists)
    XCTAssertEqual(todayTab.label, "Today")
    XCTAssertTrue(todayTab.isSelected)
    XCTAssertTrue(habitsTab.exists)
    XCTAssertEqual(habitsTab.label, "Habits")
    XCTAssertFalse(habitsTab.isSelected)
    XCTAssertEqual(app.tabBars.count, 0)
  }

  @MainActor
  func testTappingHabitsSwitchesDestinationAndSelectedState() {
    let app = launchFreshApp()
    let todayTab = app.buttons["shell.tab.today"]
    let habitsTab = app.buttons["shell.tab.habits"]

    XCTAssertTrue(todayTab.waitForExistence(timeout: 5))
    habitsTab.tap()

    XCTAssertTrue(app.otherElements["shell.destination.habits"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.otherElements["shell.destination.today"].exists)
    XCTAssertFalse(todayTab.isSelected)
    XCTAssertTrue(habitsTab.isSelected)
  }

  @MainActor
  func testBackgroundPreservesHabitsAndRelaunchRestoresToday() {
    let app = launchFreshApp()
    let todayTab = app.buttons["shell.tab.today"]
    let habitsTab = app.buttons["shell.tab.habits"]

    XCTAssertTrue(todayTab.waitForExistence(timeout: 5))
    habitsTab.tap()
    XCTAssertTrue(app.otherElements["shell.destination.habits"].waitForExistence(timeout: 5))

    XCUIDevice.shared.press(.home)
    app.activate()

    XCTAssertTrue(app.otherElements["shell.destination.habits"].waitForExistence(timeout: 5))
    XCTAssertTrue(habitsTab.isSelected)

    app.terminate()
    app.launch()

    XCTAssertTrue(app.otherElements["shell.destination.today"].waitForExistence(timeout: 5))
    XCTAssertTrue(todayTab.isSelected)
    XCTAssertFalse(habitsTab.isSelected)
  }

  @MainActor
  func testAllHabitsCreateEditArchiveReactivateAndDeleteJourney() {
    let app = launchFreshApp()
    let habitsTab = app.buttons["shell.tab.habits"]
    XCTAssertTrue(habitsTab.waitForExistence(timeout: 5))
    habitsTab.tap()
    XCTAssertTrue(app.buttons["habits.add"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Plant your first habit"].waitForExistence(timeout: 5))

    let originalName = "Smoke garden \(UUID().uuidString.prefix(6))"
    let editedName = "\(originalName) tended"

    app.buttons["habits.add"].tap()
    let nameField = app.textFields["Habit name"]
    XCTAssertTrue(nameField.waitForExistence(timeout: 5))
    nameField.tap()
    nameField.typeText(originalName)
    app.buttons["Save"].tap()

    var row = habitRow(named: originalName, in: app)
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    recordScreenshot(named: "All Habits — active", of: app)

    row.swipeLeft()
    XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 2))
    app.buttons["Edit"].tap()
    XCTAssertTrue(app.staticTexts["Edit habit"].waitForExistence(timeout: 5))
    let editNameField = app.textFields["Habit name"]
    editNameField.tap(withNumberOfTaps: 3, numberOfTouches: 1)
    editNameField.typeText(editedName)
    app.buttons["Save"].tap()

    row = habitRow(named: editedName, in: app)
    XCTAssertTrue(row.waitForExistence(timeout: 5))

    row.swipeLeft()
    XCTAssertTrue(app.buttons["Archive"].waitForExistence(timeout: 2))
    app.buttons["Archive"].tap()
    row = habitRow(named: editedName, in: app)
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    XCTAssertTrue((row.value as? String)?.contains("Inactive") == true)
    recordScreenshot(named: "All Habits — inactive", of: app)

    row.swipeLeft()
    XCTAssertTrue(app.buttons["Reactivate"].waitForExistence(timeout: 2))
    app.buttons["Reactivate"].tap()
    row = habitRow(named: editedName, in: app)
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    XCTAssertTrue((row.value as? String)?.contains("Active") == true)

    row.swipeLeft()
    XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 2))
    app.buttons["Delete"].tap()
    XCTAssertTrue(app.staticTexts["Delete \(editedName)?"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "This can't be undone.")
    ).firstMatch.exists)
    recordScreenshot(named: "All Habits — delete confirmation", of: app)
    app.buttons["Delete permanently"].tap()

    XCTAssertFalse(habitRow(named: editedName, in: app).waitForExistence(timeout: 2))
  }

  @MainActor
  private func recordScreenshot(named name: String, of app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  private func habitRow(named name: String, in app: XCUIApplication) -> XCUIElement {
    app.otherElements.matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND label == %@",
        "habits.row.",
        name
      )
    ).firstMatch
  }

  @MainActor
  private func launchFreshApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-tend-ui-testing"]
    app.terminate()
    app.launch()
    return app
  }
}
