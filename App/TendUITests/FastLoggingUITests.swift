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
  func testQuantityLoggingJourneys() {
    verifyDailyCurrentQuickAddCustomAmountDeleteAndRelaunch()
    verifyWeeklyPriorSetTotalValidationAndUndo()
    verifyAdaptiveQuantitySheet()
  }

  @MainActor
  func testTimesLoggingJourneys() {
    verifyDailyTargetOneRoutingAndReducedMotion()
    verifyWeeklyCountGraceUndoAndRelaunch()
  }

  @MainActor
  private func verifyDailyTargetOneRoutingAndReducedMotion() {
    let storeName = "FastLoggingUITests-times-daily-\(UUID().uuidString)"
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
    XCTAssertFalse(app.buttons["today.row.Feed the cat"].exists)

    targetOne.tap()

    assertValueContains("1 of 1 time", for: targetOne)
    XCTAssertEqual(targetOne.value as? String, "1 of 1 time, 1 day, Met")
    assertLabel("3 of 5", for: summary)
    makeHittable(targetOne, above: tabButton, in: app)
    XCTAssertGreaterThan(targetOne.frame.minY, tendedSection.frame.maxY)
    XCTAssertEqual(targetOne.frame.width, 44, accuracy: 0.5)
    XCTAssertEqual(targetOne.frame.height, 44, accuracy: 0.5)
    XCTAssertFalse(element("log-sheet", in: app).exists)
    let undo = element("today.undo.Feed the cat", in: app)
    XCTAssertTrue(undo.waitForExistence(timeout: 2))
    XCTAssertEqual(undo.label, "Feed the cat. Logged 1 times. Undo available.")
    let undoButton = app.buttons["today.undo.action.Feed the cat"]
    assertMinimumTarget(undoButton)
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

    let exactTime = app.buttons["today.log.Meditate"]
    makeHittable(exactTime, above: app.buttons["shell.tab.today"], in: app)
    assertValueContains("0 of 10 time", for: exactTime)
    exactTime.tap()
    let sheet = element("log-sheet", in: app)
    XCTAssertTrue(sheet.waitForExistence(timeout: 5))
    XCTAssertEqual(element("log-sheet.progress", in: app).label, "0 of 10 time")
    dismissSheet(sheet, in: app)
    assertValueContains("0 of 10 time", for: exactTime)

    let quantity = app.buttons["today.log.Walk 8K steps"]
    makeHittable(quantity, above: app.buttons["shell.tab.today"], in: app)
    assertValueContains("4,000 of 8,000 steps", for: quantity)
    quantity.tap()
    XCTAssertTrue(sheet.waitForExistence(timeout: 5))
    XCTAssertEqual(element("log-sheet.progress", in: app).label, "4,000 of 8,000 steps")
    dismissSheet(sheet, in: app)
    assertValueContains("4,000 of 8,000 steps", for: quantity)
  }

  @MainActor
  private func verifyWeeklyCountGraceUndoAndRelaunch() {
    let storeName = "FastLoggingUITests-times-weekly-\(UUID().uuidString)"
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

    risk.tap()

    assertValueContains("1 of 3 times", for: count)
    XCTAssertTrue(risk.exists)
    XCTAssertFalse(element("log-sheet", in: app).exists)
    let undo = element("today.undo.Weekly check-ins", in: app)
    XCTAssertTrue(undo.waitForExistence(timeout: 2))
    XCTAssertEqual(undo.label, "Weekly check-ins. Logged 1 times. Undo available.")

    makeHittable(risk, above: tabButton, in: app)
    risk.tap()
    assertValueContains("1 of 3 times", for: count)
    XCTAssertTrue(waitForDisappearance(risk))
    app.buttons["today.undo.action.Weekly check-ins"].tap()
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

    app.buttons["today.undo.action.Weekly check-ins"].tap()
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
  }
  @MainActor
  private func verifyDailyCurrentQuickAddCustomAmountDeleteAndRelaunch() {
    let storeName = "FastLoggingUITests-daily-\(UUID().uuidString)"
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
    dismissSheet(sheet, in: app)
    assertValueContains("0 of 10 time", for: exactTimeButton)

    let riskButton = app.buttons["today.risk.Walk 8K steps"]
    makeHittable(riskButton, above: app.buttons["shell.tab.today"], in: app)
    riskButton.tap()
    XCTAssertTrue(sheet.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["log-sheet.scope.Yesterday"].isSelected)
    XCTAssertEqual(element("log-sheet.progress", in: app).label, "3,000 of 8,000 steps")
    dismissSheet(sheet, in: app)

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
    let currentScope = app.buttons["log-sheet.scope.Today"]
    let priorScope = app.buttons["log-sheet.scope.Yesterday"]
    XCTAssertTrue(currentScope.isSelected)
    XCTAssertTrue(priorScope.exists)
    assertMinimumTarget(currentScope)
    assertMinimumTarget(priorScope)

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
    assertMinimumTarget(submitAmount)
    assertMinimumTarget(cancelAmount)

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
    }
    keyboardCancel.tap()
    XCTAssertTrue(waitForDisappearance(element("log-sheet.amount-editor", in: app)))
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

    let addedEntryDelete = app.buttons.matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
        "log-sheet.delete.",
        "1,000 steps"
      )
    ).firstMatch
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
    let relaunchedLogButton = app.buttons["today.log.Walk 8K steps"]
    makeHittable(relaunchedLogButton, above: app.buttons["shell.tab.today"], in: app)
    XCTAssertTrue(
      (relaunchedLogButton.value as? String)?.contains("4,750 of 8,000 steps") == true
    )
    relaunchedLogButton.tap()
    XCTAssertTrue(element("log-sheet", in: app).waitForExistence(timeout: 5))
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
    let orderedEntryDeletes = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "log-sheet.delete.")
    ).allElementsBoundByIndex
    guard let newestEntryDelete = orderedEntryDeletes.first else {
      XCTFail("Expected at least one persisted entry")
      return
    }
    XCTAssertTrue(newestEntryDelete.label.contains("250 steps"))
    let newestEntryID = newestEntryDelete.identifier
    let survivingEntryIDs = Set(orderedEntryDeletes.dropFirst().map(\.identifier))
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

    let overTargetAdd = app.buttons["log-sheet.quick-add.1000"]
    makeHittable(overTargetAdd, direction: .up, in: app)
    overTargetAdd.tap()
    assertLabel("9,000 of 8,000 steps", for: relaunchedProgress)
    XCTAssertFalse(app.buttons["log-sheet.quick-add.finish"].exists)
    dismissSheet(element("log-sheet", in: app), in: app)

    XCTAssertTrue(element("today.undo.Walk 8K steps", in: app).exists)
    let completedQuantity = app.buttons["today.log.Read 20 pages"]
    makeHittable(completedQuantity, above: app.buttons["shell.tab.today"], in: app)
    assertValueContains("20 of 20 pages", for: completedQuantity)
    completedQuantity.tap()
    XCTAssertTrue(element("log-sheet", in: app).waitForExistence(timeout: 5))
    XCTAssertEqual(element("log-sheet.progress", in: app).label, "20 of 20 pages")
    XCTAssertFalse(app.buttons["log-sheet.quick-add.finish"].exists)
    XCTAssertFalse(element("log-sheet.undo", in: app).exists)
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
  private func verifyWeeklyPriorSetTotalValidationAndUndo() {
    let app = launch(
      fixture: "fast-logging-weekly",
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

    let setTotal = app.buttons["log-sheet.amount.set-total"]
    makeHittable(setTotal, direction: .up, in: app)
    assertMinimumTarget(setTotal)
    setTotal.tap()

    let amountField = app.textFields["log-sheet.amount.field"]
    XCTAssertTrue(amountField.waitForExistence(timeout: 2))
    replaceText(in: amountField, with: "30")
    let submitAmount = app.buttons["log-sheet.amount.submit"]
    makeHittable(submitAmount, direction: .up, in: app)
    assertMinimumTarget(submitAmount)
    submitAmount.tap()
    assertLabel("30 of 100 pages", for: progress)
    XCTAssertTrue(waitForDisappearance(element("log-sheet.amount-editor", in: app)))
    XCTAssertFalse(element("log-sheet.undo", in: app).exists)
    XCTAssertTrue(priorScope.isSelected)

    makeHittable(setTotal, direction: .up, in: app)
    setTotal.tap()
    XCTAssertTrue(amountField.waitForExistence(timeout: 2))
    replaceText(in: amountField, with: "20")
    makeHittable(submitAmount, direction: .up, in: app)
    submitAmount.tap()
    XCTAssertEqual(
      element("log-sheet.amount.error", in: app).label,
      "Delete an entry before lowering the total."
    )

    replaceText(in: amountField, with: "60")
    makeHittable(submitAmount, direction: .up, in: app)
    submitAmount.tap()
    assertLabel("60 of 100 pages", for: progress)
    XCTAssertTrue(sheet.exists)
    XCTAssertTrue(priorScope.isSelected)

    let undo = element("log-sheet.undo", in: app)
    XCTAssertTrue(undo.waitForExistence(timeout: 2))
    XCTAssertEqual(undo.label, "Weekly field notes. Logged 30 pages. Undo available.")
    let undoButton = app.buttons["log-sheet.undo.action"]
    assertMinimumTarget(undoButton)
    undoButton.tap()
    assertLabel("30 of 100 pages", for: progress)
    XCTAssertTrue(waitForDisappearance(undo))
    XCTAssertTrue(priorScope.isSelected)
  }

  @MainActor
  private func verifyAdaptiveQuantitySheet() {
    for contentSizeCategory in [
      "UICTContentSizeCategoryAccessibilityL",
      "UICTContentSizeCategoryAccessibilityXXL",
    ] {
      verifyAdaptiveQuantitySheet(contentSizeCategory: contentSizeCategory)
    }
  }

  @MainActor
  private func verifyAdaptiveQuantitySheet(contentSizeCategory: String) {
    let app = launch(
      fixture: "fast-logging-daily",
      additionalArguments: [
        "-UIPreferredContentSizeCategoryName",
        contentSizeCategory,
        "-UIAccessibilityReduceMotionEnabled",
        "YES",
      ]
    )

    XCTAssertTrue(app.otherElements["today.dashboard"].waitForExistence(timeout: 5))
    let logButton = app.buttons["today.log.Walk 8K steps"]
    makeHittable(logButton, above: app.buttons["shell.tab.today"], in: app)
    logButton.tap()

    let sheet = element("log-sheet", in: app)
    XCTAssertTrue(sheet.waitForExistence(timeout: 5))
    let mediumMinY = sheet.frame.minY
    let todayScope = app.buttons["log-sheet.scope.Today"]
    let priorScope = app.buttons["log-sheet.scope.Yesterday"]
    assertMinimumTarget(todayScope)
    assertMinimumTarget(priorScope)

    let setTotal = app.buttons["log-sheet.amount.set-total"]
    makeHittable(setTotal, direction: .up, in: app)
    XCTAssertEqual(sheet.frame.minY, mediumMinY, accuracy: 4)
    assertLongLowerTotalValidation(
      setTotal: setTotal,
      expectedSheetMinY: mediumMinY,
      in: app
    )

    expandSheet(sheet, in: app)
    let largeMinY = sheet.frame.minY
    XCTAssertLessThan(largeMinY, mediumMinY - 50)
    makeHittable(setTotal, direction: .up, in: app)
    assertLongLowerTotalValidation(
      setTotal: setTotal,
      expectedSheetMinY: largeMinY,
      in: app
    )

    makeHittable(priorScope, direction: .down, in: app)
    priorScope.tap()
    XCTAssertTrue(priorScope.isSelected)
    XCTAssertEqual(element("log-sheet.progress", in: app).label, "3,000 of 8,000 steps")
    makeHittable(element("log-sheet.entries.title", in: app), direction: .up, in: app)
    XCTAssertEqual(element("log-sheet.entries.title", in: app).label, "LOGGED YESTERDAY")
  }

  @MainActor
  private func assertLongLowerTotalValidation(
    setTotal: XCUIElement,
    expectedSheetMinY: CGFloat,
    in app: XCUIApplication
  ) {
    setTotal.tap()
    let amountField = app.textFields["log-sheet.amount.field"]
    XCTAssertTrue(amountField.waitForExistence(timeout: 2))
    replaceText(in: amountField, with: "3000")
    let keyboardSubmit = app.buttons["log-sheet.amount.keyboard-submit"]
    XCTAssertTrue(keyboardSubmit.waitForExistence(timeout: 2))
    keyboardSubmit.tap()

    let error = element("log-sheet.amount.error", in: app)
    XCTAssertEqual(error.label, "Delete an entry before lowering the total.")
    XCTAssertGreaterThan(error.frame.height, 40)
    app.buttons["log-sheet.amount.keyboard-cancel"].tap()
    XCTAssertEqual(
      element("log-sheet", in: app).frame.minY,
      expectedSheetMinY,
      accuracy: 4
    )
  }

  @MainActor
  private func expandSheet(_ sheet: XCUIElement, in app: XCUIApplication) {
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
  private func launch(
    fixture: String,
    storeName: String? = nil,
    reset: Bool = true,
    fixtureInstant: String? = nil,
    additionalArguments: [String] = []
  ) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["TZ"] = "America/Los_Angeles"
    app.launchArguments = launchArguments(
      storeName: storeName ?? "FastLoggingUITests-\(fixture)-\(UUID().uuidString)",
      reset: reset,
      fixture: fixture,
      fixtureInstant: fixtureInstant,
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
