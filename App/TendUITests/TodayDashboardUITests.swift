import UIKit
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
    let device = evidenceDeviceName
    let sizes = [
      (
        category: "UICTContentSizeCategoryAccessibilityL",
        name: "accessibility-large"
      ),
      (
        category: "UICTContentSizeCategoryAccessibilityXXL",
        name: "accessibility-extra-extra-large"
      ),
    ]

    for size in sizes {
      let app = launch(
        fixture: "today-mixed",
        additionalArguments: acceptanceLaunchArguments + [
          "-UIPreferredContentSizeCategoryName",
          size.category,
        ]
      )
      let dashboard = app.otherElements["today.dashboard"]
      XCTAssertTrue(dashboard.waitForExistence(timeout: 5))
      guard assertEvidenceDeviceGeometry(in: app) else {
        app.terminate()
        return
      }

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

      let topTitleY = title.frame.minY
      let topAuditedElementKeys = visibleAuditElementKeys(in: app)
      recordScreenshot("\(device)-mixed-\(size.name)-top", of: app)
      try performAdaptiveAccessibilityAudit(in: app)
      restoreTop(title, to: topTitleY, in: app)

      dragToMiddle(in: app, normalizedDistance: 0.35)
      let middleTitleY = title.frame.minY
      XCTAssertLessThan(middleTitleY, topTitleY - 150)
      recordScreenshot("\(device)-mixed-\(size.name)-middle", of: app)
      try performAdaptiveAccessibilityAudit(
        in: app,
        previouslyAuditedElementKeys: topAuditedElementKeys
      )
      restoreTop(title, to: topTitleY, in: app)

      let lastRow = element("today.row.Water seedlings", in: app)
      let tabPill = app.buttons["shell.tab.today"]
      scroll(lastRow, above: tabPill, in: app)
      XCTAssertLessThan(title.frame.minY, middleTitleY - 20)
      XCTAssertTrue(lastRow.isHittable)
      XCTAssertGreaterThanOrEqual(lastRow.frame.minY, window.frame.minY)
      XCTAssertLessThanOrEqual(lastRow.frame.maxY, tabPill.frame.minY)
      recordScreenshot("\(device)-mixed-\(size.name)-bottom", of: app)
      app.terminate()
    }
  }

  @MainActor
  func testAcceptanceEvidenceStates() throws {
    let device = evidenceDeviceName
    let launchArguments = acceptanceLaunchArguments

    do {
      let app = launch(fixture: "today-mixed", additionalArguments: launchArguments)
      let dashboard = app.otherElements["today.dashboard"]
      XCTAssertTrue(dashboard.waitForExistence(timeout: 5))
      guard assertEvidenceDeviceGeometry(in: app) else {
        app.terminate()
        return
      }
      assertCenteredReadableSurface(dashboard, in: app)
      assertAccessibilityOrder(
        [
          "today.title",
          "today.summary",
          "today.section.to-tend",
          "today.row.Check in",
          "today.row.Exercise",
          "today.row.Meditate",
          "today.section.tended",
          "today.row.Read",
          "today.row.Water seedlings",
        ],
        in: app
      )
      XCTAssertEqual(
        element("today.row.Exercise", in: app).descendants(matching: .button).count,
        0
      )
      XCTAssertEqual(
        element("today.row.Exercise", in: app).descendants(matching: .progressIndicator).count,
        0
      )
      assertMinimumHitRegion(of: app.buttons["shell.tab.today"])
      assertMinimumHitRegion(of: app.buttons["shell.tab.habits"])
      try app.performAccessibilityAudit(for: acceptanceAuditTypes)

      if device == "ipad" {
        recordScreenshot("ipad-mixed-full", of: app)
      } else {
        let title = element("today.title", in: app)
        let topTitleY = title.frame.minY
        recordScreenshot("iphone-mixed-top", of: app)
        let tabPill = app.buttons["shell.tab.today"]
        scroll(element("today.row.Water seedlings", in: app), above: tabPill, in: app)
        XCTAssertLessThan(title.frame.minY, topTitleY - 10)
        recordScreenshot("iphone-mixed-bottom", of: app)
      }
      app.terminate()
    }

    do {
      let app = launch(fixture: "today-all-tended", additionalArguments: launchArguments)
      let dashboard = app.otherElements["today.dashboard"]
      XCTAssertTrue(dashboard.waitForExistence(timeout: 5))
      assertCenteredReadableSurface(dashboard, in: app)
      XCTAssertTrue(element("today.all-tended", in: app).exists)
      try app.performAccessibilityAudit(for: acceptanceAuditTypes)
      recordScreenshot("\(device)-all-tended", of: app)
      app.terminate()
    }

    do {
      let app = launch(fixture: "today-inactive", additionalArguments: launchArguments)
      let inactive = app.otherElements["today.inactive"]
      XCTAssertTrue(inactive.waitForExistence(timeout: 5))
      assertCenteredReadableSurface(inactive, in: app)
      XCTAssertTrue(app.staticTexts["No active habits."].exists)
      try app.performAccessibilityAudit(for: acceptanceAuditTypes)
      recordScreenshot("\(device)-inactive", of: app)
      app.terminate()
    }

    do {
      let app = launch(fixture: "today-failure", additionalArguments: launchArguments)
      let dashboard = app.otherElements["today.dashboard"]
      XCTAssertTrue(dashboard.waitForExistence(timeout: 5))
      assertCenteredReadableSurface(dashboard, in: app)
      let malformed = element("today.row.Malformed cadence", in: app)
      let retry = app.buttons["today.retry.Malformed cadence"]
      XCTAssertTrue(malformed.exists)
      XCTAssertEqual(app.buttons.matching(identifier: retry.identifier).count, 1)
      XCTAssertEqual(retry.label, "Retry Malformed cadence")
      assertMinimumHitRegion(of: retry)
      try app.performAccessibilityAudit(for: acceptanceAuditTypes)

      if device == "ipad" {
        recordScreenshot("ipad-failure-full", of: app)
      } else {
        let tabPill = app.buttons["shell.tab.today"]
        XCTAssertTrue(malformed.isHittable)
        XCTAssertTrue(retry.isHittable)
        XCTAssertLessThanOrEqual(malformed.frame.maxY, tabPill.frame.minY)
        recordScreenshot("iphone-failure-full", of: app)
      }
      app.terminate()
    }
  }

  @MainActor
  func testCenteredIPadEvidenceState() throws {
    try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Requires an iPad")
    let app = launch(fixture: "today-mixed", additionalArguments: acceptanceLaunchArguments)
    let dashboard = app.otherElements["today.dashboard"]
    XCTAssertTrue(dashboard.waitForExistence(timeout: 5))

    guard assertEvidenceDeviceGeometry(in: app) else {
      app.terminate()
      return
    }
    let window = app.windows.firstMatch
    assertCenteredReadableSurface(dashboard, in: app)

    let firstRow = element("today.row.Check in", in: app)
    let lastRow = element("today.row.Water seedlings", in: app)
    let tabPill = app.buttons["shell.tab.today"]
    XCTAssertTrue(firstRow.isHittable)
    XCTAssertTrue(lastRow.isHittable)
    XCTAssertGreaterThanOrEqual(firstRow.frame.minX, window.frame.minX)
    XCTAssertLessThanOrEqual(lastRow.frame.maxY, tabPill.frame.minY)

    try app.performAccessibilityAudit(for: acceptanceAuditTypes)
    recordScreenshot("ipad-mixed-centered", of: app)
    app.terminate()
  }

  @MainActor
  func testFailureReflowsAtTwoAccessibilityTextSizes() throws {
    let device = evidenceDeviceName
    let sizes = [
      (
        category: "UICTContentSizeCategoryAccessibilityL",
        name: "accessibility-large"
      ),
      (
        category: "UICTContentSizeCategoryAccessibilityXXL",
        name: "accessibility-extra-extra-large"
      ),
    ]

    for size in sizes {
      let app = launch(
        fixture: "today-failure",
        additionalArguments: acceptanceLaunchArguments + [
          "-UIPreferredContentSizeCategoryName",
          size.category,
        ]
      )
      let dashboard = app.otherElements["today.dashboard"]
      XCTAssertTrue(dashboard.waitForExistence(timeout: 5))
      guard assertEvidenceDeviceGeometry(in: app) else {
        app.terminate()
        return
      }

      let malformed = element("today.row.Malformed cadence", in: app)
      let retry = app.buttons["today.retry.Malformed cadence"]
      XCTAssertTrue(malformed.exists)
      XCTAssertTrue(retry.exists)
      assertMinimumHitRegion(of: retry)

      let topMalformedY = malformed.frame.minY
      let topAuditedElementKeys = visibleAuditElementKeys(in: app)
      recordScreenshot("\(device)-failure-\(size.name)-top", of: app)
      try performAdaptiveAccessibilityAudit(in: app)
      restoreTop(malformed, to: topMalformedY, in: app)

      dragToMiddle(in: app, normalizedDistance: 0.25)
      let middleMalformedY = malformed.frame.minY
      XCTAssertLessThan(middleMalformedY, topMalformedY - 100)
      let middleRetryY = retry.frame.minY
      recordScreenshot("\(device)-failure-\(size.name)-middle", of: app)
      try performAdaptiveAccessibilityAudit(
        in: app,
        previouslyAuditedElementKeys: topAuditedElementKeys
      )
      restoreTop(malformed, to: topMalformedY, in: app)

      let tabPill = app.buttons["shell.tab.today"]
      scroll(retry, above: tabPill, in: app)
      XCTAssertLessThan(retry.frame.minY, middleRetryY - 20)
      XCTAssertTrue(malformed.isHittable)
      XCTAssertTrue(retry.isHittable)
      XCTAssertLessThanOrEqual(retry.frame.maxY, tabPill.frame.minY)
      recordScreenshot("\(device)-failure-\(size.name)-bottom", of: app)
      app.terminate()
    }
  }

  @MainActor
  private var evidenceDeviceName: String {
    UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
  }

  private var acceptanceLaunchArguments: [String] {
    [
      "-AppleInterfaceStyle",
      "Dark",
      "-UIAccessibilityReduceMotionEnabled",
      "YES",
    ]
  }

  private var acceptanceAuditTypes: XCUIAccessibilityAuditType {
    [
      .contrast,
      .hitRegion,
      .sufficientElementDescription,
      .textClipped,
      .trait,
    ]
  }

  @MainActor
  private func performAdaptiveAccessibilityAudit(
    in app: XCUIApplication,
    previouslyAuditedElementKeys: Set<String> = []
  ) throws {
    // XCTest includes controls scrolled beneath opaque system and tab chrome in contrast audits.
    // It can also re-report noninteractive text that passed while visible in an earlier viewport.
    // Ignore only those unreachable or already-audited contrast findings; every other issue fails.
    try app.performAccessibilityAudit(for: acceptanceAuditTypes) { issue in
      guard issue.auditType == .contrast, let issueElement = issue.element else {
        return false
      }
      let unobscuredTop = self.element("shell.destination.today", in: app).frame.minY
      return issueElement.frame.minY <= unobscuredTop
        || issueElement.frame.maxY > app.buttons["shell.tab.today"].frame.minY
        || previouslyAuditedElementKeys.contains(self.auditElementKey(issueElement))
    }
  }

  @MainActor
  private func visibleAuditElementKeys(in app: XCUIApplication) -> Set<String> {
    let unobscuredTop = element("shell.destination.today", in: app).frame.minY
    let unobscuredBottom = app.buttons["shell.tab.today"].frame.minY
    return Set(
      app.descendants(matching: .any).allElementsBoundByIndex.compactMap { element in
        guard element.frame.minY > unobscuredTop, element.frame.maxY <= unobscuredBottom else {
          return nil
        }
        return auditElementKey(element)
      }
    )
  }

  @MainActor
  private func auditElementKey(_ element: XCUIElement) -> String {
    "\(element.elementType.rawValue)|\(element.identifier)|\(element.label)"
  }

  @MainActor
  private func assertCenteredReadableSurface(
    _ surface: XCUIElement,
    in app: XCUIApplication
  ) {
    let window = app.windows.firstMatch
    XCTAssertTrue(window.exists)
    XCTAssertGreaterThanOrEqual(surface.frame.minX, window.frame.minX)
    XCTAssertLessThanOrEqual(surface.frame.maxX, window.frame.maxX)
    let expectedLeadingInset = max((window.frame.width - 600) / 2, 20)
    XCTAssertEqual(
      element("today.title", in: app).frame.minX,
      window.frame.minX + expectedLeadingInset,
      accuracy: 2
    )
  }

  @MainActor
  private func assertEvidenceDeviceGeometry(in app: XCUIApplication) -> Bool {
    let window = app.windows.firstMatch
    XCTAssertTrue(window.exists)

    let expectedSize =
      UIDevice.current.userInterfaceIdiom == .pad
      ? CGSize(width: 1024, height: 1366)
      : CGSize(width: 402, height: 874)
    XCTAssertEqual(
      window.frame.size,
      expectedSize,
      "Expected portrait \(expectedSize.width)×\(expectedSize.height), got \(window.frame.size)"
    )
    return window.frame.size == expectedSize
  }

  @MainActor
  private func restoreTop(
    _ anchor: XCUIElement,
    to expectedY: CGFloat,
    in app: XCUIApplication
  ) {
    for _ in 0..<12 {
      if abs(anchor.frame.minY - expectedY) <= 2 {
        return
      }
      app.swipeDown()
    }

    XCTAssertEqual(anchor.frame.minY, expectedY, accuracy: 2)
  }

  @MainActor
  private func dragToMiddle(
    in app: XCUIApplication,
    normalizedDistance: CGFloat
  ) {
    let scrollSurface = element("shell.destination.today", in: app)
    XCTAssertTrue(scrollSurface.exists)
    let start = scrollSurface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.68))
    let end = scrollSurface.coordinate(
      withNormalizedOffset: CGVector(dx: 0.5, dy: 0.68 - normalizedDistance)
    )
    start.press(
      forDuration: 0.5,
      thenDragTo: end,
      withVelocity: .slow,
      thenHoldForDuration: 0.5
    )
  }

  @MainActor
  private func assertAccessibilityOrder(
    _ identifiers: [String],
    in app: XCUIApplication
  ) {
    let elements = app.descendants(matching: .any).allElementsBoundByIndex
    var previousIndex = -1
    for identifier in identifiers {
      guard let index = elements.firstIndex(where: { $0.identifier == identifier }) else {
        XCTFail("Missing accessibility element \(identifier)")
        return
      }
      XCTAssertGreaterThan(index, previousIndex, "\(identifier) is out of traversal order")
      previousIndex = index
    }
  }

  @MainActor
  private func assertMinimumHitRegion(of element: XCUIElement) {
    XCTAssertTrue(element.exists)
    XCTAssertGreaterThanOrEqual(element.frame.width, 44)
    XCTAssertGreaterThanOrEqual(element.frame.height, 44)
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
