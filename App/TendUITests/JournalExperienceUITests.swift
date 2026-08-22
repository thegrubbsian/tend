import XCTest

final class JournalExperienceUITests: XCTestCase {
  private let fixedInstant = "2026-08-05T12:00:00Z"
  private let todayEntryID = "B1000000-0000-0000-0000-000000000001"
  private let oldEntryID = "B1000000-0000-0000-0000-000000000002"
  private let emptyEntryID = "B1000000-0000-0000-0000-000000000003"
  private let habitID = "B2000000-0000-0000-0000-000000000001"

  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testEmptyJournalCreatesTodayBackfillsYesterdayAndRelaunchesToToday() throws {
    XCUIDevice.shared.orientation = .portrait
    let storeName = "JournalExperienceEmpty-\(UUID().uuidString)"
    let app = launch(storeName: storeName, reset: true)
    openJournal(in: app)

    XCTAssertTrue(element("journal.overview", in: app).waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["journal.today"].label, "Write today's page")
    XCTAssertEqual(element("journal.month.title", in: app).label, "AUGUST 2026")
    XCTAssertEqual(element("journal.past.empty", in: app).label, "No earlier pages yet.")
    XCTAssertFalse(app.searchFields.firstMatch.exists)
    recordScreenshot("journal-empty", of: app)

    app.buttons["journal.today"].tap()
    let prose = app.textViews["journalEditor.prose"]
    XCTAssertTrue(prose.waitForExistence(timeout: 5))
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
    XCTAssertEqual(prose.value as? String ?? "", "")
    prose.typeText("First page\nThe rest of today")
    XCTAssertTrue(waitForLabel("Saved", on: element("journalEditor.status", in: app)))
    app.buttons["journalEditor.back"].tap()

    XCTAssertTrue(element("journal.overview", in: app).waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["journal.today"].label, "First page")

    app.buttons["journal.today"].tap()
    XCTAssertTrue(app.buttons["journalEditor.scope.Yesterday"].waitForExistence(timeout: 5))
    app.buttons["journalEditor.scope.Yesterday"].tap()
    let yesterdayProse = app.textViews["journalEditor.prose"]
    XCTAssertTrue(yesterdayProse.waitForExistence(timeout: 5))
    XCTAssertEqual(yesterdayProse.value as? String ?? "", "")
    yesterdayProse.typeText("Yesterday in the beds")
    XCTAssertTrue(waitForLabel("Saved", on: element("journalEditor.status", in: app)))
    app.buttons["journalEditor.back"].tap()

    let yesterdayRow = app.buttons.matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
        "journal.entry.",
        "Yesterday in the beds"
      )
    ).firstMatch
    XCTAssertTrue(yesterdayRow.waitForExistence(timeout: 5))
    XCTAssertTrue((yesterdayRow.value as? String)?.contains("August 4, 2026") == true)
    recordScreenshot("journal-today-and-yesterday", of: app)

    app.terminate()
    app.launchArguments = launchArguments(storeName: storeName, reset: false)
    app.launch()
    XCTAssertTrue(element("shell.destination.today", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["shell.tab.today"].isSelected)
    XCTAssertFalse(app.buttons["shell.tab.journal"].isSelected)
  }

  @MainActor
  func testHistoryOldEditDeleteAndLiveHabitMutationStayTruthful() throws {
    XCUIDevice.shared.orientation = .portrait
    let app = launch(
      storeName: "JournalExperienceHistory-\(UUID().uuidString)",
      reset: true,
      fixture: "journal-experience"
    )
    openJournal(in: app)

    XCTAssertEqual(app.buttons["journal.today"].label, "Today among the tomatoes")
    XCTAssertEqual(
      app.buttons.matching(
        NSPredicate(format: "identifier BEGINSWITH %@", "journal.entry.")
      ).allElementsBoundByIndex.map(\.identifier),
      ["journal.entry.\(oldEntryID)", "journal.entry.\(emptyEntryID)"]
    )
    XCTAssertEqual(app.buttons["journal.entry.\(emptyEntryID)"].label, "No text")

    app.buttons["journal.today"].tap()
    XCTAssertTrue(element("journalGarden.section", in: app).waitForExistence(timeout: 5))
    XCTAssertEqual(element("journalGarden.progress.\(habitID)", in: app).label, "0 of 1 time")
    XCTAssertEqual(element("journalGarden.leaf.\(habitID)", in: app).value as? String, "Hollow")

    app.buttons["shell.tab.today"].tap()
    XCTAssertTrue(element("shell.destination.today", in: app).waitForExistence(timeout: 5))
    let logButton = app.buttons["today.log.Water seedlings"]
    makeHittable(logButton, in: app)
    logButton.tap()
    XCTAssertTrue((logButton.value as? String)?.contains("1 of 1 time") == true)

    app.buttons["shell.tab.journal"].tap()
    XCTAssertTrue(element("journalGarden.section", in: app).waitForExistence(timeout: 5))
    XCTAssertEqual(element("journalGarden.progress.\(habitID)", in: app).label, "1 of 1 time")
    XCTAssertEqual(element("journalGarden.leaf.\(habitID)", in: app).value as? String, "Filled")
    app.buttons["journalEditor.back"].tap()

    let oldRow = app.buttons["journal.entry.\(oldEntryID)"]
    makeHittable(oldRow, in: app)
    oldRow.tap()
    let oldProse = app.textViews["journalEditor.prose"]
    XCTAssertTrue(oldProse.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["journalEditor.delete"].exists)
    replaceText(in: oldProse, with: "Revised seedling notes\nKept forever")
    XCTAssertTrue(waitForLabel("Saved", on: element("journalEditor.status", in: app)))
    app.buttons["journalEditor.back"].tap()
    XCTAssertEqual(
      app.buttons["journal.entry.\(oldEntryID)"].label, "Revised seedling notes")

    let previousMonth = app.buttons["journal.month.previous"]
    makeHittable(previousMonth, in: app)
    previousMonth.tap()
    XCTAssertEqual(element("journal.month.title", in: app).label, "JULY 2026")
    XCTAssertTrue(app.buttons["journal.month.day.2026-07-10"].exists)

    app.buttons["journal.today"].tap()
    XCTAssertTrue(app.buttons["journalEditor.delete"].waitForExistence(timeout: 5))
    app.buttons["journalEditor.delete"].tap()
    XCTAssertTrue(app.alerts["Delete this entry?"].waitForExistence(timeout: 2))
    app.alerts["Delete this entry?"].buttons["Delete entry"].tap()
    XCTAssertTrue(element("journal.overview", in: app).waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["journal.today"].label, "Write today's page")
    recordScreenshot("journal-history-mutated", of: app)
  }

  @MainActor
  func testLoadAndSaveFailuresKeepIdentityAndOfferRetry() {
    XCUIDevice.shared.orientation = .portrait
    let loadFailureApp = launch(
      storeName: "JournalExperienceLoadFailure-\(UUID().uuidString)",
      reset: true,
      fixture: "journal-load-failure"
    )
    openJournal(in: loadFailureApp)
    let loadFailure = loadFailureApp.staticTexts["Journal is unavailable right now."]
    XCTAssertTrue(loadFailure.waitForExistence(timeout: 5))
    XCTAssertFalse(element("journal.today", in: loadFailureApp).exists)
    XCTAssertFalse(element("journal.month", in: loadFailureApp).exists)
    loadFailureApp.buttons["journal.failure.retry"].tap()
    XCTAssertTrue(loadFailure.waitForExistence(timeout: 2))
    XCTAssertTrue(loadFailureApp.buttons["shell.tab.journal"].isSelected)
    recordScreenshot("journal-load-failure", of: loadFailureApp)

    loadFailureApp.terminate()
    let saveFailureApp = launch(
      storeName: "JournalExperienceSaveFailure-\(UUID().uuidString)",
      reset: true,
      additionalArguments: ["-tend-journal-editor-fail-first-save"]
    )
    openJournal(in: saveFailureApp)
    saveFailureApp.buttons["journal.today"].tap()
    let prose = saveFailureApp.textViews["journalEditor.prose"]
    XCTAssertTrue(prose.waitForExistence(timeout: 5))
    prose.typeText("Keep this field note")
    let saveFailure = element("journalEditor.failure", in: saveFailureApp)
    XCTAssertTrue(saveFailure.waitForExistence(timeout: 5))
    XCTAssertEqual(prose.value as? String, "Keep this field note")
    saveFailureApp.buttons["journalEditor.failure.retry"].tap()
    XCTAssertTrue(waitForLabel("Saved", on: element("journalEditor.status", in: saveFailureApp)))
    saveFailureApp.buttons["journalEditor.back"].tap()
    XCTAssertEqual(
      saveFailureApp.buttons["journal.today"].label, "Keep this field note")
    recordScreenshot("journal-save-recovered", of: saveFailureApp)
  }

  @MainActor
  func testRouteFailureHidesMountedEditorWithoutLosingJournalSelection() {
    XCUIDevice.shared.orientation = .portrait
    let app = launch(
      storeName: "JournalExperienceRouteFailure-\(UUID().uuidString)",
      reset: true,
      fixture: "journal-experience",
      additionalArguments: ["-tend-journal-route-failure-control"]
    )
    openJournal(in: app)
    app.buttons["journal.today"].tap()
    XCTAssertTrue(app.textViews["journalEditor.prose"].waitForExistence(timeout: 5))

    let corrupt = app.buttons["journal.fixture.corrupt-route"]
    XCTAssertTrue(corrupt.waitForExistence(timeout: 5))
    corrupt.tap()

    let failure = app.staticTexts["journal.route.failure"]
    XCTAssertTrue(failure.waitForExistence(timeout: 5))
    XCTAssertEqual(failure.label, "This Journal page could not be loaded.")
    XCTAssertFalse(app.textViews["journalEditor.prose"].exists)
    XCTAssertFalse(app.buttons["journalEditor.back"].exists)
    XCTAssertFalse(app.buttons["journalEditor.delete"].exists)
    XCTAssertTrue(app.buttons["journal.route.failure.retry"].exists)
    XCTAssertTrue(app.buttons["shell.tab.journal"].isSelected)

    app.buttons["journal.route.failure.retry"].tap()
    let recoveredProse = app.textViews["journalEditor.prose"]
    XCTAssertTrue(recoveredProse.waitForExistence(timeout: 5))
    XCTAssertEqual(recoveredProse.value as? String, "Pending route failure draft")
    XCTAssertTrue(waitForLabel("Saved", on: element("journalEditor.status", in: app)))
    app.buttons["journalEditor.back"].tap()
    XCTAssertEqual(app.buttons["journal.today"].label, "Pending route failure draft")
  }

  @MainActor
  func testDestinationPreservesSelectionAndAdaptsForLargeTextLandscape() throws {
    XCUIDevice.shared.orientation = .portrait
    defer { XCUIDevice.shared.orientation = .portrait }
    let app = launch(
      storeName: "JournalExperienceAdaptive-\(UUID().uuidString)",
      reset: true,
      fixture: "journal-experience",
      additionalArguments: [
        "-UIPreferredContentSizeCategoryName",
        "UICTContentSizeCategoryAccessibilityXXL",
        "-UIAccessibilityReduceMotionEnabled",
        "YES",
      ]
    )
    openJournal(in: app)
    let overview = element("journal.overview", in: app)
    XCTAssertTrue(overview.waitForExistence(timeout: 5))
    try app.performAccessibilityAudit(for: acceptanceAuditTypes)

    XCUIDevice.shared.press(.home)
    app.activate()
    XCTAssertTrue(overview.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["shell.tab.journal"].isSelected)

    XCUIDevice.shared.orientation = .landscapeLeft
    let landscape = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in app.frame.width > app.frame.height },
      object: app
    )
    XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
    XCTAssertTrue(overview.exists)
    XCTAssertLessThanOrEqual(overview.frame.maxX, app.windows.firstMatch.frame.maxX)
    recordScreenshot("journal-overview-accessibility-landscape", of: app)
  }

  @MainActor
  private func openJournal(in app: XCUIApplication) {
    let journalTab = app.buttons["shell.tab.journal"]
    XCTAssertTrue(journalTab.waitForExistence(timeout: 5))
    journalTab.tap()
    XCTAssertTrue(element("shell.destination.journal", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(journalTab.isSelected)
  }

  @MainActor
  private func launch(
    storeName: String,
    reset: Bool,
    fixture: String? = nil,
    additionalArguments: [String] = []
  ) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = launchArguments(
      storeName: storeName,
      reset: reset,
      fixture: fixture,
      additionalArguments: additionalArguments
    )
    app.launch()
    return app
  }

  private func launchArguments(
    storeName: String,
    reset: Bool,
    fixture: String? = nil,
    additionalArguments: [String] = []
  ) -> [String] {
    var arguments = [
      "-tend-ui-testing",
      "-tend-ui-test-store",
      storeName,
      "-tend-ui-test-instant",
      fixedInstant,
      "-AppleLocale",
      "en_US",
      "-AppleLanguages",
      "(en)",
      "-AppleTimeZone",
      "UTC",
    ]
    if reset { arguments.append("-tend-ui-test-reset") }
    if let fixture {
      arguments.append(contentsOf: ["-tend-ui-test-fixture", fixture])
    }
    arguments.append(contentsOf: additionalArguments)
    return arguments
  }

  @MainActor
  private func makeHittable(_ target: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<12 where !target.isHittable {
      app.swipeUp(velocity: .slow)
    }
    XCTAssertTrue(target.isHittable)
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
    element.typeText(replacement)
  }

  @MainActor
  private func waitForLabel(_ label: String, on element: XCUIElement) -> Bool {
    XCTWaiter.wait(
      for: [
        XCTNSPredicateExpectation(
          predicate: NSPredicate(format: "label == %@", label),
          object: element
        )
      ],
      timeout: 5
    ) == .completed
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
  private func recordScreenshot(_ name: String, of app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
