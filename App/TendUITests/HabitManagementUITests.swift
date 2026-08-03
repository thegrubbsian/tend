import XCTest

final class HabitManagementUITests: XCTestCase {
  private let storeName = "HabitManagementUITests-owner-journey"

  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testCompleteFirstHabitOwnerJourney() {
    let app = launch(reset: true)

    XCTAssertTrue(app.otherElements["today.empty"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.staticTexts[
        "Tend is a quiet place to grow the habits you want to keep."
      ].exists)
    let plantHabitButton = app.buttons["today.plant-habit"]
    XCTAssertTrue(plantHabitButton.exists)
    XCTAssertEqual(plantHabitButton.label, "Plant a habit")
    recordScreenshot(named: "First launch Today", of: app)

    plantHabitButton.tap()
    XCTAssertTrue(app.staticTexts["New habit"].waitForExistence(timeout: 5))
    recordScreenshot(named: "New Habit", of: app)

    let nameField = app.textFields["Habit name"]
    let targetField = app.textFields["Target"]
    let unitField = app.textFields["Unit"]
    let saveButton = app.buttons["Save"]
    XCTAssertTrue(nameField.waitForExistence(timeout: 5))
    XCTAssertFalse(saveButton.isEnabled)

    replaceText(in: nameField, with: "")
    targetField.tap()
    XCTAssertTrue(
      staticText(containing: "Enter a habit name.", in: app).waitForExistence(timeout: 2))

    replaceText(in: targetField, with: "0")
    unitField.tap()
    XCTAssertTrue(
      staticText(
        containing: "Enter a whole number greater than zero.",
        in: app
      ).waitForExistence(timeout: 2)
    )
    XCTAssertFalse(saveButton.isEnabled)

    replaceText(in: targetField, with: "1")
    replaceText(in: unitField, with: "")
    nameField.tap()
    XCTAssertTrue(staticText(containing: "Enter a unit.", in: app).waitForExistence(timeout: 2))
    XCTAssertFalse(saveButton.isEnabled)

    replaceText(in: nameField, with: "Read deliberately")
    replaceText(in: unitField, with: "times")
    XCTAssertTrue(saveButton.isEnabled)
    saveButton.tap()

    XCTAssertFalse(app.otherElements["today.empty"].waitForExistence(timeout: 2))
    XCTAssertFalse(
      app.staticTexts[
        "Tend is a quiet place to grow the habits you want to keep."
      ].exists)
    XCTAssertTrue(app.otherElements["shell.destination.today"].exists)

    app.buttons["shell.tab.habits"].tap()
    XCTAssertTrue(app.buttons["habits.add"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["habits.add"].label, "New habit")
    app.buttons["habits.add"].tap()

    let weeklyNameField = app.textFields["Habit name"]
    let weeklyTargetField = app.textFields["Target"]
    let weeklyUnitField = app.textFields["Unit"]
    XCTAssertTrue(weeklyNameField.waitForExistence(timeout: 5))
    app.buttons["Weekly cadence"].tap()
    replaceText(in: weeklyNameField, with: "Write field notes")
    replaceText(in: weeklyTargetField, with: "2")
    replaceText(in: weeklyUnitField, with: "pages")
    app.buttons["Reminder, none"].tap()

    XCTAssertTrue(
      app.staticTexts[
        "Reminder warning. No reminder will fire until a day is pinned."
      ].waitForExistence(timeout: 2))
    XCTAssertTrue(app.buttons["Save"].isEnabled)
    recordScreenshot(named: "Weekly warning", of: app)

    app.buttons["Monday"].tap()
    app.buttons["Wednesday"].tap()
    XCTAssertTrue(app.buttons["Monday"].isSelected)
    XCTAssertTrue(app.buttons["Wednesday"].isSelected)
    XCTAssertFalse(
      app.staticTexts[
        "Reminder warning. No reminder will fire until a day is pinned."
      ].exists)
    app.buttons["Save"].tap()

    var dailyRow = habitRow(named: "Read deliberately", in: app)
    var weeklyRow = habitRow(named: "Write field notes", in: app)
    XCTAssertTrue(dailyRow.waitForExistence(timeout: 5))
    XCTAssertTrue(weeklyRow.waitForExistence(timeout: 5))
    assertValue(of: dailyRow, contains: ["1 time", "Daily", "0 days", "Active"])
    assertValue(
      of: weeklyRow,
      contains: ["2 pages", "Weekly", "Mon, Wed", "0 weeks", "Active"]
    )
    recordScreenshot(named: "All Habits", of: app)

    chooseRowAction("Edit", on: dailyRow, in: app)
    XCTAssertTrue(
      app.staticTexts[
        "Cadence, Daily, locked"
      ].waitForExistence(timeout: 5))
    XCTAssertTrue(
      staticText(
        containing: "Set at creation. To change cadence, archive this habit and plant a new one.",
        in: app
      ).exists)
    recordScreenshot(named: "Edit Habit", of: app)
    replaceText(in: app.textFields["Habit name"], with: "Read with care")
    replaceText(in: app.textFields["Target"], with: "3")
    replaceText(in: app.textFields["Unit"], with: "chapters")
    app.buttons["Reminder, none"].tap()
    app.buttons["Save"].tap()

    dailyRow = habitRow(named: "Read with care", in: app)
    XCTAssertTrue(dailyRow.waitForExistence(timeout: 5))
    assertValue(of: dailyRow, contains: ["3 chapters", "Daily", "0 days", "Active"])

    weeklyRow = habitRow(named: "Write field notes", in: app)
    chooseRowAction("Edit", on: weeklyRow, in: app)
    XCTAssertTrue(
      app.staticTexts[
        "Cadence, Weekly, locked"
      ].waitForExistence(timeout: 5))
    replaceText(in: app.textFields["Habit name"], with: "Write lasting field notes")
    replaceText(in: app.textFields["Target"], with: "4")
    replaceText(in: app.textFields["Unit"], with: "lines")
    if app.frame.width < 700 {
      app.swipeDown()
      XCTAssertFalse(app.keyboards.firstMatch.exists)
    }
    let mondayButton = app.buttons["Monday"]
    let fridayButton = app.buttons["Friday"]
    XCTAssertTrue(mondayButton.isSelected)
    XCTAssertFalse(fridayButton.isSelected)
    mondayButton.tap()
    XCTAssertFalse(mondayButton.isSelected)
    fridayButton.tap()
    XCTAssertTrue(fridayButton.isSelected)
    app.buttons["Clear"].tap()
    app.buttons["Save"].tap()

    weeklyRow = habitRow(named: "Write lasting field notes", in: app)
    XCTAssertTrue(weeklyRow.waitForExistence(timeout: 5))
    assertValue(
      of: weeklyRow,
      contains: ["4 lines", "Weekly", "Wed, Fri", "0 weeks", "Active"]
    )

    chooseRowAction("Archive", on: weeklyRow, in: app)
    weeklyRow = habitRow(named: "Write lasting field notes", in: app)
    XCTAssertTrue(weeklyRow.waitForExistence(timeout: 5))
    assertValue(
      of: weeklyRow,
      contains: ["4 lines", "Weekly", "dormant", "held at 0 weeks", "Inactive"]
    )

    chooseRowAction("Reactivate", on: weeklyRow, in: app)
    weeklyRow = habitRow(named: "Write lasting field notes", in: app)
    XCTAssertTrue(weeklyRow.waitForExistence(timeout: 5))
    assertValue(of: weeklyRow, contains: ["4 lines", "Weekly", "0 weeks", "Active"])

    chooseRowAction("Delete", on: weeklyRow, in: app)
    XCTAssertTrue(
      app.staticTexts[
        "Delete Write lasting field notes?"
      ].waitForExistence(timeout: 5))
    let weeklyConsequence =
      "Deleting Write lasting field notes also removes 2 activity periods, 1 bucket, and 0 log entries. This can't be undone."
    XCTAssertTrue(app.staticTexts[weeklyConsequence].exists)
    recordScreenshot(named: "Delete confirmation", of: app)
    app.buttons["Cancel deletion"].tap()
    XCTAssertTrue(habitRow(named: "Write lasting field notes", in: app).exists)

    weeklyRow = habitRow(named: "Write lasting field notes", in: app)
    chooseRowAction("Delete", on: weeklyRow, in: app)
    XCTAssertTrue(app.staticTexts[weeklyConsequence].waitForExistence(timeout: 5))
    app.buttons["Delete permanently"].tap()
    XCTAssertFalse(
      habitRow(
        named: "Write lasting field notes",
        in: app
      ).waitForExistence(timeout: 2))

    app.terminate()
    app.launchArguments = launchArguments(reset: false)
    app.launch()
    XCTAssertTrue(app.otherElements["shell.destination.today"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.otherElements["today.empty"].exists)
    app.buttons["shell.tab.habits"].tap()

    dailyRow = habitRow(named: "Read with care", in: app)
    XCTAssertTrue(dailyRow.waitForExistence(timeout: 5))
    assertValue(of: dailyRow, contains: ["3 chapters", "Daily", "0 days", "Active"])

    chooseRowAction("Delete", on: dailyRow, in: app)
    XCTAssertTrue(
      app.staticTexts[
        "Deleting Read with care also removes 1 activity period, 1 bucket, and 0 log entries. This can't be undone."
      ].waitForExistence(timeout: 5))
    app.buttons["Delete permanently"].tap()
    XCTAssertFalse(habitRow(named: "Read with care", in: app).waitForExistence(timeout: 2))

    app.buttons["shell.tab.today"].tap()
    XCTAssertTrue(app.otherElements["today.empty"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.staticTexts[
        "Tend is a quiet place to grow the habits you want to keep."
      ].exists)
    XCTAssertTrue(app.buttons["today.plant-habit"].exists)
  }

  @MainActor
  func testHabitManagementSurfacesPassAccessibilityAudits() throws {
    let auditTypes: XCUIAccessibilityAuditType = [
      .contrast,
      .elementDetection,
      .hitRegion,
      .sufficientElementDescription,
      .textClipped,
      .trait,
    ]
    let app = launch(reset: true)
    XCTAssertTrue(app.otherElements["today.empty"].waitForExistence(timeout: 5))
    assertMinimumHitRegion(of: app.buttons["today.plant-habit"])
    try app.performAccessibilityAudit(for: auditTypes)

    app.buttons["today.plant-habit"].tap()
    XCTAssertTrue(app.textFields["Habit name"].waitForExistence(timeout: 5))
    // Scrollable forms report offscreen labels as inaccessible at accessibility text sizes.
    let scrollAuditTypes = auditTypes.subtracting(.elementDetection)
    try app.performAccessibilityAudit(for: scrollAuditTypes)
    for cadence in ["Daily cadence", "Weekly cadence"] {
      assertMinimumHitRegion(of: app.buttons[cadence])
    }
    assertMinimumHitRegion(of: app.buttons["Save"])

    app.buttons["Weekly cadence"].tap()
    for weekday in [
      "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
    ] {
      assertMinimumHitRegion(of: app.buttons[weekday])
    }
    app.buttons["Monday"].tap()
    XCTAssertTrue(app.buttons["Monday"].isSelected)

    replaceText(in: app.textFields["Habit name"], with: "Audit habit")
    app.buttons["Save"].tap()
    XCTAssertTrue(app.otherElements["shell.destination.today"].waitForExistence(timeout: 5))

    app.buttons["shell.tab.habits"].tap()
    assertMinimumHitRegion(of: app.buttons["habits.add"])
    let row = habitRow(named: "Audit habit", in: app)
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    assertMinimumHitRegion(of: row)
    try app.performAccessibilityAudit(for: auditTypes)

    chooseRowAction("Delete", on: row, in: app)
    let consequence =
      "Deleting Audit habit also removes 1 activity period, 1 bucket, and 0 log entries. This can't be undone."
    XCTAssertTrue(app.staticTexts["Delete Audit habit?"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts[consequence].exists)
    XCTAssertTrue(app.buttons["Cancel deletion"].exists)
    XCTAssertTrue(app.buttons["Archive instead"].exists)
    XCTAssertTrue(app.buttons["Delete permanently"].exists)
    // Half-height system sheets report false positives for visible, queryable text.
    let sheetAuditTypes = auditTypes.subtracting([.elementDetection, .textClipped])
    try app.performAccessibilityAudit(for: sheetAuditTypes)
  }

  @MainActor
  private func launch(reset: Bool) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = launchArguments(reset: reset)
    app.terminate()
    app.launch()
    return app
  }

  private func launchArguments(reset: Bool) -> [String] {
    var arguments = [
      "-tend-ui-testing",
      "-tend-ui-test-store",
      storeName,
    ]
    if reset {
      arguments.append("-tend-ui-test-reset")
    }
    return arguments
  }

  @MainActor
  private func replaceText(in field: XCUIElement, with replacement: String) {
    XCTAssertTrue(field.waitForExistence(timeout: 2))
    field.tap()
    field.tap(withNumberOfTaps: 3, numberOfTouches: 1)
    field.typeText(
      replacement.isEmpty
        ? XCUIKeyboardKey.delete.rawValue
        : replacement
    )
  }

  @MainActor
  private func assertMinimumHitRegion(of element: XCUIElement) {
    XCTAssertTrue(element.waitForExistence(timeout: 2))
    let minimum = 44 - 0.01
    XCTAssertGreaterThanOrEqual(
      element.frame.width, minimum, "\(element) is narrower than 44 points")
    XCTAssertGreaterThanOrEqual(
      element.frame.height, minimum, "\(element) is shorter than 44 points")
  }

  @MainActor
  private func staticText(
    containing fragment: String,
    in app: XCUIApplication
  ) -> XCUIElement {
    app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", fragment)
    ).firstMatch
  }

  @MainActor
  private func chooseRowAction(
    _ action: String,
    on row: XCUIElement,
    in app: XCUIApplication
  ) {
    XCTAssertTrue(row.waitForExistence(timeout: 2))
    row.press(forDuration: 1)
    let button = app.buttons[action]
    XCTAssertTrue(button.waitForExistence(timeout: 2))
    button.tap()
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
  private func assertValue(of element: XCUIElement, contains fragments: [String]) {
    guard let value = element.value as? String else {
      XCTFail("Expected an accessibility value for \(element.label)")
      return
    }
    for fragment in fragments {
      XCTAssertTrue(value.contains(fragment), "Expected \(value) to contain \(fragment)")
    }
  }

  @MainActor
  private func recordScreenshot(named name: String, of app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
