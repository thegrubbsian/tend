import UIKit
import XCTest

final class GoalExperienceUITests: XCTestCase {
  private let ownerStoreName = "GoalExperienceUITests-owner-journey"
  private let emptyStoreName = "GoalExperienceUITests-empty"
  private let fixtureInstant = "2026-01-15T17:00:00Z"

  private enum AbsentTargetSearchDirection {
    case towardStart
    case towardEnd
  }

  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testPersistentGoalsOwnerJourney() throws {
    XCUIDevice.shared.orientation = .portrait
    let app = launch(
      storeName: ownerStoreName,
      reset: true,
      fixture: "goal-experience"
    )

    let todayDestination = element("shell.destination.today", in: app)
    let todayTab = app.buttons["shell.tab.today"]
    XCTAssertTrue(
      todayDestination.waitForExistence(timeout: 5),
      "Expected a cold launch to show Today"
    )
    XCTAssertTrue(todayTab.isSelected, "Expected Today to be selected after a cold launch")
    assertMinimumHitRegion(of: todayTab)

    selectGoals(in: app)
    let goalsTab = app.buttons["shell.tab.goals"]
    let habitsTab = app.buttons["shell.tab.habits"]
    let addGoal = app.buttons["goals.add"]
    XCTAssertTrue(goalsTab.isSelected, "Expected Goals to expose the selected trait")
    XCTAssertFalse(todayTab.isSelected, "Expected Today to clear its selected trait")
    assertMinimumHitRegion(of: goalsTab)
    assertMinimumHitRegion(of: habitsTab)
    assertMinimumHitRegion(of: addGoal)

    let oak = goalRow(id: "11000000-0000-0000-0000-000000000002", in: app)
    XCTAssertTrue(oak.waitForExistence(timeout: 5), "Expected the seeded increasing goal")
    XCTAssertEqual(oak.label, "Grow oak seedlings")
    let oakOutput = "\(oak.label), \(oak.value as? String ?? "")"
    for fragment in ["Behind", "150 centimeters now · 30 of 80 centimeters", "Jan 31, 2026"] {
      XCTAssertTrue(oakOutput.contains(fragment), "Missing \(fragment) from \(oakOutput)")
    }
    assertMinimumHitRegion(of: oak)

    let heartRate = goalRow(id: "11000000-0000-0000-0000-000000000003", in: app)
    XCTAssertTrue(
      heartRate.waitForExistence(timeout: 5),
      "Expected the seeded decreasing goal"
    )
    XCTAssertEqual(heartRate.label, "Lower resting heart rate")
    let heartRateOutput = "\(heartRate.label), \(heartRate.value as? String ?? "")"
    for fragment in [
      "On pace", "70 beats per minute now · 10 of 20 beats per minute", "Jan 31, 2026",
    ] {
      XCTAssertTrue(
        heartRateOutput.contains(fragment),
        "Missing \(fragment) from \(heartRateOutput)"
      )
    }
    assertMinimumHitRegion(of: heartRate)

    try performVisibleAccessibilityAudit(in: app)

    openGoal(oak, in: app)
    let oakProgress = element("goalDetail.progress", in: app)
    let oakProgressValue = oakProgress.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", "Progress")
    ).firstMatch
    XCTAssertTrue(oakProgressValue.waitForExistence(timeout: 2))
    XCTAssertEqual(oakProgressValue.value as? String, "150 centimeters now · 30 of 80 centimeters")
    XCTAssertTrue(app.staticTexts["Increasing measure"].exists)
    XCTAssertTrue(
      app.descendants(matching: .any)[
        "Baseline 120 centimeters, target 200 centimeters"
      ].exists,
      "Expected the increasing span to expose baseline and target"
    )
    XCTAssertEqual(
      element("goalDetail.metadata.deadline", in: app).value as? String,
      "16 days remaining · Due Jan 31, 2026"
    )
    backToGoals(in: app)

