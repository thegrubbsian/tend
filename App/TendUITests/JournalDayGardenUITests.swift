import XCTest

final class JournalDayGardenUITests: XCTestCase {
  private let fixedInstant = "2026-08-05T12:00:00Z"
  private let readID = "00000000-0000-0000-0000-000000000001"
  private let walkID = "00000000-0000-0000-0000-000000000002"
  private let brokenID = "00000000-0000-0000-0000-000000000003"

  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testWrittenEntryRendersLiveGardenStatesAndIsolatedRetry() throws {
    XCUIDevice.shared.orientation = .portrait
    let app = launch(
      storeName: "JournalDayGardenUITests-\(UUID().uuidString)",
      reset: true
    )
    let section = element("journalGarden.section", in: app)

    XCTAssertTrue(section.waitForExistence(timeout: 5))
    reveal(section, in: app)
    XCTAssertEqual(element("journalGarden.title", in: app).label, "TODAY'S GARDEN")
    let back = app.buttons["journalEditor.back"]
    let date = element("journalEditor.date", in: app)
    let delete = app.buttons["journalEditor.delete"]
    XCTAssertLessThanOrEqual(back.frame.maxX, date.frame.minX)
    XCTAssertLessThanOrEqual(date.frame.maxX, delete.frame.minX)
    assertRow(
      id: readID,
      name: "Read",
      progress: "2 of 2 pages",
      state: "Open",
      leafValue: "Filled",
      in: app
    )
    assertRow(
      id: walkID,
      name: "Walk",
      progress: "1 of 2 miles",
      state: "Open",
      leafValue: "Hollow",
      in: app
    )
    assertRow(
      id: brokenID,
      name: "Broken",
      progress: "Progress unavailable",
      state: "Unavailable",
      leafValue: "Hollow",
      in: app
    )

    let retry = app.buttons["journalGarden.retry.\(brokenID)"]
    XCTAssertTrue(retry.exists)
    XCTAssertEqual(retry.label, "Try again")
    assertMinimumHitRegion(retry)
    retry.tap()
    XCTAssertTrue(element("journalGarden.row.\(brokenID)", in: app).exists)
    XCTAssertTrue(element("journalGarden.row.\(readID)", in: app).exists)
    XCTAssertTrue(element("journalGarden.row.\(walkID)", in: app).exists)

    try app.performAccessibilityAudit(for: acceptanceAuditTypes)
    recordScreenshot("journal-day-garden", of: app)
  }

  @MainActor
  func testGardenAdaptsToAccessibilityTextAndLandscape() throws {
    XCUIDevice.shared.orientation = .portrait
    defer { XCUIDevice.shared.orientation = .portrait }
    let app = launch(
      storeName: "JournalDayGardenAdaptiveUITests-\(UUID().uuidString)",
      reset: true,
      additionalArguments: [
        "-UIPreferredContentSizeCategoryName",
        "UICTContentSizeCategoryAccessibilityXXL",
        "-UIAccessibilityReduceMotionEnabled",
        "YES",
      ]
    )
    let section = element("journalGarden.section", in: app)
    XCTAssertTrue(section.waitForExistence(timeout: 5))
    dismissKeyboard(in: app)
    reveal(section, in: app)

    for id in [readID, walkID, brokenID] {
      let row = element("journalGarden.row.\(id)", in: app)
      XCTAssertTrue(row.exists)
      XCTAssertGreaterThanOrEqual(row.frame.height, 44)
    }
    try app.performAccessibilityAudit(for: acceptanceAuditTypes)

    XCUIDevice.shared.orientation = .landscapeLeft
    let landscape = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        app.frame.width > app.frame.height
      },
      object: app
    )
    XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
    XCTAssertGreaterThanOrEqual(section.frame.minX, app.windows.firstMatch.frame.minX)
    XCTAssertLessThanOrEqual(section.frame.maxX, app.windows.firstMatch.frame.maxX)
    let retry = app.buttons["journalGarden.retry.\(brokenID)"]
    reveal(retry, in: app)
    let window = app.windows.firstMatch
    XCTAssertGreaterThanOrEqual(retry.frame.minY, window.frame.minY)
    XCTAssertLessThanOrEqual(retry.frame.maxY, window.frame.maxY)
    XCTAssertTrue(element("journalGarden.name.\(readID)", in: app).label.contains("Read"))
    XCTAssertTrue(element("journalGarden.name.\(walkID)", in: app).label.contains("Walk"))
    try app.performAccessibilityAudit(for: acceptanceAuditTypes.subtracting(.contrast))
    recordScreenshot("journal-day-garden-landscape", of: app)
  }

  @MainActor
  private func launch(
    storeName: String,
    reset: Bool,
    additionalArguments: [String] = []
  ) -> XCUIApplication {
    let app = XCUIApplication()
    var arguments = [
      "-tend-ui-testing",
      "-tend-ui-test-store",
      storeName,
      "-tend-ui-test-instant",
      fixedInstant,
      "-tend-journal-editor",
      "-tend-journal-garden",
      "-AppleLocale",
      "en_US",
      "-AppleLanguages",
      "(en)",
      "-AppleTimeZone",
      "UTC",
    ]
    if reset { arguments.append("-tend-ui-test-reset") }
    arguments.append(contentsOf: additionalArguments)
    app.launchArguments = arguments
    app.launch()
    return app
  }

  @MainActor
  private func assertRow(
    id: String,
    name: String,
    progress: String,
    state: String,
    leafValue: String,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let row = element("journalGarden.row.\(id)", in: app)
    XCTAssertTrue(row.exists, file: file, line: line)
    XCTAssertEqual(element("journalGarden.name.\(id)", in: app).label, name, file: file, line: line)
    XCTAssertEqual(
      element("journalGarden.progress.\(id)", in: app).label,
      progress,
      file: file,
      line: line
    )
    XCTAssertEqual(
      element("journalGarden.state.\(id)", in: app).label, state, file: file, line: line)
    XCTAssertEqual(
      element("journalGarden.leaf.\(id)", in: app).value as? String, leafValue, file: file,
      line: line)
  }

  @MainActor
  private func reveal(_ target: XCUIElement, in app: XCUIApplication) {
    let scroll = app.scrollViews["journalEditor.scroll"]
    for _ in 0..<20 {
      if target.isHittable { return }
      guard scroll.exists, scroll.isHittable, target.exists else {
        app.swipeUp(velocity: .slow)
        continue
      }
      nudge(scroll, towardEnd: target.frame.maxY > scroll.frame.maxY)
    }
    XCTFail("Expected \(target.identifier) to become hittable")
  }

  @MainActor
  private func nudge(_ scroll: XCUIElement, towardEnd: Bool) {
    let startY = towardEnd ? 0.7 : 0.3
    let endY = towardEnd ? 0.55 : 0.45
    let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
    let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
    start.press(forDuration: 0.05, thenDragTo: end)
  }

  @MainActor
  private func dismissKeyboard(in app: XCUIApplication) {
    let keyboard = app.keyboards.firstMatch
    guard keyboard.exists else { return }
    let hide = keyboard.buttons["Hide keyboard"]
    if hide.exists {
      hide.tap()
    } else {
      app.swipeDown()
    }
  }

  @MainActor
  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
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
  private func assertMinimumHitRegion(
    _ element: XCUIElement,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertTrue(element.exists, file: file, line: line)
    XCTAssertGreaterThanOrEqual(element.frame.width, 44, file: file, line: line)
    XCTAssertGreaterThanOrEqual(element.frame.height, 44, file: file, line: line)
  }

  @MainActor
  private func recordScreenshot(_ name: String, of app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
