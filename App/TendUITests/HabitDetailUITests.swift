import XCTest

final class HabitDetailUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testRosterRowPresentsFullScreenDetailAndBackReturnsToHabits() {
    let app = launch()
    let habitsTab = app.buttons["shell.tab.habits"]
    XCTAssertTrue(habitsTab.waitForExistence(timeout: 5))
    habitsTab.tap()

    let dailyRow = habitRow(named: "Daily garden", in: app)
    XCTAssertTrue(dailyRow.waitForExistence(timeout: 5))
    dailyRow.tap()

    let title = element("habitDetail.title", in: app)
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    XCTAssertEqual(title.label, "Daily garden")
    XCTAssertFalse(app.buttons["shell.tab.today"].isHittable)
    XCTAssertFalse(app.buttons["shell.tab.habits"].isHittable)

    element("habitDetail.back", in: app).tap()

    XCTAssertTrue(element("shell.destination.habits", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(habitRow(named: "Daily garden", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["shell.tab.habits"].isSelected)
    XCTAssertTrue(app.buttons["shell.tab.habits"].isHittable)

    var weeklyRow = habitRow(named: "Weekly field notes", in: app)
    XCTAssertTrue(weeklyRow.waitForExistence(timeout: 5))
    weeklyRow.press(forDuration: 1)
    XCTAssertTrue(app.buttons["Archive"].waitForExistence(timeout: 2))
    app.buttons["Archive"].tap()

    XCTAssertFalse(element("habitDetail.title", in: app).waitForExistence(timeout: 2))
    weeklyRow = habitRow(named: "Weekly field notes", in: app)
    XCTAssertTrue(weeklyRow.waitForExistence(timeout: 5))
    XCTAssertTrue((weeklyRow.value as? String)?.contains("Inactive") == true)

    let reopenedDailyRow = habitRow(named: "Daily garden", in: app)
    XCTAssertTrue(reopenedDailyRow.waitForExistence(timeout: 5))
    reopenedDailyRow.tap()

    let reopenedTitle = element("habitDetail.title", in: app)
    XCTAssertTrue(reopenedTitle.waitForExistence(timeout: 5))
    XCTAssertEqual(reopenedTitle.label, "Daily garden")
  }

  @MainActor
  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }

  @MainActor
  private func habitRow(named name: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND label == %@",
        "habits.row.",
        name
      )
    ).firstMatch
  }

  @MainActor
  private func launch() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["TZ"] = "America/Los_Angeles"
    app.launchArguments = [
      "-tend-ui-testing",
      "-tend-ui-test-store",
      "HabitDetailUITests-\(UUID().uuidString)",
      "-tend-ui-test-reset",
      "-tend-ui-test-fixture",
      "habit-detail",
    ]
    app.terminate()
    app.launch()
    return app
  }
}
