import UIKit
import XCTest

final class FastLoggingUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  private let fixtureInstantArgument = "2026-08-05T19:00:00Z"
  private let laterFixtureInstantArgument = "2026-08-05T20:00:00Z"
  private let weeklyFixtureInstantArgument = "2027-01-04T20:00:00Z"

  @MainActor
  func testQuantityLoggingJourneys() throws {
    try verifyFocusedAmountEditorHidesPendingUndo()
    try verifyDailyCurrentQuickAddCustomAmountDeleteAndRelaunch()
    try verifyWeeklyPriorSetTotalValidationAndUndo()
    try verifyAdaptiveQuantitySheet()
  }

  @MainActor
  private func verifyFocusedAmountEditorHidesPendingUndo() throws {
    let app = launch(
      fixture: "fast-logging-daily",
      storeName: evidenceStoreName(journey: "focused-undo")
    )

    XCTAssertTrue(app.otherElements["today.dashboard"].waitForExistence(timeout: 5))
    let logButton = app.buttons["today.log.Walk 8K steps"]
    makeHittable(logButton, above: app.buttons["shell.tab.today"], in: app)
    logButton.tap()

    let sheet = element("log-sheet", in: app)
    XCTAssertTrue(sheet.waitForExistence(timeout: 5))
    dragSheetToLargeDetent(sheet, in: app)
    let quickAdd = app.buttons["log-sheet.quick-add.1000"]
    makeHittable(quickAdd, direction: .up, in: app)
    quickAdd.tap()

    let undo = element("log-sheet.undo", in: app)
    XCTAssertTrue(undo.waitForExistence(timeout: 2))
    let customAmount = app.buttons["log-sheet.amount.custom"]
    makeHittable(customAmount, direction: .up, in: app)
    customAmount.tap()

    let editor = element("log-sheet.amount-editor", in: app)
    XCTAssertTrue(editor.waitForExistence(timeout: 2))
    XCTAssertFalse(undo.exists)
    app.buttons["log-sheet.amount.keyboard-cancel"].tap()
    XCTAssertTrue(waitForDisappearance(editor))
    XCTAssertTrue(element("log-sheet.quick-add.title", in: app).waitForExistence(timeout: 2))
  }

  @MainActor
  func testTimesLoggingJourneys() throws {
    try verifyDailyTargetOneRoutingAndReducedMotion()
    try verifyWeeklyCountGraceUndoAndRelaunch()
  }

  @MainActor
  private func verifyDailyTargetOneRoutingAndReducedMotion() throws {
    let storeName = evidenceStoreName(journey: "times-daily")
    let app = launch(
      fixture: "fast-logging-daily",
      storeName: storeName,
      additionalArguments: [
        "-UIAccessibilityReduceMotionEnabled",
        "YES",
      ]
    )

    XCTAssertTrue(app.otherElements["today.dashboard"].waitForExistence(timeout: 5))
    let summary = element("today.summary", in: app)
    XCTAssertEqual(summary.label, "2 of 5")
    let tabButton = app.buttons["shell.tab.today"]
    let tendedSection = element("today.section.tended", in: app)
    let targetOne = app.buttons["today.log.Feed the cat"]
    makeHittable(targetOne, above: tabButton, in: app)
    XCTAssertEqual(targetOne.label, "Feed the cat")
    assertValueContains("0 of 1 time", for: targetOne)
    XCTAssertEqual(targetOne.value as? String, "0 of 1 time, 0 days, Unmet")
    assertMinimumTarget(targetOne)
    XCTAssertEqual(targetOne.frame.width, 52, accuracy: 0.5)
    XCTAssertEqual(targetOne.frame.height, 52, accuracy: 0.5)
    XCTAssertLessThan(targetOne.frame.maxY, tendedSection.frame.minY)
    XCTAssertLessThanOrEqual(targetOne.frame.maxY, tabButton.frame.minY)
    XCTAssertFalse(app.buttons["today.row.Feed the cat"].exists)
    assertAccessibilityOrder(
      ["today.title", "today.summary", "today.section.to-tend", "today.row.Feed the cat"],
      in: app
    )
    try performAccessibilityAudit(in: app, context: .today)
    recordScreenshot("times-daily-empty", of: app)

    targetOne.tap()

    assertValueContains("1 of 1 time", for: targetOne)
    XCTAssertEqual(targetOne.value as? String, "1 of 1 time, 1 day, Met")
    assertLabel("3 of 5", for: summary)
    makeHittable(targetOne, above: tabButton, in: app)
    XCTAssertGreaterThan(targetOne.frame.minY, tendedSection.frame.maxY)
    XCTAssertEqual(targetOne.frame.width, 44, accuracy: 0.5)
    XCTAssertEqual(targetOne.frame.height, 44, accuracy: 0.5)
    XCTAssertLessThanOrEqual(targetOne.frame.maxY, tabButton.frame.minY)
    XCTAssertFalse(element("log-sheet", in: app).exists)
    let undo = element("today.undo.Feed the cat", in: app)
    XCTAssertTrue(undo.waitForExistence(timeout: 2))
    XCTAssertEqual(undo.label, "Feed the cat. Logged 1 times. Undo available.")
    let undoButton = app.buttons["today.undo.action.Feed the cat"]
    assertMinimumTarget(undoButton)
    XCTAssertLessThanOrEqual(undoButton.frame.maxY, tabButton.frame.minY)
    recordScreenshot("times-daily-undo", of: app)
    undoButton.tap()
    assertValueContains("0 of 1 time", for: targetOne)
    XCTAssertEqual(targetOne.value as? String, "0 of 1 time, 0 days, Unmet")
    assertLabel("2 of 5", for: summary)
    makeHittable(targetOne, above: tabButton, in: app)
    XCTAssertLessThan(targetOne.frame.maxY, tendedSection.frame.minY)
    XCTAssertTrue(waitForDisappearance(undo))

    makeHittable(targetOne, above: tabButton, in: app)
    targetOne.tap()
    assertValueContains("1 of 1 time", for: targetOne)
    XCTAssertEqual(targetOne.value as? String, "1 of 1 time, 1 day, Met")
    XCTAssertFalse(element("log-sheet", in: app).exists)
    recordScreenshot("times-daily-complete", of: app)
    app.terminate()
    app.launchArguments = launchArguments(
      storeName: storeName,
      reset: false,
      fixture: nil,
      fixtureInstant: laterFixtureInstantArgument
    )
    app.launch()

    XCTAssertTrue(app.otherElements["today.dashboard"].waitForExistence(timeout: 5))
    let relaunchedTargetOne = app.buttons["today.log.Feed the cat"]
    makeHittable(relaunchedTargetOne, above: app.buttons["shell.tab.today"], in: app)
    assertValueContains("1 of 1 time", for: relaunchedTargetOne)
    XCTAssertEqual(element("today.summary", in: app).label, "3 of 5")
    XCTAssertFalse(element("today.undo.Feed the cat", in: app).exists)
    XCTAssertFalse(element("log-sheet", in: app).exists)
    XCTAssertFalse(element("log-sheet.amount-editor", in: app).exists)

    let exactTime = app.buttons["today.log.Meditate"]
    makeHittable(exactTime, above: app.buttons["shell.tab.today"], in: app)
    assertValueContains("0 of 10 time", for: exactTime)
    exactTime.tap()
    let sheet = element("log-sheet", in: app)
    XCTAssertTrue(sheet.waitForExistence(timeout: 5))
    assertSheetGeometry(sheet, in: app)
    XCTAssertEqual(element("log-sheet.progress", in: app).label, "0 of 10 time")
    dismissSheet(sheet, in: app)
    XCTAssertFalse(element("log-sheet.amount-editor", in: app).exists)
    assertValueContains("0 of 10 time", for: exactTime)

    let quantity = app.buttons["today.log.Walk 8K steps"]
    makeHittable(quantity, above: app.buttons["shell.tab.today"], in: app)
    assertValueContains("4,000 of 8,000 steps", for: quantity)
    quantity.tap()
    XCTAssertTrue(sheet.waitForExistence(timeout: 5))
    assertSheetGeometry(sheet, in: app)
    XCTAssertEqual(element("log-sheet.progress", in: app).label, "4,000 of 8,000 steps")
    dismissSheet(sheet, in: app)
    XCTAssertFalse(element("log-sheet.amount-editor", in: app).exists)
    assertValueContains("4,000 of 8,000 steps", for: quantity)
  }

  @MainActor
  private func verifyWeeklyCountGraceUndoAndRelaunch() throws {
    let storeName = evidenceStoreName(journey: "times-weekly")
    let app = launch(
      fixture: "fast-logging-weekly",
      storeName: storeName,
      fixtureInstant: weeklyFixtureInstantArgument
    )

    XCTAssertTrue(app.otherElements["today.dashboard"].waitForExistence(timeout: 5))
    let summary = element("today.summary", in: app)
    XCTAssertEqual(summary.label, "0 of 2")
    let tabButton = app.buttons["shell.tab.today"]
    let count = app.buttons["today.log.Weekly check-ins"]
    let risk = app.buttons["today.risk.Weekly check-ins"]
    makeHittable(risk, above: tabButton, in: app)
    XCTAssertEqual(risk.label, "Log Last Week for Weekly check-ins")
    assertValueContains("Last week open", for: risk)
    assertValueContains("3 week streak at risk", for: risk)
    XCTAssertEqual(
      count.value as? String,
      "1 of 3 times, 3 weeks, Unmet, Last week open · 3 week streak at risk"
    )
    assertMinimumTarget(risk)
    XCTAssertLessThanOrEqual(risk.frame.maxY, tabButton.frame.minY)
    recordScreenshot("times-weekly-grace-open", of: app)

    risk.tap()

    assertValueContains("1 of 3 times", for: count)
    XCTAssertTrue(risk.exists)
    XCTAssertFalse(element("log-sheet", in: app).exists)
    let undo = element("today.undo.Weekly check-ins", in: app)
    XCTAssertTrue(undo.waitForExistence(timeout: 2))
    XCTAssertEqual(undo.label, "Weekly check-ins. Logged 1 times. Undo available.")
    let undoButton = app.buttons["today.undo.action.Weekly check-ins"]
    assertMinimumTarget(undoButton)
    XCTAssertLessThanOrEqual(undoButton.frame.maxY, tabButton.frame.minY)
    recordScreenshot("times-weekly-grace-undo", of: app)

    makeHittable(risk, above: tabButton, in: app)
    risk.tap()
    assertValueContains("1 of 3 times", for: count)
    XCTAssertTrue(waitForDisappearance(risk))
    undoButton.tap()
    XCTAssertTrue(risk.waitForExistence(timeout: 2))

    makeHittable(risk, above: tabButton, in: app)
    risk.tap()
    XCTAssertTrue(waitForDisappearance(risk))
    XCTAssertEqual(count.value as? String, "1 of 3 times, 4 weeks, Unmet")

    makeHittable(count, above: tabButton, in: app)
    XCTAssertEqual(count.frame.width, 52, accuracy: 0.5)
    XCTAssertEqual(count.frame.height, 52, accuracy: 0.5)
    count.tap()
    assertValueContains("2 of 3 times", for: count)
    XCTAssertEqual(count.value as? String, "2 of 3 times, 4 weeks, Unmet")
    XCTAssertTrue(undo.exists)
    makeHittable(count, above: tabButton, in: app)
    count.tap()
    assertValueContains("3 of 3 times", for: count)
    XCTAssertEqual(count.value as? String, "3 of 3 times, 5 weeks, Met")
    assertLabel("1 of 2", for: summary)
    makeHittable(count, above: tabButton, in: app)
    XCTAssertEqual(count.frame.width, 44, accuracy: 0.5)
    XCTAssertEqual(count.frame.height, 44, accuracy: 0.5)

    undoButton.tap()
    assertValueContains("2 of 3 times", for: count)
    XCTAssertEqual(count.value as? String, "2 of 3 times, 4 weeks, Unmet")
    assertLabel("0 of 2", for: summary)
    XCTAssertTrue(waitForDisappearance(undo))

    makeHittable(count, above: tabButton, in: app)
    count.tap()
    assertValueContains("3 of 3 times", for: count)
    makeHittable(count, above: tabButton, in: app)
    count.tap()
    assertValueContains("4 of 3 times", for: count)
    XCTAssertEqual(count.value as? String, "4 of 3 times, 5 weeks, Met")
    XCTAssertFalse(element("log-sheet", in: app).exists)
    XCTAssertLessThanOrEqual(count.frame.maxY, tabButton.frame.minY)
    recordScreenshot("times-weekly-over-target", of: app)

    app.terminate()
    app.launchArguments = launchArguments(
      storeName: storeName,
      reset: false,
      fixture: nil,
      fixtureInstant: weeklyFixtureInstantArgument
    )
    app.launch()

    XCTAssertTrue(app.otherElements["today.dashboard"].waitForExistence(timeout: 5))
    let relaunchedCount = app.buttons["today.log.Weekly check-ins"]
    makeHittable(relaunchedCount, above: app.buttons["shell.tab.today"], in: app)
    assertValueContains("4 of 3 times", for: relaunchedCount)
    XCTAssertEqual(relaunchedCount.value as? String, "4 of 3 times, 5 weeks, Met")
    XCTAssertEqual(element("today.summary", in: app).label, "1 of 2")
    XCTAssertFalse(element("today.undo.Weekly check-ins", in: app).exists)
    XCTAssertFalse(element("log-sheet", in: app).exists)
    XCTAssertFalse(element("log-sheet.amount-editor", in: app).exists)
    recordScreenshot("times-weekly-relaunch", of: app)
  }
  @MainActor
  private func verifyDailyCurrentQuickAddCustomAmountDeleteAndRelaunch() throws {
    let storeName = evidenceStoreName(journey: "quantity-daily")
    let app = launch(fixture: "fast-logging-daily", storeName: storeName)

    XCTAssertTrue(app.otherElements["today.dashboard"].waitForExistence(timeout: 5))
    let sheet = element("log-sheet", in: app)

    let exactTimesButton = app.buttons["today.log.Feed the cat"]
    makeHittable(exactTimesButton, above: app.buttons["shell.tab.today"], in: app)
    assertValueContains("0 of 1 time", for: exactTimesButton)
    exactTimesButton.tap()
    assertValueContains("1 of 1 time", for: exactTimesButton)
    XCTAssertFalse(sheet.exists)
    let directUndo = element("today.undo.Feed the cat", in: app)
    XCTAssertTrue(directUndo.waitForExistence(timeout: 2))
    XCTAssertEqual(directUndo.label, "Feed the cat. Logged 1 times. Undo available.")
    app.buttons["today.undo.action.Feed the cat"].tap()
    assertValueContains("0 of 1 time", for: exactTimesButton)
    XCTAssertTrue(waitForDisappearance(directUndo))

    let exactTimeButton = app.buttons["today.log.Meditate"]
    makeHittable(exactTimeButton, above: app.buttons["shell.tab.today"], in: app)
    assertValueContains("0 of 10 time", for: exactTimeButton)
    exactTimeButton.tap()
    XCTAssertTrue(sheet.waitForExistence(timeout: 5))
    XCTAssertEqual(element("log-sheet.title", in: app).label, "Meditate")
    XCTAssertEqual(element("log-sheet.progress", in: app).label, "0 of 10 time")
    assertSheetGeometry(sheet, in: app)
    let emptyEntries = element("log-sheet.entries.empty", in: app)
    makeHittable(emptyEntries, direction: .up, in: app)
    XCTAssertEqual(emptyEntries.label, "Nothing logged in this period.")
    XCTAssertEqual(
      app.buttons.matching(
        NSPredicate(format: "identifier BEGINSWITH %@", "log-sheet.delete.")
      ).count,
      0
    )
    recordScreenshot("quantity-daily-empty-entries", of: app)
    dismissSheet(sheet, in: app)
    XCTAssertFalse(element("log-sheet.amount-editor", in: app).exists)
    assertValueContains("0 of 10 time", for: exactTimeButton)

    let riskButton = app.buttons["today.risk.Walk 8K steps"]
    makeHittable(riskButton, above: app.buttons["shell.tab.today"], in: app)
    riskButton.tap()
    XCTAssertTrue(sheet.waitForExistence(timeout: 5))
    assertSheetGeometry(sheet, in: app)
    let dailyGraceScope = app.buttons["log-sheet.scope.Yesterday"]
    XCTAssertTrue(dailyGraceScope.isSelected)
    XCTAssertEqual(dailyGraceScope.value as? String, "Unfinished")
    XCTAssertEqual(element("log-sheet.progress", in: app).label, "3,000 of 8,000 steps")
    dragSheetToLargeDetent(sheet, in: app)
    XCTAssertLessThan(sheet.frame.minY, app.frame.midY)
    try performAccessibilityAudit(in: app, sheet: sheet, context: .dailyGrace)
    dismissSheet(sheet, in: app)
    XCTAssertFalse(element("log-sheet.amount-editor", in: app).exists)

    let logButton = app.buttons["today.log.Walk 8K steps"]
    makeHittable(logButton, above: app.buttons["shell.tab.today"], in: app)
    XCTAssertEqual(logButton.label, "Walk 8K steps")
    assertValueContains("4,000 of 8,000 steps", for: logButton)
    assertMinimumTarget(logButton)
    logButton.tap()

    let progress = element("log-sheet.progress", in: app)
    XCTAssertTrue(sheet.waitForExistence(timeout: 5))
    XCTAssertEqual(element("log-sheet.title", in: app).label, "Walk 8K steps")
    XCTAssertEqual(progress.label, "4,000 of 8,000 steps")
    XCTAssertEqual(element("log-sheet.streak", in: app).label, "3 day streak")
    assertSheetGeometry(sheet, in: app)
    let currentScope = app.buttons["log-sheet.scope.Today"]
    let priorScope = app.buttons["log-sheet.scope.Yesterday"]
    XCTAssertTrue(currentScope.isSelected)
    XCTAssertTrue(priorScope.exists)
    assertMinimumTarget(currentScope)
    assertMinimumTarget(priorScope)
    assertAccessibilityOrder(
      [
        "log-sheet.title",
        "log-sheet.scope.Today",
        "log-sheet.scope.Yesterday",
        "log-sheet.progress",
      ],
      in: app
    )
    recordScreenshot("quantity-daily-current-sheet", of: app)
    dragSheetToLargeDetent(sheet, in: app)
    XCTAssertLessThan(sheet.frame.minY, app.frame.midY)
    try performAccessibilityAudit(in: app, sheet: sheet, context: .dailyCurrent)

    let quickAdd = app.buttons["log-sheet.quick-add.1000"]
    makeHittable(quickAdd, direction: .up, in: app)
    assertMinimumTarget(quickAdd)
    quickAdd.tap()

    assertLabel("5,000 of 8,000 steps", for: progress)
    XCTAssertTrue(sheet.exists)
    let undo = element("log-sheet.undo", in: app)
    XCTAssertTrue(undo.waitForExistence(timeout: 2))
    XCTAssertEqual(undo.label, "Walk 8K steps. Logged 1,000 steps. Undo available.")
    let undoButton = app.buttons["log-sheet.undo.action"]
    assertMinimumTarget(undoButton)
    recordScreenshot("quantity-daily-current-undo", of: app)
    undoButton.tap()
    assertLabel("4,000 of 8,000 steps", for: progress)
    XCTAssertTrue(waitForDisappearance(undo))

    let customAmount = app.buttons["log-sheet.amount.custom"]
    makeHittable(customAmount, direction: .up, in: app)
    assertMinimumTarget(customAmount)
    customAmount.tap()

    let amountField = app.textFields["log-sheet.amount.field"]
    XCTAssertTrue(amountField.waitForExistence(timeout: 2))
    XCTAssertTrue(app.buttons["log-sheet.amount.keyboard-submit"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.buttons["log-sheet.amount.keyboard-cancel"].exists)
    assertMinimumTarget(amountField)
    let submitAmount = app.buttons["log-sheet.amount.submit"]
    let cancelAmount = app.buttons["log-sheet.amount.cancel"]
    XCTAssertFalse(submitAmount.exists)
    XCTAssertFalse(cancelAmount.exists)

    let keyboardSubmit = app.buttons["log-sheet.amount.keyboard-submit"]
    let keyboardCancel = app.buttons["log-sheet.amount.keyboard-cancel"]
    let invalidInputs = [
      "",
      "0",
      "-1",
      "1.5",
      String(repeating: "9", count: 40),
    ]
    for input in invalidInputs {
      if !input.isEmpty {
        replaceText(in: amountField, with: input)
      }
      XCTAssertTrue(keyboardSubmit.waitForExistence(timeout: 2))
      keyboardSubmit.tap()
      XCTAssertEqual(
        element("log-sheet.amount.error", in: app).label,
        "Enter a positive whole number."
      )
      if !input.isEmpty {
        assertFieldRetainsKeyboardFocus(amountField)
      }
    }
    let validationEditor = element("log-sheet.amount-editor", in: app)
    XCTAssertTrue(validationEditor.exists)
    XCTAssertEqual(app.buttons.matching(identifier: "log-sheet.amount.keyboard-cancel").count, 1)
    XCTAssertTrue(keyboardCancel.isHittable)
    XCTAssertTrue(element("log-sheet.title", in: app).exists)
    XCTAssertFalse(app.buttons["log-sheet.scope.Today"].exists)
    XCTAssertFalse(element("log-sheet.progress", in: app).exists)
    XCTAssertFalse(element("log-sheet.quick-add.title", in: app).exists)
    XCTAssertFalse(element("log-sheet.entries.title", in: app).exists)
    recordScreenshot("quantity-daily-validation-keyboard", of: app)
    keyboardCancel.tap()
    XCTAssertTrue(waitForDisappearance(validationEditor))
    XCTAssertTrue(element("log-sheet.entries.title", in: app).waitForExistence(timeout: 2))
    XCTAssertTrue(element("log-sheet.quick-add.title", in: app).waitForExistence(timeout: 2))
    assertLabel("4,000 of 8,000 steps", for: progress)

    customAmount.tap()
    XCTAssertTrue(amountField.waitForExistence(timeout: 2))
    replaceText(in: amountField, with: "750")
    XCTAssertTrue(keyboardSubmit.waitForExistence(timeout: 2))
    keyboardSubmit.tap()
    assertLabel("4,750 of 8,000 steps", for: progress)
    XCTAssertTrue(sheet.exists)
    XCTAssertEqual(
      element("log-sheet.undo", in: app).label,
      "Walk 8K steps. Logged 750 steps. Undo available."
    )

    makeHittable(quickAdd, direction: .down, in: app)
    quickAdd.tap()
    assertLabel("5,750 of 8,000 steps", for: progress)

    let addedEntryDeleteQuery = app.buttons.matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
        "log-sheet.delete.",
        "1,000 steps"
      )
    )
    XCTAssertEqual(addedEntryDeleteQuery.count, 1)
    let addedEntryDelete = addedEntryDeleteQuery.element(boundBy: 0)
    makeHittable(addedEntryDelete, direction: .up, in: app)
    assertMinimumTarget(addedEntryDelete)
    addedEntryDelete.tap()
    assertLabel("4,750 of 8,000 steps", for: progress)
    XCTAssertTrue(sheet.exists)

    app.terminate()
    app.launchArguments = launchArguments(
      storeName: storeName,
      reset: false,
      fixture: nil,
      fixtureInstant: laterFixtureInstantArgument
    )
    app.launch()

    XCTAssertTrue(app.otherElements["today.dashboard"].waitForExistence(timeout: 5))
    XCTAssertFalse(element("today.undo.Walk 8K steps", in: app).exists)
    XCTAssertFalse(element("log-sheet", in: app).exists)
    XCTAssertFalse(element("log-sheet.amount-editor", in: app).exists)
    let relaunchedLogButton = app.buttons["today.log.Walk 8K steps"]
    makeHittable(relaunchedLogButton, above: app.buttons["shell.tab.today"], in: app)
    XCTAssertTrue(
      (relaunchedLogButton.value as? String)?.contains("4,750 of 8,000 steps") == true
    )
    relaunchedLogButton.tap()
    XCTAssertTrue(element("log-sheet", in: app).waitForExistence(timeout: 5))
    assertSheetGeometry(element("log-sheet", in: app), in: app)
    XCTAssertFalse(element("log-sheet.amount-editor", in: app).exists)
    XCTAssertEqual(element("log-sheet.progress", in: app).label, "4,750 of 8,000 steps")

    let relaunchedProgress = element("log-sheet.progress", in: app)
    let laterCustomAmount = app.buttons["log-sheet.amount.custom"]
    makeHittable(laterCustomAmount, direction: .up, in: app)
    laterCustomAmount.tap()
    let laterAmountField = app.textFields["log-sheet.amount.field"]
    XCTAssertTrue(laterAmountField.waitForExistence(timeout: 2))
    replaceText(in: laterAmountField, with: "250")
    app.buttons["log-sheet.amount.keyboard-submit"].tap()
    assertLabel("5,000 of 8,000 steps", for: relaunchedProgress)
    makeHittable(element("log-sheet.entries.title", in: app), direction: .up, in: app)
    let allRelaunchedDeleteQuery = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "log-sheet.delete.")
    )
    let allRelaunchedEntryIDs = Set(
      allRelaunchedDeleteQuery.allElementsBoundByIndex.map(\.identifier)
    )
    let newestEntryDeleteQuery = app.buttons.matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
        "log-sheet.delete.",
        "250 steps"
      )
    )
    XCTAssertEqual(newestEntryDeleteQuery.count, 1)
    let newestEntryDelete = newestEntryDeleteQuery.element(boundBy: 0)
    let newestEntryID = newestEntryDelete.identifier
    let survivingEntryIDs = allRelaunchedEntryIDs.subtracting([newestEntryID])
    makeHittable(newestEntryDelete, direction: .up, in: app)
    newestEntryDelete.tap()
    assertLabel("4,750 of 8,000 steps", for: relaunchedProgress)
    let remainingEntryIDs = Set(
      app.buttons.matching(
        NSPredicate(format: "identifier BEGINSWITH %@", "log-sheet.delete.")
      ).allElementsBoundByIndex.map(\.identifier)
    )
    XCTAssertFalse(remainingEntryIDs.contains(newestEntryID))
    XCTAssertEqual(remainingEntryIDs, survivingEntryIDs)

    let finish = app.buttons["log-sheet.quick-add.finish"]
    makeHittable(finish, direction: .up, in: app)
    XCTAssertEqual(finish.label, "Finish with 3,250 steps")
    assertMinimumTarget(finish)
    finish.tap()
    assertLabel("8,000 of 8,000 steps", for: relaunchedProgress)
    XCTAssertTrue(waitForDisappearance(finish))
    recordScreenshot("quantity-daily-complete", of: app)

    let overTargetAdd = app.buttons["log-sheet.quick-add.1000"]
    makeHittable(overTargetAdd, direction: .up, in: app)
    overTargetAdd.tap()
    assertLabel("9,000 of 8,000 steps", for: relaunchedProgress)
    XCTAssertFalse(app.buttons["log-sheet.quick-add.finish"].exists)
    XCTAssertTrue(element("today.undo.Walk 8K steps", in: app).exists)
    recordScreenshot("quantity-daily-over-target", of: app)
    dismissSheet(element("log-sheet", in: app), in: app)
    XCTAssertTrue(element("today.undo.Walk 8K steps", in: app).exists)
    assertValueContains("9,000 of 8,000 steps", for: relaunchedLogButton)

    let completedQuantity = app.buttons["today.log.Read 20 pages"]
    makeHittable(completedQuantity, above: app.buttons["shell.tab.today"], in: app)
    assertValueContains("20 of 20 pages", for: completedQuantity)
    completedQuantity.tap()
    XCTAssertTrue(element("log-sheet", in: app).waitForExistence(timeout: 5))
    XCTAssertEqual(element("log-sheet.progress", in: app).label, "20 of 20 pages")
    XCTAssertFalse(app.buttons["log-sheet.quick-add.finish"].exists)
    XCTAssertFalse(element("log-sheet.undo", in: app).exists)
    assertSheetGeometry(element("log-sheet", in: app), in: app)
    recordScreenshot("quantity-daily-completed-access", of: app)
    dismissSheet(element("log-sheet", in: app), in: app)

    let completedTimes = app.buttons["today.log.Posture checks"]
    makeHittable(completedTimes, above: app.buttons["shell.tab.today"], in: app)
    assertValueContains("4 of 4 times", for: completedTimes)
    completedTimes.tap()
    assertValueContains("5 of 4 times", for: completedTimes)
    XCTAssertFalse(element("log-sheet", in: app).exists)
    XCTAssertTrue(element("today.undo.Posture checks", in: app).waitForExistence(timeout: 2))
  }

  @MainActor
  private func verifyWeeklyPriorSetTotalValidationAndUndo() throws {
    let app = launch(
      fixture: "fast-logging-weekly",
      storeName: evidenceStoreName(journey: "quantity-weekly"),
      fixtureInstant: weeklyFixtureInstantArgument
    )

    XCTAssertTrue(app.otherElements["today.dashboard"].waitForExistence(timeout: 5))
    let weeklyTimes = app.buttons["today.log.Weekly check-ins"]
    let weeklyRisk = app.buttons["today.risk.Weekly check-ins"]
    makeHittable(weeklyRisk, above: app.buttons["shell.tab.today"], in: app)
    XCTAssertEqual(weeklyRisk.label, "Log Last Week for Weekly check-ins")
    weeklyRisk.tap()
    assertValueContains("1 of 3 times", for: weeklyTimes)
    XCTAssertFalse(element("log-sheet", in: app).exists)
    XCTAssertTrue(weeklyRisk.exists)
    XCTAssertTrue(element("today.undo.Weekly check-ins", in: app).waitForExistence(timeout: 2))
    makeHittable(weeklyRisk, above: app.buttons["shell.tab.today"], in: app)
    weeklyRisk.tap()
    assertValueContains("1 of 3 times", for: weeklyTimes)
    XCTAssertFalse(element("log-sheet", in: app).exists)
    XCTAssertTrue(waitForDisappearance(weeklyRisk))
    app.buttons["today.undo.action.Weekly check-ins"].tap()
    XCTAssertTrue(weeklyRisk.waitForExistence(timeout: 2))

    makeHittable(weeklyTimes, above: app.buttons["shell.tab.today"], in: app)
    assertValueContains("1 of 3 times", for: weeklyTimes)
    weeklyTimes.tap()
    assertValueContains("2 of 3 times", for: weeklyTimes)
    XCTAssertFalse(element("log-sheet", in: app).exists)
    XCTAssertTrue(element("today.undo.Weekly check-ins", in: app).exists)

    let logButton = app.buttons["today.log.Weekly field notes"]
    makeHittable(logButton, above: app.buttons["shell.tab.today"], in: app)
    XCTAssertTrue((logButton.value as? String)?.contains("40 of 100 pages") == true)
    logButton.tap()

    let sheet = element("log-sheet", in: app)
    let progress = element("log-sheet.progress", in: app)
    XCTAssertTrue(sheet.waitForExistence(timeout: 5))
    assertSheetGeometry(sheet, in: app)
    XCTAssertEqual(element("log-sheet.title", in: app).label, "Weekly field notes")
    XCTAssertEqual(progress.label, "40 of 100 pages")
    XCTAssertTrue(app.buttons["log-sheet.scope.This Week"].isSelected)
    assertMinimumTarget(app.buttons["log-sheet.scope.This Week"])
    makeHittable(element("log-sheet.entries.title", in: app), direction: .up, in: app)
    let currentEntryDeleteLabels = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "log-sheet.delete.")
    ).allElementsBoundByIndex.map(\.label)
    XCTAssertEqual(currentEntryDeleteLabels.count, 2)
    for label in currentEntryDeleteLabels {
      XCTAssertTrue(label.contains("Mon"), "Unexpected label: \(label)")
      XCTAssertTrue(label.contains("20 pages"), "Unexpected label: \(label)")
    }
    recordScreenshot("quantity-weekly-current-entries", of: app)

    let priorScope = app.buttons["log-sheet.scope.Last Week"]
    XCTAssertTrue(priorScope.exists)
    XCTAssertEqual(priorScope.value as? String, "Unfinished")
    assertMinimumTarget(priorScope)
    makeHittable(priorScope, direction: .down, in: app)
    priorScope.tap()
    XCTAssertTrue(priorScope.isSelected)
    assertLabel("30 of 100 pages", for: progress)
    XCTAssertEqual(element("log-sheet.entries.title", in: app).label, "LOGGED LAST WEEK")
    makeHittable(element("log-sheet.entries.title", in: app), direction: .up, in: app)
    let priorEntryDeleteLabels = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "log-sheet.delete.")
    ).allElementsBoundByIndex.map(\.label)
    XCTAssertEqual(priorEntryDeleteLabels.count, 1)
    XCTAssertTrue(
      priorEntryDeleteLabels[0].contains("Mon")
        && priorEntryDeleteLabels[0].contains("30 pages"),
      "Unexpected label: \(priorEntryDeleteLabels[0])"
    )
    XCTAssertFalse(element("log-sheet.amount-editor", in: app).exists)
    recordScreenshot("quantity-weekly-grace-selected", of: app)
    dragSheetToLargeDetent(sheet, in: app)
    XCTAssertLessThan(sheet.frame.minY, app.frame.midY)
    try performAccessibilityAudit(in: app, sheet: sheet, context: .weeklyGrace)

    let setTotal = app.buttons["log-sheet.amount.set-total"]
    makeHittable(setTotal, direction: .up, in: app)
    assertMinimumTarget(setTotal)
    setTotal.tap()

    let amountField = app.textFields["log-sheet.amount.field"]
    XCTAssertTrue(amountField.waitForExistence(timeout: 2))
    let keyboardSubmit = app.buttons["log-sheet.amount.keyboard-submit"]
    XCTAssertTrue(keyboardSubmit.waitForExistence(timeout: 2))
    XCTAssertFalse(app.buttons["log-sheet.amount.submit"].exists)
    XCTAssertFalse(app.buttons["log-sheet.amount.cancel"].exists)
    replaceText(in: amountField, with: "30")
    keyboardSubmit.tap()
    assertLabel("30 of 100 pages", for: progress)
    XCTAssertTrue(waitForDisappearance(element("log-sheet.amount-editor", in: app)))
    XCTAssertFalse(element("log-sheet.undo", in: app).exists)
    XCTAssertTrue(priorScope.isSelected)

    makeHittable(setTotal, direction: .up, in: app)
    setTotal.tap()
    XCTAssertTrue(amountField.waitForExistence(timeout: 2))
    replaceText(in: amountField, with: "20")
    XCTAssertTrue(keyboardSubmit.exists)
    keyboardSubmit.tap()
    XCTAssertEqual(
      element("log-sheet.amount.error", in: app).label,
      "Delete an entry before lowering the total."
    )
    assertFieldRetainsKeyboardFocus(amountField)
    let keyboardCancel = app.buttons["log-sheet.amount.keyboard-cancel"]
    XCTAssertTrue(keyboardSubmit.exists)
    XCTAssertTrue(keyboardCancel.exists)
    let validationEditor = element("log-sheet.amount-editor", in: app)
    XCTAssertTrue(validationEditor.exists)
    XCTAssertEqual(app.buttons.matching(identifier: "log-sheet.amount.keyboard-cancel").count, 1)
    XCTAssertTrue(keyboardCancel.isHittable)
    XCTAssertFalse(app.buttons["log-sheet.amount.submit"].exists)
    XCTAssertFalse(app.buttons["log-sheet.amount.cancel"].exists)
    try performAccessibilityAudit(in: app, sheet: sheet, context: .weeklyValidation)
    recordScreenshot("quantity-weekly-validation-keyboard", of: app)

    replaceText(in: amountField, with: "60")
    XCTAssertTrue(keyboardSubmit.exists)
    keyboardSubmit.tap()
    assertLabel("60 of 100 pages", for: progress)
    XCTAssertTrue(sheet.exists)
    XCTAssertTrue(priorScope.isSelected)
    XCTAssertFalse(element("log-sheet.amount-editor", in: app).exists)

    let undo = element("log-sheet.undo", in: app)
    XCTAssertTrue(undo.waitForExistence(timeout: 2))
    XCTAssertEqual(undo.label, "Weekly field notes. Logged 30 pages. Undo available.")
    let undoButton = app.buttons["log-sheet.undo.action"]
    assertMinimumTarget(undoButton)
    recordScreenshot("quantity-weekly-grace-undo", of: app)
    undoButton.tap()
    assertLabel("30 of 100 pages", for: progress)
    XCTAssertTrue(waitForDisappearance(undo))
    XCTAssertTrue(priorScope.isSelected)
    try performAccessibilityAudit(in: app, sheet: sheet, context: .weeklyPostUndo)
  }

  @MainActor
  private func verifyAdaptiveQuantitySheet() throws {
    let sizes = [
      (
        category: "UICTContentSizeCategoryAccessibilityL",
        slug: "accessibility-large"
      ),
      (
        category: "UICTContentSizeCategoryAccessibilityXXL",
        slug: "accessibility-extra-extra-large"
      ),
    ]
    for size in sizes {
      try verifyAdaptiveQuantitySheet(
        contentSizeCategory: size.category,
        sizeSlug: size.slug
      )
    }
  }

  @MainActor
  private func verifyAdaptiveQuantitySheet(
    contentSizeCategory: String,
    sizeSlug: String
  ) throws {
    let app = launch(
      fixture: "fast-logging-daily",
      storeName: evidenceStoreName(journey: "quantity-daily", sizeSlug: sizeSlug),
      additionalArguments: [
        "-UIPreferredContentSizeCategoryName",
        contentSizeCategory,
        "-UIAccessibilityReduceMotionEnabled",
        "YES",
        "-AppleInterfaceStyle",
        "Dark",
      ]
    )

    XCTAssertTrue(app.otherElements["today.dashboard"].waitForExistence(timeout: 5))
    let logButton = app.buttons["today.log.Walk 8K steps"]
    makeHittable(logButton, above: app.buttons["shell.tab.today"], in: app)
    logButton.tap()

    let sheet = element("log-sheet", in: app)
    XCTAssertTrue(sheet.waitForExistence(timeout: 5))
    assertSheetGeometry(sheet, in: app)
    let mediumMinY = sheet.frame.minY
    let todayScope = app.buttons["log-sheet.scope.Today"]
    let priorScope = app.buttons["log-sheet.scope.Yesterday"]
    XCTAssertTrue(todayScope.isSelected)
    XCTAssertEqual(priorScope.value as? String, "Unfinished")
    assertMinimumTarget(todayScope)
    assertMinimumTarget(priorScope)
    assertAccessibilityOrder(
      [
        "log-sheet.title",
        "log-sheet.scope.Today",
        "log-sheet.scope.Yesterday",
        "log-sheet.progress",
      ],
      in: app
    )
    recordScreenshot("quantity-daily-\(sizeSlug)-medium-top", of: app)
    try performAccessibilityAudit(
      in: app,
      sheet: sheet,
      context: .adaptiveMediumTop(sizeSlug)
    )

    let setTotal = app.buttons["log-sheet.amount.set-total"]
    makeHittable(setTotal, direction: .up, in: app)
    XCTAssertEqual(sheet.frame.minY, mediumMinY, accuracy: 4)
    try assertLongLowerTotalValidation(
      setTotal: setTotal,
      expectedSheetMinY: mediumMinY,
      screenshotName: "quantity-daily-\(sizeSlug)-medium-validation-keyboard",
      auditContext: .adaptiveMediumValidation(sizeSlug),
      in: app
    )

    dragSheetToLargeDetent(sheet, in: app)
    let largeMinY = sheet.frame.minY
    XCTAssertLessThan(largeMinY, mediumMinY - 50)
    assertSheetGeometry(sheet, requiresVisibleTitle: false, in: app)
    makeHittable(setTotal, direction: .up, in: app)
    XCTAssertTrue(setTotal.isHittable)
    XCTAssertFalse(element("log-sheet.amount-editor", in: app).exists)
    recordScreenshot("quantity-daily-\(sizeSlug)-large-middle", of: app)
    try assertLongLowerTotalValidation(
      setTotal: setTotal,
      expectedSheetMinY: largeMinY,
      screenshotName: nil,
      auditContext: .adaptiveLargeValidation(sizeSlug),
      in: app
    )

    makeHittable(priorScope, direction: .down, in: app)
    priorScope.tap()
    XCTAssertTrue(priorScope.isSelected)
    XCTAssertEqual(priorScope.value as? String, "Unfinished")
    XCTAssertFalse(element("log-sheet.amount-editor", in: app).exists)
    XCTAssertEqual(element("log-sheet.progress", in: app).label, "3,000 of 8,000 steps")
    let entriesTitle = element("log-sheet.entries.title", in: app)
    makeHittable(entriesTitle, direction: .up, in: app)
    XCTAssertEqual(entriesTitle.label, "LOGGED YESTERDAY")
    XCTAssertTrue(entriesTitle.isHittable)
    XCTAssertLessThanOrEqual(entriesTitle.frame.maxY, app.frame.maxY)
    recordScreenshot("quantity-daily-\(sizeSlug)-grace-bottom", of: app)
  }

  @MainActor
  private func assertLongLowerTotalValidation(
    setTotal: XCUIElement,
    expectedSheetMinY: CGFloat,
    screenshotName: String?,
    auditContext: AuditContext,
    in app: XCUIApplication
  ) throws {
    setTotal.tap()
    let amountField = app.textFields["log-sheet.amount.field"]
    XCTAssertTrue(amountField.waitForExistence(timeout: 2))
    replaceText(in: amountField, with: "3000")
    let keyboardSubmit = app.buttons["log-sheet.amount.keyboard-submit"]
    let keyboardCancel = app.buttons["log-sheet.amount.keyboard-cancel"]
    XCTAssertTrue(keyboardSubmit.waitForExistence(timeout: 2))
    XCTAssertTrue(keyboardCancel.exists)
    keyboardSubmit.tap()

    let error = element("log-sheet.amount.error", in: app)
    XCTAssertEqual(error.label, "Delete an entry before lowering the total.")
    XCTAssertGreaterThan(error.frame.height, 40)
    assertFieldRetainsKeyboardFocus(amountField)
    let editor = element("log-sheet.amount-editor", in: app)
    XCTAssertTrue(editor.exists)
    XCTAssertEqual(app.buttons.matching(identifier: "log-sheet.amount.keyboard-cancel").count, 1)
    XCTAssertTrue(keyboardCancel.exists)
    XCTAssertTrue(keyboardCancel.isHittable)
    XCTAssertGreaterThanOrEqual(
      keyboardCancel.frame.width,
      80,
      "Keyboard Cancel must remain visibly readable at larger Dynamic Type sizes."
    )
    XCTAssertTrue(element("log-sheet.title", in: app).exists)
    XCTAssertFalse(app.buttons["log-sheet.scope.Today"].exists)
    XCTAssertFalse(element("log-sheet.progress", in: app).exists)
    XCTAssertFalse(element("log-sheet.quick-add.title", in: app).exists)
    XCTAssertGreaterThan(editor.frame.width, 0)
    XCTAssertGreaterThan(editor.frame.height, 0)
    let sheet = element("log-sheet", in: app)
    XCTAssertGreaterThanOrEqual(editor.frame.minY, sheet.frame.minY + 32)
    XCTAssertLessThanOrEqual(editor.frame.maxY, keyboardCancel.frame.minY - 8)
    try performAccessibilityAudit(
      in: app, sheet: element("log-sheet", in: app), context: auditContext)
    if let screenshotName {
      recordScreenshot(screenshotName, of: app)
    }
    keyboardCancel.tap()
    XCTAssertTrue(waitForDisappearance(editor))
    XCTAssertEqual(
      element("log-sheet", in: app).frame.minY,
      expectedSheetMinY,
      accuracy: 4
    )
  }

  @MainActor
  private func dragSheetToLargeDetent(_ sheet: XCUIElement, in app: XCUIApplication) {
    let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
    let start = origin.withOffset(
      CGVector(
        dx: sheet.frame.midX,
        dy: max(sheet.frame.minY - 10, 10)
      )
    )
    let end = start.withOffset(CGVector(dx: 0, dy: -250))
    start.press(forDuration: 0.1, thenDragTo: end)
  }

  @MainActor
  private func evidenceStoreName(
    journey: String,
    sizeSlug: String = "standard"
  ) -> String {
    "fast-logging-iphone-\(journey)-\(sizeSlug)"
  }

  @MainActor
  private func recordScreenshot(_ name: String, of app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
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

  private enum AuditContext: Equatable {
    case today
    case dailyGrace
    case dailyCurrent
    case weeklyGrace
    case weeklyValidation
    case weeklyPostUndo
    case adaptiveMediumTop(String)
    case adaptiveMediumValidation(String)
    case adaptiveLargeValidation(String)

  }

  private struct ExpectedAuditIssue {
    let auditType: XCUIAccessibilityAuditType
    let detailedDescription: String
    let identifier: String?
    let label: String?
    let frame: CGRect?
    let isHittable: Bool?
    let count: Int
  }

  @MainActor
  private func performAccessibilityAudit(
    in app: XCUIApplication,
    sheet: XCUIElement? = nil,
    context: AuditContext
  ) throws {
    guard let sheet else {
      XCTAssertEqual(context, .today)
      try app.performAccessibilityAudit(for: acceptanceAuditTypes)
      return
    }

    let expectedIssues = expectedAuditIssues(for: context)
    var handledCounts = Array(repeating: 0, count: expectedIssues.count)
    let sheetFrame = sheet.frame
    let keyboardCancel = app.buttons["log-sheet.amount.keyboard-cancel"]
    let unobscuredBottom =
      keyboardCancel.exists
      ? min(keyboardCancel.frame.minY - 8, sheetFrame.maxY)
      : sheetFrame.maxY
    let unobscuredSheetFrame = CGRect(
      x: sheetFrame.minX,
      y: sheetFrame.minY + 32,
      width: sheetFrame.width,
      height: max(unobscuredBottom - sheetFrame.minY - 32, 0)
    )

    try app.performAccessibilityAudit(for: acceptanceAuditTypes) { issue in
      guard issue.auditType == .contrast || issue.auditType == .textClipped else {
        return false
      }
      if let element = issue.element,
        element.exists,
        element.identifier.hasPrefix("log-sheet."),
        !element.identifier.hasPrefix("log-sheet.amount.keyboard-"),
        element.frame.maxY > unobscuredBottom
      {
        return true
      }

      let matchingIndices = expectedIssues.indices.filter {
        self.auditIssue(
          issue,
          matches: expectedIssues[$0],
          unobscuredSheetFrame: unobscuredSheetFrame
        )
      }
      guard matchingIndices.count == 1, let matchIndex = matchingIndices.first else {
        let element = issue.element
        let attachment = XCTAttachment(
          string: """
            auditType: \(issue.auditType.rawValue)
            compactDescription: \(issue.compactDescription)
            context: \(String(describing: context))
            detailedDescription: \(issue.detailedDescription)
            identifier: \(element?.identifier ?? "<none>")
            label: \(element?.label ?? "<none>")
            frame: \(String(describing: element?.frame))
            exists: \(element?.exists ?? false)
            isHittable: \(element?.isHittable ?? false)
            unobscuredSheetFrame: \(unobscuredSheetFrame)
            """
        )
        attachment.name = "Unexpected accessibility audit issue"
        attachment.lifetime = .keepAlways
        self.add(attachment)
        return false
      }
      guard handledCounts[matchIndex] < expectedIssues[matchIndex].count else {
        return false
      }
      handledCounts[matchIndex] += 1
      return true
    }

    for index in expectedIssues.indices {
      XCTAssertEqual(
        handledCounts[index],
        expectedIssues[index].count,
        "Unexpected handled-audit count for \(context), signature \(index)"
      )
    }
  }

  @MainActor
  private func auditIssue(
    _ issue: XCUIAccessibilityAuditIssue,
    matches expected: ExpectedAuditIssue,
    unobscuredSheetFrame: CGRect
  ) -> Bool {
    guard issue.auditType == expected.auditType else { return false }

    let compactKeyword = expected.auditType == .contrast ? "contrast" : "clipp"
    guard
      issue.compactDescription.localizedCaseInsensitiveContains(compactKeyword),
      issue.detailedDescription == expected.detailedDescription
    else {
      return false
    }

    guard let expectedIdentifier = expected.identifier else {
      return issue.element == nil
        && expected.label == nil
        && expected.frame == nil
        && expected.isHittable == nil
    }
    guard
      let expectedLabel = expected.label,
      let issueElement = issue.element,
      issueElement.identifier == expectedIdentifier,
      issueElement.label == expectedLabel,
      issueElement.exists
    else {
      return false
    }

    if let expectedHittable = expected.isHittable,
      issueElement.isHittable != expectedHittable
    {
      return false
    }
    if let expectedFrame = expected.frame {
      guard frame(issueElement.frame, equals: expectedFrame, accuracy: 2) else {
        return false
      }
    } else if unobscuredSheetFrame.contains(issueElement.frame) {
      return false
    }

    if expected.isHittable == true {
      return unobscuredSheetFrame.intersects(issueElement.frame)
    }
    if expected.isHittable == false {
      return !issueElement.isHittable
        && !unobscuredSheetFrame.intersects(issueElement.frame)
    }
    return true
  }

  private func frame(_ actual: CGRect, equals expected: CGRect, accuracy: CGFloat) -> Bool {
    abs(actual.minX - expected.minX) <= accuracy
      && abs(actual.minY - expected.minY) <= accuracy
      && abs(actual.width - expected.width) <= accuracy
      && abs(actual.height - expected.height) <= accuracy
  }

  @MainActor
  private func expectedAuditIssues(for context: AuditContext) -> [ExpectedAuditIssue] {
    switch context {
    case .dailyGrace:
      return [
        textClippedIssue(
          identifier: "log-sheet.entries.title",
          label: "LOGGED YESTERDAY",
          frame: CGRect(x: 20, y: 475.6667, width: 174.3333, height: 15.6667),
          isHittable: true
        )
      ]
    case .weeklyValidation:
      return [
        textClippedIssue(
          identifier: "log-sheet.amount.field",
          label: "Set week total",
          detailedDescription:
            "Text of this UITextField may be clipped at larger Dynamic Type sizes.",
          frame: CGRect(x: 35.5, y: 174.8333, width: 331, height: 47),
          isHittable: true
        )
      ]
    case .weeklyGrace, .weeklyPostUndo:
      return [
        textClippedIssue(
          identifier: "log-sheet.entries.title",
          label: "LOGGED LAST WEEK",
          frame: CGRect(x: 20, y: 463.6667, width: 172.3333, height: 15.6667),
          isHittable: true
        )
      ]
    case .adaptiveMediumValidation("accessibility-large"),
      .adaptiveLargeValidation("accessibility-large"):
      return [
        textClippedIssue(
          identifier: "log-sheet.amount.field",
          label: "Set day total",
          detailedDescription:
            "Text of this UITextField may be clipped at larger Dynamic Type sizes.",
          frame: CGRect(x: 35.5, y: 209.1667, width: 331, height: 47),
          isHittable: true
        )
      ]
    case .adaptiveMediumValidation("accessibility-extra-extra-large"),
      .adaptiveLargeValidation("accessibility-extra-extra-large"):
      return [
        textClippedIssue(
          identifier: "log-sheet.amount.field",
          label: "Set day total",
          detailedDescription:
            "Text of this UITextField may be clipped at larger Dynamic Type sizes.",
          frame: CGRect(x: 35.5, y: 234.5, width: 331, height: 59),
          isHittable: true
        )
      ]
    case .adaptiveMediumTop("accessibility-large"):
      return [
        textClippedIssue(
          identifier: "log-sheet.title",
          label: "Walk 8K steps",
          frame: CGRect(x: 27.2040, y: 430.3897, width: 270.1360, height: 49.2902),
          isHittable: true
        ),
        textClippedIssue(
          identifier: "log-sheet.quick-add.title",
          label: "QUICK ADD",
          frame: CGRect(x: 27.2040, y: 748.2156, width: 161.9536, height: 31.0464),
          isHittable: true
        ),
        textClippedIssue(
          identifier: "log-sheet.streak",
          label: "3 day streak",
          frame: CGRect(x: 27.2040, y: 690.6036, width: 151.3914, height: 34.5672),
          isHittable: true
        ),
        textClippedIssue(
          identifier: "log-sheet.progress",
          label: "4,000 of 8,000 steps",
          frame: CGRect(x: 27.2040, y: 644.8342, width: 292.2206, height: 38.0879),
          isHittable: true
        ),
      ]
    case .adaptiveMediumTop("accessibility-extra-extra-large"):
      return [
        textClippedIssue(
          identifier: "log-sheet.streak",
          label: "3 day streak",
          frame: CGRect(x: 27.2040, y: 780.2222, width: 209.9635, height: 48.3300),
          isHittable: true
        ),
        textClippedIssue(
          identifier: "log-sheet.title",
          label: "Walk 8K steps",
          frame: CGRect(x: 27.2040, y: 430.3897, width: 329.6683, height: 60.8126),
          isHittable: true
        ),
        textClippedIssue(
          identifier: "log-sheet.progress",
          label: "4,000 of 8,000 steps",
          frame: CGRect(x: 27.2040, y: 664.6783, width: 233.9685, height: 107.8624),
          isHittable: true
        ),
      ]
    default:
      return []
    }
  }

  private func textClippedIssue(
    identifier: String,
    label: String,
    detailedDescription: String =
      "Text of this SwiftUI.AccessibilityNode may be clipped at larger Dynamic Type sizes.",
    frame: CGRect,
    isHittable: Bool
  ) -> ExpectedAuditIssue {
    ExpectedAuditIssue(
      auditType: .textClipped,
      detailedDescription: detailedDescription,
      identifier: identifier,
      label: label,
      frame: frame,
      isHittable: isHittable,
      count: 1
    )
  }

  @MainActor
  private func assertSheetGeometry(
    _ sheet: XCUIElement,
    requiresVisibleTitle: Bool = true,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let windowFrame = app.frame
    let sheetFrame = sheet.frame
    XCTAssertTrue(sheet.exists, file: file, line: line)
    XCTAssertGreaterThan(sheetFrame.width, 0, file: file, line: line)
    XCTAssertGreaterThan(sheetFrame.height, 0, file: file, line: line)
    XCTAssertGreaterThanOrEqual(sheetFrame.minX, windowFrame.minX, file: file, line: line)
    XCTAssertLessThanOrEqual(sheetFrame.maxX, windowFrame.maxX, file: file, line: line)
    XCTAssertGreaterThanOrEqual(sheetFrame.minY, windowFrame.minY, file: file, line: line)
    XCTAssertLessThanOrEqual(sheetFrame.maxY, windowFrame.maxY, file: file, line: line)

    let leadingChrome = sheetFrame.minX - windowFrame.minX
    let trailingChrome = windowFrame.maxX - sheetFrame.maxX
    XCTAssertEqual(leadingChrome, trailingChrome, accuracy: 1, file: file, line: line)
    XCTAssertLessThanOrEqual(leadingChrome, 8.5, file: file, line: line)
    XCTAssertLessThanOrEqual(trailingChrome, 8.5, file: file, line: line)
    if requiresVisibleTitle {
      let titleFrame = element("log-sheet.title", in: app).frame
      XCTAssertGreaterThanOrEqual(titleFrame.minX, windowFrame.minX + 16, file: file, line: line)
      XCTAssertLessThanOrEqual(titleFrame.maxX, windowFrame.maxX - 16, file: file, line: line)
      XCTAssertGreaterThan(titleFrame.minY, windowFrame.minY, file: file, line: line)
      XCTAssertLessThan(titleFrame.maxY, windowFrame.maxY, file: file, line: line)
    }
  }

  @MainActor
  private func assertAccessibilityOrder(
    _ identifiers: [String],
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let elements = app.descendants(matching: .any).allElementsBoundByIndex
    var previousIndex = -1
    var previousFrame: CGRect?
    for identifier in identifiers {
      guard let index = elements.firstIndex(where: { $0.identifier == identifier }) else {
        XCTFail("Missing accessibility element \(identifier)", file: file, line: line)
        return
      }
      let currentFrame = elements[index].frame
      XCTAssertGreaterThan(
        index,
        previousIndex,
        "\(identifier) is out of traversal order",
        file: file,
        line: line
      )
      if let previousFrame {
        XCTAssertGreaterThanOrEqual(
          currentFrame.minY,
          previousFrame.minY,
          "\(identifier) is above the preceding reading-order element",
          file: file,
          line: line
        )
      }
      previousIndex = index
      previousFrame = currentFrame
    }
  }

  @MainActor
  private func launch(
    fixture: String,
    storeName: String,
    reset: Bool = true,
    fixtureInstant: String? = nil,
    additionalArguments: [String] = []
  ) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["TZ"] = "America/Los_Angeles"
    app.launchArguments = launchArguments(
      storeName: storeName,
      reset: reset,
      fixture: fixture,
      fixtureInstant: fixtureInstant,
      additionalArguments: additionalArguments
    )
    app.terminate()
    app.launch()
    XCTAssertEqual(app.frame.width, 402, accuracy: 0.5)
    XCTAssertEqual(app.frame.height, 874, accuracy: 0.5)
    return app
  }

  private func launchArguments(
    storeName: String,
    reset: Bool,
    fixture: String?,
    fixtureInstant: String? = nil,
    additionalArguments: [String] = []
  ) -> [String] {
    var arguments = [
      "-tend-ui-testing",
      "-tend-ui-test-store",
      storeName,
      "-tend-ui-test-instant",
      fixtureInstant ?? fixtureInstantArgument,
    ]
    if reset {
      arguments.append("-tend-ui-test-reset")
    }
    if let fixture {
      arguments += ["-tend-ui-test-fixture", fixture]
    }
    return arguments + additionalArguments
  }

  @MainActor
  private func assertFieldRetainsKeyboardFocus(
    _ field: XCUIElement,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard let originalValue = field.value as? String else {
      XCTFail("Expected an editable text-field value", file: file, line: line)
      return
    }
    field.typeText("7")
    XCTAssertEqual(
      field.value as? String,
      originalValue + "7",
      "Validation must keep keyboard focus in the amount field",
      file: file,
      line: line
    )
    field.typeText(XCUIKeyboardKey.delete.rawValue)
    XCTAssertEqual(field.value as? String, originalValue, file: file, line: line)
  }

  @MainActor
  private func makeHittable(
    _ element: XCUIElement,
    above overlay: XCUIElement,
    in app: XCUIApplication
  ) {
    for _ in 0..<12 {
      guard element.exists, overlay.exists else {
        XCTFail("Expected scroll target and overlay to exist")
        return
      }
      if element.isHittable, element.frame.maxY <= overlay.frame.minY {
        return
      }
      app.swipeUp()
    }
    XCTFail("Expected \(element.identifier) to become hittable")
  }

  @MainActor
  private func makeHittable(
    _ element: XCUIElement,
    direction: ScrollDirection,
    in app: XCUIApplication
  ) {
    for _ in 0..<12 {
      if element.exists, element.isHittable {
        return
      }
      switch direction {
      case .up:
        app.swipeUp()
      case .down:
        app.swipeDown()
      }
    }
    XCTFail("Expected \(element.identifier) to become hittable")
  }

  @MainActor
  private func assertMinimumTarget(
    _ element: XCUIElement,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertGreaterThanOrEqual(element.frame.width, 43.99, file: file, line: line)
    XCTAssertGreaterThanOrEqual(element.frame.height, 43.99, file: file, line: line)
  }

  @MainActor
  private func assertLabel(
    _ expectedLabel: String,
    for element: XCUIElement,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let predicate = NSPredicate(format: "label == %@", expectedLabel)
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    XCTAssertEqual(
      XCTWaiter.wait(for: [expectation], timeout: 3),
      .completed,
      "Expected label \(expectedLabel), found \(element.label)",
      file: file,
      line: line
    )
  }

  @MainActor
  private func assertValueContains(
    _ expectedSubstring: String,
    for element: XCUIElement,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let predicate = NSPredicate(format: "value CONTAINS %@", expectedSubstring)
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    XCTAssertEqual(
      XCTWaiter.wait(for: [expectation], timeout: 3),
      .completed,
      "Expected value containing \(expectedSubstring), found \(String(describing: element.value))",
      file: file,
      line: line
    )
  }

  @MainActor
  private func replaceText(in field: XCUIElement, with text: String) {
    field.tap()
    if let value = field.value as? String, !value.isEmpty, value != "Whole number" {
      field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
    }
    field.typeText(text)
  }

  @MainActor
  private func waitForDisappearance(_ element: XCUIElement) -> Bool {
    let predicate = NSPredicate(format: "exists == false")
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
  }

  @MainActor
  private func dismissSheet(_ sheet: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<3 where sheet.exists {
      sheet.swipeDown()
    }
    XCTAssertTrue(waitForDisappearance(sheet))
  }

  @MainActor
  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }
}

private enum ScrollDirection {
  case up
  case down
}
