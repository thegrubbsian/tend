import UIKit
import XCTest

final class GoalRosterUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
  }

  override func tearDown() {
    XCUIDevice.shared.orientation = .portrait
  }

  @MainActor
  func testPortraitRosterProjectsRowsAndClosedDisclosureAccessibility() throws {
    let app = launch()
    selectGoals(in: app)

    let screen = element("goals.screen", in: app)
    XCTAssertTrue(screen.waitForExistence(timeout: 5))
    assertPortraitEvidenceGeometry(in: app)
    let goalsTab = app.buttons["shell.tab.goals"]
    XCTAssertTrue(goalsTab.isSelected)
    assertMinimumHitRegion(of: goalsTab)
    assertMinimumHitRegion(of: app.buttons["shell.tab.today"])
    assertMinimumHitRegion(of: app.buttons["shell.tab.habits"])
    assertMinimumHitRegion(of: app.buttons["goals.add"])

    assertRow(
      id: "10000000-0000-0000-0000-000000000002",
      name: "Grow oak seedlings",
      contains: ["Behind", "150 centimeters now · 30 of 80 centimeters", "Jan 31, 2026"],
      in: app
    )
    assertRow(
      id: "10000000-0000-0000-0000-000000000003",
      name: "Lower resting heart rate",
      contains: ["On pace", "70 beats per minute now · 10 of 20 beats per minute"],
      in: app
    )
    scroll(
      row(id: "10000000-0000-0000-0000-000000000001", in: app),
      above: goalsTab,
      in: app
    )
    assertRow(
      id: "10000000-0000-0000-0000-000000000001",
      name: "Fund neighborhood science kits for every after-school classroom",
      contains: [
        "On pace",
        "1,250,000 of 2,000,000 dollars pledged across neighborhoods",
        "No deadline",
      ],
      in: app
    )
    XCTAssertTrue(element("goals.pastDue", in: app).exists)
    scroll(
      row(id: "10000000-0000-0000-0000-000000000004", in: app),
      above: goalsTab,
      in: app
    )
    assertRow(
      id: "10000000-0000-0000-0000-000000000004",
      name: "Submit winter grant application",
      contains: ["Past due", "7 of 10 sections", "Jan 14, 2026"],
      in: app
    )

    let disclosure = app.buttons["goals.closed.disclosure"]
    scroll(disclosure, above: goalsTab, in: app)
    XCTAssertTrue(disclosure.exists)
    XCTAssertEqual(disclosure.label, "Closed goals")
    XCTAssertEqual(disclosure.value as? String, "2, collapsed")
    assertMinimumHitRegion(of: disclosure)
    XCTAssertFalse(row(id: "10000000-0000-0000-0000-000000000005", in: app).exists)
    XCTAssertFalse(row(id: "10000000-0000-0000-0000-000000000006", in: app).exists)
    try app.performAccessibilityAudit(for: acceptanceAuditTypes)
    recordScreenshot("goal-roster-portrait-collapsed", of: app)

    disclosure.tap()
    XCTAssertEqual(disclosure.value as? String, "2, expanded")
    let harvested = row(id: "10000000-0000-0000-0000-000000000005", in: app)
    let letGo = row(id: "10000000-0000-0000-0000-000000000006", in: app)
    scroll(letGo, above: goalsTab, in: app)
    assertCombinedSemantics(
      of: harvested,
      name: "Read the field guide",
      contains: ["Harvested", "12 of 12 chapters", "No deadline"]
    )
    assertCombinedSemantics(
      of: letGo,
      name: "Walk the coastal trail",
      contains: ["Let go", "20 miles now · 20 of 100 miles", "No deadline"]
    )
    assertMinimumHitRegion(of: harvested)
    assertMinimumHitRegion(of: letGo)
    XCTAssertLessThanOrEqual(letGo.frame.maxY, goalsTab.frame.minY)
    try app.performAccessibilityAudit(for: acceptanceAuditTypes)
    recordScreenshot("goal-roster-portrait-expanded", of: app)
    scrollBack(disclosure, above: goalsTab, in: app)

    disclosure.tap()
    XCTAssertEqual(disclosure.value as? String, "2, collapsed")
    XCTAssertTrue(letGo.waitForNonExistence(timeout: 2))
  }

  @MainActor
  func testLandscapeRosterKeepsRowsWithinTheViewportAndAboveTheTabPill() throws {
    let app = launch()
    selectGoals(in: app)
    let disclosure = app.buttons["goals.closed.disclosure"]
    scroll(disclosure, above: app.buttons["shell.tab.goals"], in: app)
    XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
    disclosure.tap()

    XCUIDevice.shared.orientation = .landscapeLeft
    let window = app.windows.firstMatch
    let landscape = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "frame.size.width > frame.size.height"),
      object: window
    )
    wait(for: [landscape], timeout: 5)

    let goalsTab = app.buttons["shell.tab.goals"]
    let lastRow = row(id: "10000000-0000-0000-0000-000000000006", in: app)
    scroll(lastRow, above: goalsTab, in: app)
    XCTAssertGreaterThanOrEqual(lastRow.frame.minX, window.frame.minX)
    XCTAssertLessThanOrEqual(lastRow.frame.maxX, window.frame.maxX)
    XCTAssertLessThanOrEqual(lastRow.frame.maxY, goalsTab.frame.minY)
    assertMinimumHitRegion(of: lastRow)
    assertMinimumHitRegion(of: disclosure)
    try app.performAccessibilityAudit(for: acceptanceAuditTypes)
    recordScreenshot("goal-roster-landscape-expanded", of: app)
  }

  @MainActor
  func testRosterReflowsAtTwoAccessibilityDynamicTypeSizes() throws {
    let sizes = [
      ("UICTContentSizeCategoryAccessibilityL", "accessibility-large"),
      ("UICTContentSizeCategoryAccessibilityXXL", "accessibility-extra-extra-large"),
    ]

    for (category, screenshotName) in sizes {
      let app = launch(additionalArguments: [
        "-UIPreferredContentSizeCategoryName", category,
      ])
      selectGoals(in: app)
      assertPortraitEvidenceGeometry(in: app)
      let window = app.windows.firstMatch
      let goalsTab = app.buttons["shell.tab.goals"]
      XCTAssertTrue(goalsTab.isSelected)

      let firstRow = row(id: "10000000-0000-0000-0000-000000000002", in: app)
      XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
      XCTAssertGreaterThanOrEqual(firstRow.frame.minX, window.frame.minX)
      XCTAssertLessThanOrEqual(firstRow.frame.maxX, window.frame.maxX)
      assertMinimumHitRegion(of: firstRow)
      try app.performAccessibilityAudit(for: acceptanceAuditTypes)
      recordScreenshot("goal-roster-\(screenshotName)-top", of: app)

      let longRow = row(id: "10000000-0000-0000-0000-000000000001", in: app)
      scroll(longRow, above: goalsTab, in: app)
      assertCombinedSemantics(
        of: longRow,
        name: "Fund neighborhood science kits for every after-school classroom",
        contains: [
          "On pace",
          "1,250,000 of 2,000,000 dollars pledged across neighborhoods",
        ]
      )
      XCTAssertGreaterThan(longRow.frame.height, 44)
      XCTAssertGreaterThan(longRow.frame.height, firstRow.frame.height)
      XCTAssertGreaterThanOrEqual(longRow.frame.minX, window.frame.minX)
      XCTAssertLessThanOrEqual(longRow.frame.maxX, window.frame.maxX)

      let pastDue = row(id: "10000000-0000-0000-0000-000000000004", in: app)
      scroll(pastDue, above: goalsTab, in: app)
      XCTAssertGreaterThanOrEqual(pastDue.frame.minY, window.frame.minY)
      XCTAssertLessThanOrEqual(pastDue.frame.maxY, goalsTab.frame.minY)
      XCTAssertGreaterThanOrEqual(pastDue.frame.minY, longRow.frame.maxY)
      try app.performAccessibilityAudit(for: acceptanceAuditTypes)
      recordScreenshot("goal-roster-\(screenshotName)-bottom", of: app)
      app.terminate()
    }
  }

  private let fixtureInstant = "2026-01-15T17:00:00Z"

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
  private func launch(additionalArguments: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["TZ"] = "America/Los_Angeles"
    app.launchArguments = [
      "-tend-ui-testing",
      "-tend-ui-test-store",
      "GoalRosterUITests-\(UUID().uuidString)",
      "-tend-ui-test-reset",
      "-tend-ui-test-fixture",
      "goal-roster",
      "-tend-ui-test-instant",
      fixtureInstant,
    ] + additionalArguments
    app.terminate()
    app.launch()
    return app
  }

  @MainActor
  private func selectGoals(in app: XCUIApplication) {
    let goalsTab = app.buttons["shell.tab.goals"]
    XCTAssertTrue(goalsTab.waitForExistence(timeout: 5))
    goalsTab.tap()
    XCTAssertTrue(element("goals.screen", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(goalsTab.isSelected)
  }

  @MainActor
  private func assertRow(
    id: String,
    name: String,
    contains expectedFragments: [String],
    in app: XCUIApplication
  ) {
    let element = row(id: id, in: app)
    XCTAssertTrue(element.waitForExistence(timeout: 5))
    assertCombinedSemantics(of: element, name: name, contains: expectedFragments)
    assertMinimumHitRegion(of: element)
  }

  @MainActor
  private func assertCombinedSemantics(
    of element: XCUIElement,
    name: String,
    contains expectedFragments: [String]
  ) {
    XCTAssertEqual(element.label, name)
    let combinedOutput = "\(element.label), \(element.value as? String ?? "")"
    for fragment in expectedFragments {
      XCTAssertTrue(combinedOutput.contains(fragment), "Missing \(fragment) from \(combinedOutput)")
    }
  }

  @MainActor
  private func assertPortraitEvidenceGeometry(in app: XCUIApplication) {
    let window = app.windows.firstMatch
    XCTAssertTrue(window.exists)
    XCTAssertEqual(
      window.frame.size,
      CGSize(width: 402, height: 874),
      "Expected portrait 402×874, got \(window.frame.size)"
    )
  }

  @MainActor
  private func assertMinimumHitRegion(of element: XCUIElement) {
    XCTAssertTrue(element.exists)
    XCTAssertGreaterThanOrEqual(element.frame.width, 44)
    XCTAssertGreaterThanOrEqual(element.frame.height, 44)
  }

  @MainActor
  private func row(id: String, in app: XCUIApplication) -> XCUIElement {
    element("goals.row.\(id)", in: app)
  }

  @MainActor
  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }

  @MainActor
  private func scroll(
    _ element: XCUIElement,
    above overlay: XCUIElement,
    in app: XCUIApplication
  ) {
    for _ in 0..<16 {
      guard overlay.exists else {
        XCTFail("Expected overlay \(overlay.identifier) to exist")
        return
      }
      if element.exists,
        element.isHittable,
        element.frame.minY >= app.windows.firstMatch.frame.minY,
        element.frame.maxY <= overlay.frame.minY
      {
        return
      }
      app.swipeUp()
    }
    XCTFail("Expected \(element.identifier) to become visible above \(overlay.identifier)")
  }

  @MainActor
  private func scrollBack(
    _ element: XCUIElement,
    above overlay: XCUIElement,
    in app: XCUIApplication
  ) {
    for _ in 0..<16 {
      if element.exists,
        element.isHittable,
        element.frame.minY >= app.windows.firstMatch.frame.minY,
        element.frame.maxY <= overlay.frame.minY
      {
        return
      }
      app.swipeDown()
    }
    XCTFail("Expected \(element.identifier) to become visible above \(overlay.identifier)")
  }

  @MainActor
  private func recordScreenshot(_ name: String, of app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
