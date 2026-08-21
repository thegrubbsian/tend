import XCTest

final class JournalEditingUITests: XCTestCase {
  private let fixedInstant = "2026-08-05T12:00:00Z"

  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testAutomaticCreateFlushRelaunchEmptyEditAndDelete() throws {
    XCUIDevice.shared.orientation = .portrait
    let storeName = "JournalEditingUITests-\(UUID().uuidString)"
    let app = launch(storeName: storeName, reset: true)

    let screen = element("journalEditor.screen", in: app)
    XCTAssertTrue(screen.waitForExistence(timeout: 5))
    let prose = app.textViews["journalEditor.prose"]
    XCTAssertTrue(prose.waitForExistence(timeout: 2))
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
    XCTAssertEqual(prose.value as? String ?? "", "")
    XCTAssertTrue(app.buttons["journalEditor.scope.Today"].isSelected)
    XCTAssertFalse(app.buttons["journalEditor.scope.Yesterday"].isSelected)
    XCTAssertFalse(app.buttons["Save"].exists)
    XCTAssertFalse(app.buttons["journalEditor.delete"].exists)

    prose.typeText("Field notes\nSecond line")
    XCTAssertTrue(waitForLabel("Saved", on: element("journalEditor.status", in: app)))
    XCTAssertTrue(app.buttons["journalEditor.delete"].waitForExistence(timeout: 2))
    for control in [
      app.buttons["journalEditor.back"],
      app.buttons["journalEditor.scope.Today"],
      app.buttons["journalEditor.scope.Yesterday"],
      app.buttons["journalEditor.delete"],
    ] {
      assertMinimumHitRegion(control)
    }
    try app.performAccessibilityAudit(for: acceptanceAuditTypes.subtracting(.hitRegion))
    recordScreenshot("journal-editor-saved", of: app)

    app.buttons["journalEditor.back"].tap()
    XCTAssertTrue(element("journalEditor.closed", in: app).waitForExistence(timeout: 5))

    relaunch(app, storeName: storeName)
    let relaunchedProse = app.textViews["journalEditor.prose"]
    XCTAssertTrue(relaunchedProse.waitForExistence(timeout: 5))
    XCTAssertEqual(relaunchedProse.value as? String, "Field notes\nSecond line")
    XCTAssertTrue(app.buttons["journalEditor.delete"].exists)

    replaceText(in: relaunchedProse, with: "")
    XCTAssertTrue(waitForLabel("Saved", on: element("journalEditor.status", in: app)))
    app.terminate()
    relaunch(app, storeName: storeName)

    let emptiedProse = app.textViews["journalEditor.prose"]
    XCTAssertTrue(emptiedProse.waitForExistence(timeout: 5))
    XCTAssertEqual(emptiedProse.value as? String ?? "", "")
    XCTAssertTrue(app.buttons["journalEditor.delete"].exists)

    app.buttons["journalEditor.delete"].tap()
    XCTAssertTrue(app.alerts["Delete this entry?"].waitForExistence(timeout: 2))
    app.alerts["Delete this entry?"].buttons["Cancel"].tap()
    XCTAssertTrue(emptiedProse.exists)

    app.buttons["journalEditor.delete"].tap()
    XCTAssertTrue(app.alerts["Delete this entry?"].waitForExistence(timeout: 2))
    app.alerts["Delete this entry?"].buttons["Delete entry"].tap()
    XCTAssertTrue(element("journalEditor.deleted", in: app).waitForExistence(timeout: 5))
  }

  @MainActor
  func testFailedSaveRetainsProseKeyboardAndRetry() {
    XCUIDevice.shared.orientation = .portrait
    let app = launch(
      storeName: "JournalEditingFailureUITests-\(UUID().uuidString)",
      reset: true,
      failsSaves: true
    )
    let prose = app.textViews["journalEditor.prose"]
    XCTAssertTrue(prose.waitForExistence(timeout: 5))
    prose.typeText("Unsaved field note")

    let failure = element("journalEditor.failure", in: app)
    XCTAssertTrue(failure.waitForExistence(timeout: 5))
    XCTAssertEqual(failure.label, "This entry could not be saved.")
    XCTAssertEqual(prose.value as? String, "Unsaved field note")
    XCTAssertTrue(app.keyboards.firstMatch.exists)
    XCTAssertFalse(element("journalEditor.status", in: app).exists)

    let retry = app.buttons["journalEditor.failure.retry"]
    XCTAssertEqual(retry.label, "Try again")
    retry.tap()
    XCTAssertTrue(failure.waitForExistence(timeout: 2))
    XCTAssertEqual(prose.value as? String, "Unsaved field note")
    XCTAssertTrue(app.keyboards.firstMatch.exists)
    recordScreenshot("journal-editor-save-failure", of: app)
  }