    openGoal(heartRate, in: app)
    let heartRateProgress = element("goalDetail.progress", in: app)
    let heartRateProgressValue = heartRateProgress.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", "Progress")
    ).firstMatch
    XCTAssertTrue(heartRateProgressValue.waitForExistence(timeout: 2))
    XCTAssertEqual(
      heartRateProgressValue.value as? String,
      "70 beats per minute now · 10 of 20 beats per minute"
    )
    XCTAssertTrue(app.staticTexts["Decreasing measure"].exists)
    XCTAssertTrue(
      app.descendants(matching: .any)[
        "Baseline 80 beats per minute, target 60 beats per minute"
      ].exists,
      "Expected the decreasing span to expose baseline and target"
    )
    backToGoals(in: app)

    let piano = goalRow(id: "11000000-0000-0000-0000-000000000001", in: app)
    scrollToRosterElement(piano, in: app)
    XCTAssertEqual(piano.label, "Practice piano hours")
    let pianoOutput = "\(piano.label), \(piano.value as? String ?? "")"
    for fragment in ["On pace", "105 of 100 hours", "No deadline"] {
      XCTAssertTrue(pianoOutput.contains(fragment), "Missing \(fragment) from \(pianoOutput)")
    }
    assertMinimumHitRegion(of: piano)

    let pastDueHeader = element("goals.pastDue", in: app)
    XCTAssertTrue(pastDueHeader.exists, "Expected the PAST DUE group")
    let grant = goalRow(id: "11000000-0000-0000-0000-000000000004", in: app)
    scrollToRosterElement(grant, in: app)
    XCTAssertEqual(grant.label, "Submit winter grant application")
    let grantOutput = "\(grant.label), \(grant.value as? String ?? "")"
    for fragment in ["Past due", "7 of 10 sections", "Jan 14, 2026"] {
      XCTAssertTrue(grantOutput.contains(fragment), "Missing \(fragment) from \(grantOutput)")
    }

    let disclosure = app.buttons["goals.closed.disclosure"]
    scrollToRosterElement(disclosure, in: app)
    XCTAssertEqual(disclosure.elementType, .button, "Expected CLOSED disclosure button semantics")
    XCTAssertEqual(disclosure.label, "Closed goals")
    XCTAssertEqual(disclosure.value as? String, "2, collapsed")
    assertMinimumHitRegion(of: disclosure)
    XCTAssertFalse(
      goalRow(id: "11000000-0000-0000-0000-000000000005", in: app).exists,
      "Expected harvested goals to remain collapsed initially"
    )
    XCTAssertFalse(
      goalRow(id: "11000000-0000-0000-0000-000000000006", in: app).exists,
      "Expected let-go goals to remain collapsed initially"
    )

    createAccumulateGoal(in: app)
    var essays = goalRow(named: "Read 24 essays", in: app)
    scrollToRosterElement(essays, in: app)
    let essaysOutput = "\(essays.label), \(essays.value as? String ?? "")"
    for fragment in ["On pace", "0 of 24 essays", "No deadline"] {
      XCTAssertTrue(essaysOutput.contains(fragment), "Missing \(fragment) from \(essaysOutput)")
    }
    assertMinimumHitRegion(of: essays)

    createMeasureGoal(in: app)
    var trail = goalRow(named: "Increase trail distance", in: app)
    scrollToRosterElement(trail, in: app)
    let trailOutput = "\(trail.label), \(trail.value as? String ?? "")"
    for fragment in ["On pace", "5 miles now · 0 of 20 miles", "Jan 15, 2026"] {
      XCTAssertTrue(trailOutput.contains(fragment), "Missing \(fragment) from \(trailOutput)")
    }
    assertMinimumHitRegion(of: trail)
    scrollToRosterElement(heartRate, in: app)
    scrollRosterRowsIntoSameViewport(trail, heartRate, in: app)
    XCTAssertTrue(
      trail.exists && trail.isHittable,
      "Expected Increase trail distance to remain materialized and hittable for ordering"
    )
    XCTAssertTrue(
      heartRate.exists && heartRate.isHittable,
      "Expected Lower resting heart rate to remain materialized and hittable for ordering"
    )
    XCTAssertLessThan(
      trail.frame.minY,
      heartRate.frame.minY,
      "Expected the Jan 15 measure deadline before the Jan 31 on-pace goal"
    )

    scrollToRosterElement(piano, in: app)
    openGoal(piano, in: app)
    XCTAssertEqual(element("goalDetail.title", in: app).label, "Practice piano hours")
    let initialPianoProgress = element("goalDetail.progress", in: app).descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", "Progress")).firstMatch
    XCTAssertTrue(initialPianoProgress.waitForExistence(timeout: 2))
    XCTAssertEqual(initialPianoProgress.value as? String, "105 of 100 hours")
    XCTAssertEqual(element("goalDetail.metadata.kind", in: app).value as? String, "Accumulate")
    XCTAssertEqual(element("goalDetail.metadata.deadline", in: app).value as? String, "No deadline")

    let seededTodayHistory = element(
      "goalDetail.history.row.entry.21000000-0000-0000-0000-000000000002",
      in: app
    )
    let historicalHistory = element(
      "goalDetail.history.row.entry.21000000-0000-0000-0000-000000000001",
      in: app
    )
    scrollToVisible(seededTodayHistory, absentTargetSearchDirection: .towardEnd, in: app)
    XCTAssertEqual(seededTodayHistory.label, "Today, 10 hours")
    let seededTodayDelete = element(
      "goalDetail.history.delete.entry.21000000-0000-0000-0000-000000000002",
      in: app
    )
    XCTAssertTrue(seededTodayDelete.exists, "Expected today's seeded entry to be delete eligible")
    assertMinimumHitRegion(of: seededTodayDelete)
    scrollToVisible(historicalHistory, absentTargetSearchDirection: .towardEnd, in: app)
    XCTAssertEqual(historicalHistory.label, "Jan 1, 2026, 95 hours")
    XCTAssertFalse(
      element(
        "goalDetail.history.delete.entry.21000000-0000-0000-0000-000000000001",
        in: app
      ).exists,
      "Expected the Jan 1 entry to expose no delete action"
    )

    addProgress("3", destination: "today", in: app)
    let progressAfterToday = element("goalDetail.progress", in: app).descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", "Progress")).firstMatch
    XCTAssertEqual(progressAfterToday.value as? String, "108 of 100 hours")

    addProgress("2", destination: "yesterday", in: app)
    let progressAfterYesterday = element("goalDetail.progress", in: app).descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", "Progress")).firstMatch
    XCTAssertEqual(progressAfterYesterday.value as? String, "110 of 100 hours")

    let expectedHistoryLabels = [
      "Today, 3 hours",
      "Today, 10 hours",
      "Yesterday, 2 hours",
      "Jan 1, 2026, 95 hours",
    ]
    for label in expectedHistoryLabels {
      let historyRow = app.descendants(matching: .any).matching(
        NSPredicate(
          format: "identifier BEGINSWITH %@ AND label == %@",
          "goalDetail.history.row.entry.",
          label
        )
      ).firstMatch
      scrollToVisible(historyRow, absentTargetSearchDirection: .towardEnd, in: app)
      XCTAssertEqual(historyRow.label, label, "Expected complete piano history item \(label)")
    }

    let yesterdayDelete = app.buttons.matching(
      NSPredicate(format: "label == %@", "Delete entry, 2 hours, Yesterday")
    ).firstMatch
    scrollToVisible(yesterdayDelete, absentTargetSearchDirection: .towardStart, in: app)
    assertMinimumHitRegion(of: yesterdayDelete)
    yesterdayDelete.tap()
    XCTAssertTrue(app.staticTexts["Delete this entry?"].waitForExistence(timeout: 2))
    XCTAssertTrue(
      app.staticTexts[
        "This permanently removes the 2 hours entry for Yesterday and recalculates the goal's progress. This cannot be undone."
      ].exists
    )
    confirmPendingAction(named: "Delete Entry", in: app)
    XCTAssertTrue(
      app.descendants(matching: .any).matching(
        NSPredicate(format: "label == %@", "Yesterday, 2 hours")
      ).firstMatch.waitForNonExistence(timeout: 2),
      "Expected the confirmed eligible entry deletion to remove Yesterday"
    )
    let progressAfterHistoryDeletion = element("goalDetail.progress", in: app)
      .descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", "Progress")).firstMatch
    XCTAssertEqual(progressAfterHistoryDeletion.value as? String, "108 of 100 hours")

    scrollToVisible(
      element("goalDetail.edit", in: app),
      absentTargetSearchDirection: .towardStart,
      in: app
    )
    element("goalDetail.edit", in: app).tap()
    XCTAssertTrue(element("goalForm.sheet", in: app).waitForExistence(timeout: 2))
    XCTAssertEqual(element("goalForm.kind.locked", in: app).label, "Kind, Accumulate, locked")
    XCTAssertTrue(element("goalForm.kind.explanation", in: app).exists)
    XCTAssertFalse(element("goalForm.kind.measure", in: app).exists)
    let editedTarget = app.textFields["goalForm.target"]
    XCTAssertEqual(editedTarget.value as? String, "100")
    replaceText(in: editedTarget, with: "120")
    let editSave = app.buttons["goalForm.save"]
    XCTAssertTrue(editSave.isEnabled)
    editSave.tap()
    XCTAssertTrue(element("goalForm.sheet", in: app).waitForNonExistence(timeout: 5))
    let recomputedProgress = element("goalDetail.progress", in: app).descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", "Progress")).firstMatch
    XCTAssertEqual(recomputedProgress.value as? String, "108 of 120 hours")
    XCTAssertTrue(app.staticTexts["On pace"].exists, "Expected standing to recompute after editing")

    backToGoals(in: app)
    essays = goalRow(named: "Read 24 essays", in: app)
    scrollToRosterElement(essays, in: app)
    openGoal(essays, in: app)
    let harvest = element("goalDetail.harvest", in: app)
    scrollToVisible(harvest, absentTargetSearchDirection: .towardEnd, in: app)
    assertMinimumHitRegion(of: harvest)
    harvest.tap()
    XCTAssertTrue(app.staticTexts["Harvest “Read 24 essays”?"].waitForExistence(timeout: 2))
    XCTAssertTrue(
      app.staticTexts[
        "This closes “Read 24 essays” as harvested and keeps its progress history. You can reopen it later."
      ].exists
    )
    confirmPendingAction(named: "Harvest", in: app)
    XCTAssertTrue(app.staticTexts["Harvested"].waitForExistence(timeout: 2))
    XCTAssertFalse(element("goalDetail.addProgress", in: app).exists)
    XCTAssertTrue(element("goalDetail.reopen", in: app).exists)
    backToGoals(in: app)

    let disclosureAfterHarvest = app.buttons["goals.closed.disclosure"]
    scrollToRosterElement(disclosureAfterHarvest, in: app)
    XCTAssertEqual(disclosureAfterHarvest.value as? String, "3, collapsed")
    scrollRosterToTop(in: app)

    trail = goalRow(named: "Increase trail distance", in: app)
    scrollToRosterElement(trail, in: app)
    openGoal(trail, in: app)
    let letGo = element("goalDetail.letGo", in: app)
    scrollToVisible(letGo, absentTargetSearchDirection: .towardEnd, in: app)
    assertMinimumHitRegion(of: letGo)
    letGo.tap()
    XCTAssertTrue(
      app.staticTexts["Let go of “Increase trail distance”?"].waitForExistence(timeout: 2)
    )
    XCTAssertTrue(
      app.staticTexts[
        "This closes “Increase trail distance” as let go and keeps its progress history. You can reopen it later."
      ].exists
    )
    confirmPendingAction(named: "Let go", in: app)
    XCTAssertTrue(app.staticTexts["Let go"].waitForExistence(timeout: 2))
    XCTAssertTrue(element("goalDetail.reopen", in: app).exists)
    backToGoals(in: app)

    let disclosureAfterLetGo = app.buttons["goals.closed.disclosure"]
    scrollToRosterElement(disclosureAfterLetGo, in: app)
    XCTAssertEqual(disclosureAfterLetGo.value as? String, "4, collapsed")
    disclosureAfterLetGo.tap()
    XCTAssertEqual(disclosureAfterLetGo.value as? String, "4, expanded")

    essays = goalRow(named: "Read 24 essays", in: app)
    scrollToRosterElement(essays, in: app)
    let harvestedOutput = "\(essays.label), \(essays.value as? String ?? "")"
    XCTAssertTrue(harvestedOutput.contains("Harvested"), "Expected textual harvested closure")
    scrollRosterToTop(in: app)
    trail = goalRow(named: "Increase trail distance", in: app)
    scrollToRosterElement(trail, in: app)
    let letGoOutput = "\(trail.label), \(trail.value as? String ?? "")"
    XCTAssertTrue(letGoOutput.contains("Let go"), "Expected textual let-go closure")

    openGoal(trail, in: app)
    let reopen = element("goalDetail.reopen", in: app)
    scrollToVisible(reopen, absentTargetSearchDirection: .towardEnd, in: app)
    assertMinimumHitRegion(of: reopen)
    reopen.tap()
    XCTAssertTrue(
      app.staticTexts["Reopen “Increase trail distance”?"].waitForExistence(timeout: 2)
    )
    XCTAssertTrue(
      app.staticTexts[
        "This reopens “Increase trail distance” and makes progress entry available again."
      ].exists
    )
    confirmPendingAction(named: "Reopen", in: app)
    XCTAssertTrue(element("goalDetail.addProgress", in: app).waitForExistence(timeout: 2))
    XCTAssertFalse(element("goalDetail.reopen", in: app).exists)
    backToGoals(in: app)

    let disclosureAfterReopen = app.buttons["goals.closed.disclosure"]
    scrollToRosterElement(disclosureAfterReopen, in: app)
    XCTAssertEqual(disclosureAfterReopen.value as? String, "3, expanded")
    scrollRosterToTop(in: app)
    trail = goalRow(named: "Increase trail distance", in: app)
    scrollToRosterElement(trail, in: app)
    let reopenedTrailOutput = "\(trail.label), \(trail.value as? String ?? "")"
    XCTAssertTrue(reopenedTrailOutput.contains("On pace"), "Expected reopened goal in OPEN")

    let pianoForDeletion = goalRow(id: "11000000-0000-0000-0000-000000000001", in: app)
    scrollToRosterElement(pianoForDeletion, in: app)
    openGoal(pianoForDeletion, in: app)
    let deleteGoal = element("goalDetail.deleteGoal", in: app)
    scrollToVisible(deleteGoal, absentTargetSearchDirection: .towardEnd, in: app)
    assertMinimumHitRegion(of: deleteGoal)
    deleteGoal.tap()
    XCTAssertTrue(
      app.staticTexts["Delete “Practice piano hours” permanently?"].waitForExistence(timeout: 2)
    )
    XCTAssertTrue(
      app.staticTexts[
        "This permanently deletes “Practice piano hours” and removes all of its entry history. This cannot be undone."
      ].exists
    )
    let cancelDeletion = app.buttons["goalDetail.confirmation.cancel"]
    XCTAssertTrue(cancelDeletion.exists)
    cancelDeletion.tap()
    XCTAssertTrue(element("goalDetail.title", in: app).exists, "Cancel must preserve the goal")

    scrollToVisible(deleteGoal, absentTargetSearchDirection: .towardEnd, in: app)
    deleteGoal.tap()
    confirmPendingAction(named: "Delete Goal", in: app)
    XCTAssertTrue(
      element("shell.destination.goals", in: app).waitForExistence(timeout: 5),
      "Expected confirmed goal deletion to return to Goals"
    )
    XCTAssertFalse(
      goalExistsAfterScanningRoster(named: "Practice piano hours", in: app),
      "Expected Practice piano hours to be absent after deletion"
    )

    app.terminate()
    app.launchArguments = launchArguments(
      storeName: ownerStoreName,
      reset: false,
      fixture: nil
    )
    app.launch()

    XCTAssertTrue(
      element("shell.destination.today", in: app).waitForExistence(timeout: 5),
      "Expected the same-store relaunch to cold-launch on Today"
    )
    selectGoals(in: app)
    XCTAssertFalse(
      goalExistsAfterScanningRoster(named: "Practice piano hours", in: app),
      "Expected the deleted goal to remain absent after same-store relaunch"
    )

    scrollRosterToTop(in: app)
    trail = goalRow(named: "Increase trail distance", in: app)
    scrollToRosterElement(trail, in: app)
    let persistedTrailOutput = "\(trail.label), \(trail.value as? String ?? "")"
    for fragment in ["On pace", "5 miles now · 0 of 20 miles", "Jan 15, 2026"] {
      XCTAssertTrue(
        persistedTrailOutput.contains(fragment),
        "Expected reopened measure mutation to persist: missing \(fragment) from \(persistedTrailOutput)"
      )
    }

    let persistedDisclosure = app.buttons["goals.closed.disclosure"]
    scrollToRosterElement(persistedDisclosure, in: app)
    XCTAssertEqual(persistedDisclosure.value as? String, "3, collapsed")
    persistedDisclosure.tap()
    XCTAssertEqual(persistedDisclosure.value as? String, "3, expanded")
    essays = goalRow(named: "Read 24 essays", in: app)
    scrollToRosterElement(essays, in: app)
    let persistedEssaysOutput = "\(essays.label), \(essays.value as? String ?? "")"
    for fragment in ["Harvested", "0 of 24 essays", "No deadline"] {
      XCTAssertTrue(
        persistedEssaysOutput.contains(fragment),
        "Expected harvested accumulate mutation to persist: missing \(fragment) from \(persistedEssaysOutput)"
      )
    }
  }

  @MainActor
  func testEmptyNamedStoreShowsGoalsEmptyState() {
    XCUIDevice.shared.orientation = .portrait
    let app = launch(
      storeName: emptyStoreName,
      reset: true,
      fixture: nil
    )

    XCTAssertTrue(
      element("shell.destination.today", in: app).waitForExistence(timeout: 5),
      "Expected an empty named store to cold-launch on Today"
    )
    selectGoals(in: app)

    let emptyState = element("goals.empty", in: app)
    XCTAssertTrue(emptyState.waitForExistence(timeout: 5), "Expected the no-goals empty state")
    XCTAssertTrue(app.staticTexts["No goals yet"].exists)
    XCTAssertTrue(
      app.staticTexts[
        "Create a goal to track progress toward something that matters."
      ].exists
    )
    let emptyAction = app.buttons["goals.empty.add"]
    XCTAssertTrue(emptyAction.exists)
    XCTAssertEqual(emptyAction.label, "New goal")
    assertMinimumHitRegion(of: emptyAction)
    XCTAssertTrue(app.buttons["shell.tab.goals"].isSelected)
    XCTAssertFalse(app.buttons["goals.closed.disclosure"].exists)
  }

  @MainActor
  func testCompactPortraitRosterAndFormRemainAccessible() throws {
    XCUIDevice.shared.orientation = .portrait
    let app = launchAdaptiveStore(named: "compact")
    selectGoals(in: app)

    let window = app.windows.firstMatch
    XCTAssertTrue(window.exists)
    XCTAssertLessThan(window.frame.width, window.frame.height)

    let goalsTab = app.buttons["shell.tab.goals"]
    XCTAssertTrue(goalsTab.isSelected, "Expected Goals to retain selected state")
    XCTAssertEqual(goalsTab.label, "Goals")
    let oak = goalRow(id: "11000000-0000-0000-0000-000000000002", in: app)
    scrollToRosterElement(oak, in: app)
    assertWithinUnobscuredRosterViewport(oak, in: app)
    XCTAssertEqual(oak.elementType, .button)
    XCTAssertEqual(oak.label, "Grow oak seedlings")
    XCTAssertTrue(
      (oak.value as? String)?.contains("Behind") == true,
      "Expected the behind state to be available as text rather than color alone"
    )
    try performVisibleAccessibilityAudit(in: app)
    recordScreenshot("goal-experience-compact-roster", of: app)

    scrollRosterToTop(in: app)
    let add = app.buttons["goals.add"]
    XCTAssertEqual(add.label, "New goal")
    add.tap()

    let sheet = element("goalForm.sheet", in: app)
    XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Expected the New goal sheet")
    XCTAssertEqual(element("goalForm.title", in: app).label, "New goal")
    let accumulate = app.buttons["goalForm.kind.accumulate"]
    let measure = app.buttons["goalForm.kind.measure"]
    XCTAssertTrue(accumulate.isSelected)
    XCTAssertEqual(accumulate.value as? String, "Selected")
    XCTAssertFalse(measure.isSelected)
    XCTAssertEqual(measure.value as? String, "Not selected")
    assertMinimumHitRegion(of: accumulate)
    assertMinimumHitRegion(of: measure)
    assertWithinWindow(element("goalForm.name", in: app), in: app)
    recordScreenshot("goal-experience-form", of: app)

    let cancel = app.buttons["goalForm.cancel"]
    XCTAssertEqual(cancel.label, "Cancel")
    assertMinimumHitRegion(of: cancel)
    cancel.tap()
    XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
  }

  @MainActor
  func testLandscapeRosterKeepsContentInsideTheUnobscuredViewport() throws {
    XCUIDevice.shared.orientation = .portrait
    let app = launchAdaptiveStore(named: "landscape")
    selectGoals(in: app)

    XCUIDevice.shared.orientation = .landscapeLeft
    let landscape = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        let frame = app.windows.firstMatch.frame
        return frame.width > frame.height
      },
      object: app
    )
    wait(for: [landscape], timeout: 5)

    let oak = goalRow(id: "11000000-0000-0000-0000-000000000002", in: app)
    scrollToRosterElement(oak, in: app)
    assertWithinUnobscuredRosterViewport(oak, in: app)
    let window = app.windows.firstMatch
    XCTAssertGreaterThanOrEqual(oak.frame.minX, window.frame.minX)
    XCTAssertLessThanOrEqual(oak.frame.maxX, window.frame.maxX)
    XCTAssertTrue(app.buttons["shell.tab.goals"].isSelected)
    XCTAssertTrue((oak.value as? String)?.contains("Behind") == true)
    try performVisibleAccessibilityAudit(in: app)
    recordScreenshot("goal-experience-landscape", of: app)
  }

  @MainActor
  func testRosterAndControlsReflowAtAccessibilityLargeAndXXL() {
    XCUIDevice.shared.orientation = .portrait
    let compactApp = launchAdaptiveStore(named: "dynamic-type-baseline")
    selectGoals(in: compactApp)
    let compactOak = goalRow(id: "11000000-0000-0000-0000-000000000002", in: compactApp)
    XCTAssertTrue(compactOak.waitForExistence(timeout: 5))
    let compactRowHeight = compactOak.frame.height
    compactApp.terminate()

    let categories = [
      "UICTContentSizeCategoryAccessibilityL",
      "UICTContentSizeCategoryAccessibilityXXL",
    ]
    for (index, category) in categories.enumerated() {
      let app = launchAdaptiveStore(
        named: "dynamic-type-\(index)",
        additionalArguments: [
          "-UIPreferredContentSizeCategoryName", category,
        ]
      )
      selectGoals(in: app)

      let oak = goalRow(id: "11000000-0000-0000-0000-000000000002", in: app)
      XCTAssertTrue(oak.waitForExistence(timeout: 5))
      XCTAssertGreaterThan(
        oak.frame.height,
        compactRowHeight,
        "Expected accessibility text to grow or wrap the compact row"
      )
      XCTAssertTrue((oak.value as? String)?.contains("Behind") == true)
      assertWithinUnobscuredRosterViewport(oak, in: app)

      let disclosure = app.buttons["goals.closed.disclosure"]
      scrollToRosterElement(disclosure, in: app)
      assertWithinUnobscuredRosterViewport(disclosure, in: app)
      XCTAssertEqual(disclosure.elementType, .button)
      XCTAssertEqual(disclosure.label, "Closed goals")
      XCTAssertEqual(disclosure.value as? String, "2, collapsed")

      if index == categories.count - 1 {
        recordScreenshot("goal-experience-larger-text", of: app)
        scrollRosterToTop(in: app)
        app.buttons["goals.add"].tap()
        let deadline = app.buttons["goalForm.deadline.add"]
        scrollToVisible(deadline, absentTargetSearchDirection: .towardEnd, in: app)
        XCTAssertEqual(deadline.label, "Deadline, none")
        assertMinimumHitRegion(of: deadline)
        assertWithinWindow(deadline, in: app)
        XCTAssertTrue(app.buttons["goalForm.kind.accumulate"].isSelected)
        app.buttons["goalForm.cancel"].tap()
        XCTAssertTrue(element("goalForm.sheet", in: app).waitForNonExistence(timeout: 5))
      }
      app.terminate()
    }
  }

  @MainActor
  func testReduceMotionTransitionsExposeDetailProgressAndLifecycleSemantics() {
    XCUIDevice.shared.orientation = .portrait
    let app = launchAdaptiveStore(
      named: "reduce-motion",
      additionalArguments: [
        "-UIAccessibilityReduceMotionEnabled", "YES",
      ]
    )
    selectGoals(in: app)
    XCTAssertTrue(app.buttons["shell.tab.goals"].isSelected)

    let oak = goalRow(id: "11000000-0000-0000-0000-000000000002", in: app)
    scrollToRosterElement(oak, in: app)
    openGoal(oak, in: app)
    XCTAssertEqual(element("goalDetail.title", in: app).label, "Grow oak seedlings")
    let detailProgress = element("goalDetail.progress", in: app).descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", "Progress")).firstMatch
    XCTAssertTrue(detailProgress.waitForExistence(timeout: 2))
    XCTAssertEqual(
      detailProgress.value as? String,
      "150 centimeters now · 30 of 80 centimeters"
    )
    XCTAssertEqual(
      element("goalDetail.metadata.deadline", in: app).value as? String,
      "16 days remaining · Due Jan 31, 2026"
    )
    recordScreenshot("goal-experience-detail", of: app)
    backToGoals(in: app)

    let piano = goalRow(id: "11000000-0000-0000-0000-000000000001", in: app)
    scrollToRosterElement(piano, in: app)
    openGoal(piano, in: app)
    let addProgress = element("goalDetail.addProgress", in: app)
    scrollToVisible(addProgress, absentTargetSearchDirection: .towardStart, in: app)
    addProgress.tap()
    let progressSheet = element("goalProgressEntry.sheet", in: app)
    XCTAssertTrue(progressSheet.waitForExistence(timeout: 2))
    XCTAssertEqual(element("goalProgressEntry.title", in: app).label, "Add progress")
    XCTAssertEqual(element("goalProgressEntry.goalName", in: app).label, "Practice piano hours")
    let today = app.buttons["goalProgressEntry.destination.today"]
    let yesterday = app.buttons["goalProgressEntry.destination.yesterday"]
    XCTAssertTrue(today.isSelected)
    XCTAssertEqual(today.value as? String, "Selected")
    XCTAssertFalse(yesterday.isSelected)
    XCTAssertEqual(yesterday.value as? String, "Not selected")
    XCTAssertEqual(app.textFields["goalProgressEntry.value"].label, "Amount")
    recordScreenshot("goal-experience-progress-entry", of: app)
    app.buttons["goalProgressEntry.cancel"].tap()
    XCTAssertTrue(progressSheet.waitForNonExistence(timeout: 5))
    backToGoals(in: app)

    let disclosure = app.buttons["goals.closed.disclosure"]
    scrollToRosterElement(disclosure, in: app)
    XCTAssertEqual(disclosure.elementType, .button)
    XCTAssertEqual(disclosure.label, "Closed goals")
    XCTAssertEqual(disclosure.value as? String, "2, collapsed")
    recordScreenshot("goal-experience-closed-disclosure", of: app)
    disclosure.tap()
    XCTAssertEqual(disclosure.value as? String, "2, expanded")

    let harvested = goalRow(id: "11000000-0000-0000-0000-000000000005", in: app)
    scrollToRosterElement(harvested, in: app)
    XCTAssertTrue((harvested.value as? String)?.contains("Harvested") == true)
    openGoal(harvested, in: app)
    XCTAssertTrue(app.staticTexts["Harvested"].waitForExistence(timeout: 2))
    let reopen = element("goalDetail.reopen", in: app)
    scrollToVisible(reopen, absentTargetSearchDirection: .towardEnd, in: app)
    XCTAssertEqual(reopen.label, "Reopen")
    XCTAssertFalse(element("goalDetail.addProgress", in: app).exists)
    recordScreenshot("goal-experience-lifecycle-states", of: app)
  }

  @MainActor
  private func launch(
    storeName: String,
    reset: Bool,
    fixture: String?,
    additionalArguments: [String] = []
  ) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["TZ"] = "America/Los_Angeles"
    app.launchArguments =
      launchArguments(
        storeName: storeName,
        reset: reset,
        fixture: fixture
      ) + additionalArguments
    app.terminate()
    app.launch()
    return app
  }

  @MainActor
  private func launchAdaptiveStore(
    named name: String,
    additionalArguments: [String] = []
  ) -> XCUIApplication {
    launch(
      storeName: "GoalExperienceUITests-\(name)-\(UUID().uuidString)",
      reset: true,
      fixture: "goal-experience",
      additionalArguments: additionalArguments
    )
  }

  private func launchArguments(
    storeName: String,
    reset: Bool,
    fixture: String?
  ) -> [String] {
    var arguments = [
      "-AppleLanguages", "(en)",
      "-AppleLocale", "en_US",
      "-tend-ui-testing",
      "-tend-ui-test-store", storeName,
      "-tend-ui-test-instant", fixtureInstant,
    ]
    if reset {
      arguments.append("-tend-ui-test-reset")
    }
    if let fixture {
      arguments.append(contentsOf: ["-tend-ui-test-fixture", fixture])
    }
    return arguments
  }

  @MainActor
  private func selectGoals(in app: XCUIApplication) {
    let goalsTab = app.buttons["shell.tab.goals"]
    XCTAssertTrue(goalsTab.waitForExistence(timeout: 5), "Expected the Goals tab")
    goalsTab.tap()
    XCTAssertTrue(
      element("shell.destination.goals", in: app).waitForExistence(timeout: 5),
      "Expected Goals after selecting its tab"
    )
    XCTAssertTrue(goalsTab.isSelected, "Expected Goals to expose the selected trait")
  }

  @MainActor
  private func createAccumulateGoal(in app: XCUIApplication) {
    scrollRosterToTop(in: app)
    let add = app.buttons["goals.add"]
    scrollToRosterElement(add, in: app)
    add.tap()

    XCTAssertTrue(element("goalForm.sheet", in: app).waitForExistence(timeout: 5))
    XCTAssertEqual(element("goalForm.title", in: app).label, "New goal")
    let name = app.textFields["goalForm.name"]
    let target = app.textFields["goalForm.target"]
    let unit = app.textFields["goalForm.unit"]
    let accumulate = app.buttons["goalForm.kind.accumulate"]
    let measure = app.buttons["goalForm.kind.measure"]
    let save = app.buttons["goalForm.save"]
    XCTAssertTrue(name.waitForExistence(timeout: 2))
    XCTAssertEqual(name.value as? String, "Read every day")
    XCTAssertEqual(target.value as? String, "1")
    XCTAssertEqual(unit.value as? String, "times")
    XCTAssertTrue(accumulate.isSelected)
    XCTAssertEqual(accumulate.value as? String, "Selected")
    XCTAssertFalse(measure.isSelected)
    XCTAssertEqual(measure.value as? String, "Not selected")
    XCTAssertFalse(app.textFields["goalForm.baseline"].exists)
    XCTAssertEqual(app.buttons["goalForm.deadline.add"].label, "Deadline, none")
    XCTAssertFalse(save.isEnabled)
    assertMinimumHitRegion(of: accumulate)
    assertMinimumHitRegion(of: measure)

    name.tap()
    target.tap()
    XCTAssertTrue(
      element("goalForm.name.error", in: app).waitForExistence(timeout: 2),
      "Expected required-name validation"
    )
    XCTAssertEqual(
      element("goalForm.name.error", in: app).label,
      "Name error. Enter a goal name."
    )

    replaceText(in: target, with: "0")
    unit.tap()
    XCTAssertTrue(
      element("goalForm.target.error", in: app).waitForExistence(timeout: 2),
      "Expected positive-target validation"
    )
    XCTAssertEqual(
      element("goalForm.target.error", in: app).label,
      "Target error. Enter a whole number greater than zero."
    )

    replaceText(in: unit, with: "")
    name.tap()
    XCTAssertTrue(
      element("goalForm.unit.error", in: app).waitForExistence(timeout: 2),
      "Expected required-unit validation"
    )
    XCTAssertEqual(element("goalForm.unit.error", in: app).label, "Unit error. Enter a unit.")
    XCTAssertFalse(save.isEnabled)

    replaceText(in: name, with: "Read 24 essays")
    replaceText(in: target, with: "24")
    replaceText(in: unit, with: "essays")
    XCTAssertTrue(save.isEnabled, "Expected a valid Accumulate goal to save")
    assertMinimumHitRegion(of: save)
    save.tap()
    XCTAssertTrue(
      element("goalForm.sheet", in: app).waitForNonExistence(timeout: 5),
      "Expected the saved Accumulate form to dismiss"
    )
  }

  @MainActor
  private func createMeasureGoal(in app: XCUIApplication) {
    scrollRosterToTop(in: app)
    let add = app.buttons["goals.add"]
    scrollToRosterElement(add, in: app)
    add.tap()

    XCTAssertTrue(element("goalForm.sheet", in: app).waitForExistence(timeout: 5))
    let measure = app.buttons["goalForm.kind.measure"]
    measure.tap()
    XCTAssertTrue(measure.isSelected, "Expected Measure to expose the selected trait")
    XCTAssertFalse(app.buttons["goalForm.kind.accumulate"].isSelected)

    let name = app.textFields["goalForm.name"]
    let target = app.textFields["goalForm.target"]
    let unit = app.textFields["goalForm.unit"]
    let baseline = app.textFields["goalForm.baseline"]
    XCTAssertTrue(baseline.waitForExistence(timeout: 2), "Expected Measure baseline input")
    XCTAssertEqual(baseline.value as? String, "0")
    replaceText(in: name, with: "Increase trail distance")
    replaceText(in: target, with: "25")
    replaceText(in: unit, with: "miles")
    replaceText(in: baseline, with: "5")

    let keyboardDone = app.buttons["goalForm.keyboardDone"]
    if keyboardDone.waitForExistence(timeout: 1) {
      keyboardDone.tap()
    }
    let addDeadline = app.buttons["goalForm.deadline.add"]
    scrollToVisible(addDeadline, absentTargetSearchDirection: .towardEnd, in: app)
    assertMinimumHitRegion(of: addDeadline)
    addDeadline.tap()
    let deadlinePicker = element("goalForm.deadline.picker", in: app)
    XCTAssertTrue(
      deadlinePicker.waitForExistence(timeout: 2),
      "Expected adding the deadline to expose the real date picker"
    )
    XCTAssertTrue(element("goalForm.deadline.remove", in: app).exists)

    let save = app.buttons["goalForm.save"]
    XCTAssertTrue(save.isEnabled, "Expected the validated Measure goal to save")
    assertMinimumHitRegion(of: save)
    save.tap()
    XCTAssertTrue(
      element("goalForm.sheet", in: app).waitForNonExistence(timeout: 5),
      "Expected the saved Measure form to dismiss"
    )
  }

  @MainActor
  private func openGoal(_ row: XCUIElement, in app: XCUIApplication) {
    XCTAssertTrue(row.exists, "Expected goal row before opening details")
    XCTAssertTrue(row.isHittable, "Expected \(row.label) to be hittable before opening details")
    row.tap()
    XCTAssertTrue(
      element("goalDetail.screen", in: app).waitForExistence(timeout: 5),
      "Expected goal details after selecting \(row.label)"
    )
  }

  @MainActor
  private func backToGoals(in app: XCUIApplication) {
    let back = element("goalDetail.back", in: app)
    XCTAssertTrue(back.waitForExistence(timeout: 2), "Expected Back in goal details")
    assertMinimumHitRegion(of: back)
    back.tap()
    XCTAssertTrue(
      element("shell.destination.goals", in: app).waitForExistence(timeout: 5),
      "Expected Back to return to Goals"
    )
  }

  @MainActor
  private func addProgress(
    _ value: String,
    destination: String,
    in app: XCUIApplication
  ) {
    let add = element("goalDetail.addProgress", in: app)
    scrollToVisible(add, absentTargetSearchDirection: .towardStart, in: app)
    assertMinimumHitRegion(of: add)
    add.tap()
    XCTAssertTrue(element("goalProgressEntry.sheet", in: app).waitForExistence(timeout: 2))

    let today = app.buttons["goalProgressEntry.destination.today"]
    let yesterday = app.buttons["goalProgressEntry.destination.yesterday"]
    XCTAssertTrue(today.exists)
    XCTAssertTrue(yesterday.exists)
    assertMinimumHitRegion(of: today)
    assertMinimumHitRegion(of: yesterday)
    let selectedDestination = app.buttons["goalProgressEntry.destination.\(destination)"]
    selectedDestination.tap()
    XCTAssertTrue(selectedDestination.isSelected, "Expected \(destination) to expose selection")
    XCTAssertEqual(selectedDestination.value as? String, "Selected")

    replaceText(in: app.textFields["goalProgressEntry.value"], with: value)
    let save = app.buttons["goalProgressEntry.save"]
    XCTAssertTrue(save.isEnabled, "Expected valid progress to save")
    assertMinimumHitRegion(of: save)
    save.tap()
    XCTAssertTrue(
      element("goalProgressEntry.sheet", in: app).waitForNonExistence(timeout: 5),
      "Expected saved progress to dismiss its sheet"
    )
  }

  @MainActor
  private func confirmPendingAction(named title: String, in app: XCUIApplication) {
    let confirm = app.buttons["goalDetail.confirmation.confirm"]
    XCTAssertTrue(confirm.waitForExistence(timeout: 2), "Expected confirmation action \(title)")
    XCTAssertEqual(confirm.label, title)
    confirm.tap()
    XCTAssertTrue(
      confirm.waitForNonExistence(timeout: 5),
      "Expected confirmed \(title) action to complete"
    )
  }

  @MainActor
  private func replaceText(in field: XCUIElement, with replacement: String) {
    XCTAssertTrue(field.waitForExistence(timeout: 2), "Expected editable field \(field.identifier)")
    field.tap()
    field.tap(withNumberOfTaps: 3, numberOfTouches: 1)
    field.typeText(
      replacement.isEmpty
        ? XCUIKeyboardKey.delete.rawValue
        : replacement
    )
  }

  @MainActor
  private func scrollToRosterElement(_ target: XCUIElement, in app: XCUIApplication) {
    let overlay = app.buttons["shell.tab.goals"]
    for _ in 0..<24 {
      guard overlay.exists else {
        XCTFail("Expected Goals tab overlay while scrolling to \(target.identifier)")
        return
      }
      if target.exists {
        let frame = target.frame
        let top = element("shell.destination.goals", in: app).frame.minY
        let bottom = overlay.frame.minY
        if target.isHittable, frame.minY >= top, frame.maxY <= bottom {
          return
        }
        if frame.minY < top {
          app.swipeDown(velocity: .slow)
          continue
        }
      }
      app.swipeUp(velocity: .slow)
    }
    XCTFail(
      "Expected \(target.identifier.isEmpty ? target.label : target.identifier) to become fully visible above the Goals tab"
    )
  }

  @MainActor
  private func scrollRosterRowsIntoSameViewport(
    _ first: XCUIElement,
    _ second: XCUIElement,
    in app: XCUIApplication
  ) {
    let overlay = app.buttons["shell.tab.goals"]
    for _ in 0..<12 {
      guard overlay.exists else {
        XCTFail("Expected Goals tab overlay while aligning adjacent goal rows")
        return
      }
      let top = element("shell.destination.goals", in: app).frame.minY
      let bottom = overlay.frame.minY
      let firstIsVisible =
        first.exists && first.isHittable
        && first.frame.minY >= top && first.frame.maxY <= bottom
      let secondIsVisible =
        second.exists && second.isHittable
        && second.frame.minY >= top && second.frame.maxY <= bottom
      if firstIsVisible && secondIsVisible {
        return
      }
      if !second.exists || second.frame.maxY > bottom {
        app.swipeUp(velocity: .slow)
      } else {
        app.swipeDown(velocity: .slow)
      }
    }
    XCTFail(
      "Expected \(first.label) and \(second.label) to be fully visible together for ordering"
    )
  }

  @MainActor
  private func scrollToVisible(
    _ target: XCUIElement,
    absentTargetSearchDirection: AbsentTargetSearchDirection,
    in app: XCUIApplication
  ) {
    for _ in 0..<24 {
      if target.exists, target.isHittable {
        return
      }
      if target.exists {
        let windowFrame = app.windows.firstMatch.frame
        if target.frame.midY < windowFrame.midY {
          app.swipeDown(velocity: .slow)
        } else {
          app.swipeUp(velocity: .slow)
        }
      } else {
        switch absentTargetSearchDirection {
        case .towardStart:
          app.swipeDown(velocity: .slow)
        case .towardEnd:
          app.swipeUp(velocity: .slow)
        }
      }
    }
    XCTFail(
      "Expected \(target.identifier.isEmpty ? target.label : target.identifier) to become visible and hittable while searching \(absentTargetSearchDirection)"
    )
  }

  @MainActor
  private func scrollRosterToTop(in app: XCUIApplication) {
    for _ in 0..<16 {
      let add = app.buttons["goals.add"]
      if add.exists, add.isHittable {
        return
      }
      app.swipeDown(velocity: .fast)
    }
    XCTFail("Expected the Goals New goal action to become visible at the top of the roster")
  }

  @MainActor
  private func goalExistsAfterScanningRoster(
    named name: String,
    in app: XCUIApplication
  ) -> Bool {
    scrollRosterToTop(in: app)
    for _ in 0..<24 {
      let candidate = goalRow(named: name, in: app)
      if candidate.exists {
        return true
      }
      app.swipeUp(velocity: .slow)
    }
    return false
  }

  @MainActor
  private func performVisibleAccessibilityAudit(in app: XCUIApplication) throws {
    let auditTypes: XCUIAccessibilityAuditType = [
      .contrast,
      .hitRegion,
      .sufficientElementDescription,
      .textClipped,
      .trait,
    ]
    let visibleTop = element("shell.destination.goals", in: app).frame.minY
    let visibleBottom = app.buttons["shell.tab.goals"].frame.minY
    try app.performAccessibilityAudit(for: auditTypes) { issue in
      guard let issueElement = issue.element else {
        return false
      }
      let issueFrame = issueElement.frame.integral
      return issueFrame.minY <= visibleTop || issueFrame.maxY > visibleBottom
    }
  }

  @MainActor
  private func assertWithinUnobscuredRosterViewport(
    _ target: XCUIElement,
    in app: XCUIApplication
  ) {
    XCTAssertTrue(target.exists, "Expected \(target.identifier) in the roster")
    let visibleTop = element("shell.destination.goals", in: app).frame.minY
    let visibleBottom = app.buttons["shell.tab.goals"].frame.minY
    XCTAssertGreaterThanOrEqual(
      target.frame.minY,
      visibleTop,
      "Expected \(target.identifier) below the destination's unobscured top"
    )
    XCTAssertLessThanOrEqual(
      target.frame.maxY,
      visibleBottom,
      "Expected \(target.identifier) above the floating Goals tab"
    )
  }

  @MainActor
  private func assertWithinWindow(_ target: XCUIElement, in app: XCUIApplication) {
    XCTAssertTrue(target.exists, "Expected \(target.identifier) in the presented surface")
    let window = app.windows.firstMatch.frame
    XCTAssertGreaterThanOrEqual(target.frame.minX, window.minX)
    XCTAssertLessThanOrEqual(target.frame.maxX, window.maxX)
    XCTAssertGreaterThanOrEqual(target.frame.minY, window.minY)
    XCTAssertLessThanOrEqual(target.frame.maxY, window.maxY)
  }

  @MainActor
  private func recordScreenshot(_ name: String, of app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  private func assertMinimumHitRegion(of element: XCUIElement) {
    XCTAssertTrue(
      element.waitForExistence(timeout: 2),
      "Expected \(element.identifier.isEmpty ? element.label : element.identifier) for hit-region check"
    )
    let minimum = 44 - 0.01
    XCTAssertGreaterThanOrEqual(
      element.frame.width,
      minimum,
      "Expected \(element.identifier) to be at least 44 points wide"
    )
    XCTAssertGreaterThanOrEqual(
      element.frame.height,
      minimum,
      "Expected \(element.identifier) to be at least 44 points tall"
    )
  }

  @MainActor
  private func goalRow(id: String, in app: XCUIApplication) -> XCUIElement {
    element("goals.row.\(id)", in: app)
  }

  @MainActor
  private func goalRow(named name: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .button).matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND label == %@",
        "goals.row.",
        name
      )
    ).firstMatch
  }

  @MainActor
  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }
}
