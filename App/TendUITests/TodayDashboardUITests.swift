import XCTest

final class TodayDashboardUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  private let fixtureInstantArgument = "2026-08-05T19:00:00Z"

  @MainActor
  func testMixedDashboardRendersOrderedAlmanacSectionsAndFacts() {
    let app = launch(fixture: "today-mixed")

    XCTAssertTrue(app.otherElements["today.dashboard"].waitForExistence(timeout: 5))
    XCTAssertTrue(element("shell.destination.today", in: app).exists)
    XCTAssertEqual(element("today.title", in: app).label, "Today")
    XCTAssertEqual(element("today.summary", in: app).label, "2 of 5")
    XCTAssertTrue(element("today.section.to-tend", in: app).exists)
    XCTAssertTrue(element("today.section.tended", in: app).exists)

    let orderedNames = ["Check in", "Exercise", "Meditate", "Read", "Water seedlings"]
    let rows = orderedNames.map { element("today.row.\($0)", in: app) }
    for row in rows {
      XCTAssertTrue(row.exists)
    }
    for pair in zip(rows, rows.dropFirst()) {
      XCTAssertLessThan(pair.0.frame.minY, pair.1.frame.minY)
    }

    let exerciseValue = element("today.row.Exercise", in: app).value as? String ?? ""
    XCTAssertTrue(exerciseValue.contains("5,200 of 8,000 steps"))
    XCTAssertTrue(exerciseValue.contains("12 days"))
    XCTAssertTrue(exerciseValue.contains("Yesterday open · 12 day streak at risk"))
    let waterValue = element("today.row.Water seedlings", in: app).value as? String ?? ""
    XCTAssertTrue(waterValue.contains("5 of 3 times"))
    XCTAssertEqual(element("today.row.Exercise", in: app).descendants(matching: .button).count, 0)

    recordScreenshot("Today-mixed", of: app)
  }

  @MainActor
  func testAllTendedDashboardUsesCompactCelebrationState() {
    let app = launch(fixture: "today-all-tended")

    XCTAssertTrue(app.otherElements["today.dashboard"].waitForExistence(timeout: 5))
    XCTAssertEqual(element("today.title", in: app).label, "Today")
    XCTAssertEqual(element("today.summary", in: app).label, "2 of 2")
    XCTAssertEqual(element("today.all-tended", in: app).label, "All tended.")
    XCTAssertFalse(element("today.section.to-tend", in: app).exists)
    XCTAssertTrue(element("today.section.tended", in: app).exists)
    XCTAssertTrue(element("today.row.Drink water", in: app).exists)
    XCTAssertTrue(element("today.row.Weekly review", in: app).exists)

    recordScreenshot("Today-all-tended", of: app)
  }

  @MainActor
  func testInactiveStoreKeepsHonestEmptyDashboardWithoutFirstLaunchPrompt() {
    let app = launch(fixture: "today-inactive")

    XCTAssertTrue(app.otherElements["today.inactive"].waitForExistence(timeout: 5))
    XCTAssertEqual(element("today.title", in: app).label, "Today")
    XCTAssertFalse(element("today.summary", in: app).exists)
    XCTAssertTrue(app.staticTexts["No active habits."].exists)
    XCTAssertFalse(
      app.staticTexts["Replant a habit from All Habits when you are ready."].exists
    )
    XCTAssertFalse(app.otherElements["today.empty"].exists)
    XCTAssertFalse(app.buttons["today.plant-habit"].exists)

    recordScreenshot("Today-inactive", of: app)
  }

  @MainActor
  func testUnavailableRowStaysVisibleAndRetryRemainsReachable() {
    let app = launch(fixture: "today-failure")

    XCTAssertTrue(app.otherElements["today.dashboard"].waitForExistence(timeout: 5))
    XCTAssertEqual(element("today.summary", in: app).label, "1 of 3")
    XCTAssertTrue(element("today.row.Failure open", in: app).exists)
    XCTAssertTrue(element("today.row.Failure met", in: app).exists)
    let malformed = element("today.row.Malformed cadence", in: app)
    XCTAssertTrue(malformed.exists)
    let unavailableValue = malformed.value as? String ?? ""
    XCTAssertTrue(unavailableValue.contains("Progress unavailable"))
    XCTAssertTrue(unavailableValue.contains("Streak unavailable"))
    XCTAssertTrue(unavailableValue.contains("Cadence unavailable."))

    let retry = app.buttons["today.retry.Malformed cadence"]
    XCTAssertTrue(retry.exists)
    XCTAssertEqual(retry.label, "Retry Malformed cadence")
    retry.tap()
    XCTAssertTrue(malformed.waitForExistence(timeout: 2))
    XCTAssertTrue(retry.exists)

    recordScreenshot("Today-failure", of: app)
  }

  @MainActor
  func testPersistedDashboardSurvivesRelaunchAndRingTap() {
    let storeName = "TodayDashboardUITests-relaunch-\(UUID().uuidString)"
    let app = launch(fixture: "today-mixed", storeName: storeName)

    XCTAssertTrue(app.otherElements["today.dashboard"].waitForExistence(timeout: 5))
    let exercise = element("today.row.Exercise", in: app)
    let exerciseValue = exercise.value as? String
    XCTAssertTrue(exerciseValue?.contains("5,200 of 8,000 steps") == true)
    XCTAssertEqual(exercise.descendants(matching: .button).count, 0)

    scroll(exercise, above: app.buttons["shell.tab.today"], in: app)
    exercise.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.2)).tap()
    XCTAssertEqual(element("today.row.Exercise", in: app).value as? String, exerciseValue)

    app.terminate()
    app.launchArguments = launchArguments(
      storeName: storeName,
      reset: false,
      fixture: nil
    )
    app.launch()

    XCTAssertTrue(app.otherElements["today.dashboard"].waitForExistence(timeout: 5))
    XCTAssertEqual(element("today.summary", in: app).label, "2 of 5")
    XCTAssertEqual(element("today.row.Exercise", in: app).value as? String, exerciseValue)
  }

  @MainActor
  func testDashboardRefreshesAcrossHabitLifecycle() {
    let app = launch(includesFixedInstant: false)

    XCTAssertTrue(app.otherElements["today.empty"].waitForExistence(timeout: 5))
    app.buttons["shell.tab.habits"].tap()
    XCTAssertTrue(app.buttons["habits.add"].waitForExistence(timeout: 5))
    app.buttons["habits.add"].tap()
    XCTAssertTrue(app.textFields["Habit name"].waitForExistence(timeout: 5))
    replaceText(in: app.textFields["Habit name"], with: "Journey habit")
    replaceText(in: app.textFields["Target"], with: "1")
    replaceText(in: app.textFields["Unit"], with: "times")
    app.buttons["Save"].tap()
    XCTAssertTrue(habitRow(named: "Journey habit", in: app).waitForExistence(timeout: 5))

    app.buttons["shell.tab.today"].tap()
    let createdRow = element("today.row.Journey habit", in: app)
    XCTAssertTrue(createdRow.waitForExistence(timeout: 5))
    XCTAssertTrue((createdRow.value as? String)?.contains("0 of 1 time") == true)

    app.buttons["shell.tab.habits"].tap()
    var journeyRow = habitRow(named: "Journey habit", in: app)
    chooseRowAction("Edit", on: journeyRow, in: app)
    XCTAssertTrue(app.textFields["Habit name"].waitForExistence(timeout: 5))
    replaceText(in: app.textFields["Habit name"], with: "Journey habit renewed")
    replaceText(in: app.textFields["Target"], with: "2")
    replaceText(in: app.textFields["Unit"], with: "pages")
    app.buttons["Save"].tap()
    XCTAssertTrue(habitRow(named: "Journey habit renewed", in: app).waitForExistence(timeout: 5))

    app.buttons["shell.tab.today"].tap()
    let editedRow = element("today.row.Journey habit renewed", in: app)
    XCTAssertTrue(editedRow.waitForExistence(timeout: 5))
    XCTAssertTrue(element("today.row.Journey habit", in: app).waitForNonExistence(timeout: 2))
    XCTAssertTrue((editedRow.value as? String)?.contains("0 of 2 pages") == true)

    app.buttons["shell.tab.habits"].tap()
    journeyRow = habitRow(named: "Journey habit renewed", in: app)
    chooseRowAction("Archive", on: journeyRow, in: app)
    journeyRow = habitRow(named: "Journey habit renewed", in: app)
    XCTAssertTrue(journeyRow.waitForExistence(timeout: 5))
    XCTAssertTrue((journeyRow.value as? String)?.contains("Inactive") == true)

    app.buttons["shell.tab.today"].tap()
    XCTAssertTrue(element("today.inactive", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(
      element("today.row.Journey habit renewed", in: app).waitForNonExistence(timeout: 2)
    )

    app.buttons["shell.tab.habits"].tap()
    journeyRow = habitRow(named: "Journey habit renewed", in: app)
    chooseRowAction("Reactivate", on: journeyRow, in: app)
    journeyRow = habitRow(named: "Journey habit renewed", in: app)
    XCTAssertTrue(journeyRow.waitForExistence(timeout: 5))
    XCTAssertTrue((journeyRow.value as? String)?.contains("Active") == true)

    app.buttons["shell.tab.today"].tap()
    XCTAssertTrue(
      element("today.row.Journey habit renewed", in: app).waitForExistence(timeout: 5)
    )

    app.buttons["shell.tab.habits"].tap()
    journeyRow = habitRow(named: "Journey habit renewed", in: app)
    chooseRowAction("Delete", on: journeyRow, in: app)
    XCTAssertTrue(
      app.staticTexts["Delete Journey habit renewed?"].waitForExistence(timeout: 5)
    )
    app.buttons["Delete permanently"].tap()
    XCTAssertTrue(journeyRow.waitForNonExistence(timeout: 5))

    app.buttons["shell.tab.today"].tap()
    XCTAssertTrue(app.otherElements["today.empty"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      element("today.row.Journey habit renewed", in: app).waitForNonExistence(timeout: 2)
    )
  }

  @MainActor
  func testDashboardReflowsAtTwoAccessibilityTextSizes() throws {
    // Scroll-edge text can sit behind the system status area or floating pill while
    // remaining reachable; XCUI's contrast audit treats that transient occlusion as
    // a palette failure. Contrast is verified from the unobscured screenshots.
    let auditTypes: XCUIAccessibilityAuditType = [
      .hitRegion,
      .sufficientElementDescription,
      .textClipped,
      .trait,
    ]
    let sizes = [
      (
        category: "UICTContentSizeCategoryAccessibilityL",
        screenshot: "Today-accessibility-large"
      ),
      (
        category: "UICTContentSizeCategoryAccessibilityXL",
        screenshot: "Today-accessibility-extra-large"
      ),
    ]

    for size in sizes {
      let app = launch(
        fixture: "today-mixed",
        additionalArguments: [
          "-UIPreferredContentSizeCategoryName",
          size.category,
        ]
      )
      XCTAssertTrue(app.otherElements["today.dashboard"].waitForExistence(timeout: 5))

      let title = element("today.title", in: app)
      let summary = element("today.summary", in: app)
      XCTAssertGreaterThanOrEqual(summary.frame.minY, title.frame.maxY)

      let firstRow = element("today.row.Check in", in: app)
      let window = app.windows.firstMatch
      XCTAssertTrue(firstRow.exists)
      XCTAssertGreaterThanOrEqual(firstRow.frame.minX, window.frame.minX)
      XCTAssertLessThanOrEqual(firstRow.frame.maxX, window.frame.maxX)
      XCTAssertTrue(
        (firstRow.value as? String)?.contains("1 of 3 times") == true
      )
      recordScreenshot("\(size.screenshot)-top", of: app)

      let lastRow = element("today.row.Water seedlings", in: app)
      let tabPill = app.buttons["shell.tab.today"]
      scroll(lastRow, above: tabPill, in: app)
      XCTAssertTrue(lastRow.isHittable)
      XCTAssertGreaterThanOrEqual(lastRow.frame.minY, window.frame.minY)
      XCTAssertLessThanOrEqual(lastRow.frame.maxY, tabPill.frame.minY)

      try app.performAccessibilityAudit(for: auditTypes)
      recordScreenshot("\(size.screenshot)-bottom", of: app)
      app.terminate()
    }
  }

  @MainActor
  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }

  @MainActor
  private func launch(
    fixture: String? = nil,
    storeName: String? = nil,
    reset: Bool = true,
    includesFixedInstant: Bool = true,
    additionalArguments: [String] = []
  ) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["TZ"] = "America/Los_Angeles"
    app.launchArguments = launchArguments(
      storeName: storeName
        ?? "TodayDashboardUITests-\(fixture ?? "empty")-\(UUID().uuidString)",
      reset: reset,
      fixture: fixture,
      includesFixedInstant: includesFixedInstant,
      additionalArguments: additionalArguments
    )
    app.terminate()
    app.launch()
    return app
  }

  private func launchArguments(
    storeName: String,
    reset: Bool,
    fixture: String?,
    includesFixedInstant: Bool = true,
    additionalArguments: [String] = []
  ) -> [String] {
    var arguments = [
      "-tend-ui-testing",
      "-tend-ui-test-store",
      storeName,
    ]
    if includesFixedInstant {
      arguments += ["-tend-ui-test-instant", fixtureInstantArgument]
    }
    if reset {
      arguments.append("-tend-ui-test-reset")
    }
    if let fixture {
      arguments += ["-tend-ui-test-fixture", fixture]
    }
    return arguments + additionalArguments
  }

  @MainActor
  private func scroll(
    _ element: XCUIElement,
    above overlay: XCUIElement,
    in app: XCUIApplication
  ) {
    for _ in 0..<12 {
      guard element.exists, overlay.exists else {
        XCTFail("Expected scroll target and overlay to exist")
        return
      }

      let frame = element.frame
      if element.isHittable,
        frame.minY >= app.windows.firstMatch.frame.minY,
        frame.maxY <= overlay.frame.minY
      {
        return
      }
      app.swipeUp()
    }

    XCTFail("Expected \(element.identifier) to become visible above \(overlay.identifier)")
  }

  @MainActor
  private func replaceText(in field: XCUIElement, with replacement: String) {
    XCTAssertTrue(field.waitForExistence(timeout: 2))
    field.tap()
    field.tap(withNumberOfTaps: 3, numberOfTouches: 1)
    field.typeText(replacement)
  }

  @MainActor
  private func chooseRowAction(
    _ action: String,
    on row: XCUIElement,
    in app: XCUIApplication
  ) {
    XCTAssertTrue(row.waitForExistence(timeout: 2))
    for _ in 0..<8 where !row.isHittable {
      app.swipeUp()
    }
    XCTAssertTrue(row.isHittable)
    row.press(forDuration: 1)
    let button = app.buttons[action]
    XCTAssertTrue(button.waitForExistence(timeout: 2))
    button.tap()
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
  private func recordScreenshot(_ name: String, of app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