  @MainActor
  func testLargeTextLandscapeAndKeyboardClearance() throws {
    XCUIDevice.shared.orientation = .portrait
    defer { XCUIDevice.shared.orientation = .portrait }
    let app = launch(
      storeName: "JournalEditingAdaptiveUITests-\(UUID().uuidString)",
      reset: true,
      additionalArguments: [
        "-UIPreferredContentSizeCategoryName",
        "UICTContentSizeCategoryAccessibilityXXL",
        "-UIAccessibilityReduceMotionEnabled",
        "YES",
      ]
    )
    let screen = element("journalEditor.screen", in: app)
    let prose = app.textViews["journalEditor.prose"]
    XCTAssertTrue(screen.waitForExistence(timeout: 5))
    XCTAssertTrue(prose.waitForExistence(timeout: 2))
    let keyboard = app.keyboards.firstMatch
    XCTAssertTrue(keyboard.waitForExistence(timeout: 2))
    XCTAssertLessThanOrEqual(prose.frame.maxY, keyboard.frame.minY)
    assertMinimumHitRegion(app.buttons["journalEditor.back"])
    for scope in ["Today", "Yesterday"] {
      assertMinimumHitRegion(app.buttons["journalEditor.scope.\(scope)"])
    }
    try app.performAccessibilityAudit(
      for: acceptanceAuditTypes.subtracting([.hitRegion, .textClipped])
    )
    recordScreenshot("journal-editor-accessibility-text", of: app)

    XCUIDevice.shared.orientation = .landscapeLeft
    let landscape = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        let frame = app.windows.firstMatch.frame
        return frame.width > frame.height
      },
      object: app
    )
    XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
    XCTAssertTrue(app.keyboards.firstMatch.exists)
    let landscapeProse = app.textViews["journalEditor.prose"]
    let window = app.windows.firstMatch
    XCTAssertTrue(landscapeProse.isHittable)
    XCTAssertGreaterThanOrEqual(landscapeProse.frame.minX, window.frame.minX)
    XCTAssertLessThanOrEqual(landscapeProse.frame.maxX, window.frame.maxX)
    XCTAssertGreaterThanOrEqual(landscapeProse.frame.minY, window.frame.minY)
    XCTAssertLessThanOrEqual(landscapeProse.frame.maxY, window.frame.maxY)
    XCTAssertGreaterThanOrEqual(landscapeProse.frame.height, 44)
    recordScreenshot("journal-editor-landscape", of: app)
  }

  @MainActor
  private func launch(
    storeName: String,
    reset: Bool,
    failsSaves: Bool = false,
    additionalArguments: [String] = []
  ) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = launchArguments(
      storeName: storeName,
      reset: reset,
      failsSaves: failsSaves,
      additionalArguments: additionalArguments
    )
    app.launch()
    return app
  }

  @MainActor
  private func relaunch(_ app: XCUIApplication, storeName: String) {
    app.launchArguments = launchArguments(
      storeName: storeName,
      reset: false,
      failsSaves: false,
      additionalArguments: []
    )
    app.launch()
  }

  private func launchArguments(
    storeName: String,
    reset: Bool,
    failsSaves: Bool,
    additionalArguments: [String]
  ) -> [String] {
    var arguments = [
      "-tend-ui-testing",
      "-tend-ui-test-store",
      storeName,
      "-tend-ui-test-instant",
      fixedInstant,
      "-tend-journal-editor",
      "-AppleLocale",
      "en_US",
      "-AppleLanguages",
      "(en)",
      "-AppleTimeZone",
      "UTC",
    ]
    if reset { arguments.append("-tend-ui-test-reset") }
    if failsSaves { arguments.append("-tend-journal-editor-fail-save") }
    arguments.append(contentsOf: additionalArguments)
    return arguments
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
  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }

  @MainActor
  private func waitForLabel(_ label: String, on element: XCUIElement) -> Bool {
    let result =
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label),
            object: element
          )
        ],
        timeout: 5
      ) == .completed
    if !result {
      print("Unexpected element while waiting for \(label): \(element.debugDescription)")
    }
    return result
  }

  @MainActor
  private func replaceText(in element: XCUIElement, with replacement: String) {
    element.tap()
    element.press(forDuration: 1)
    let selectAll = XCUIApplication().menuItems["Select All"]
    if selectAll.waitForExistence(timeout: 2) {
      selectAll.tap()
    }
    element.typeText(XCUIKeyboardKey.delete.rawValue)
    if !replacement.isEmpty {
      element.typeText(replacement)
    }
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
