import XCTest

final class HabitDetailUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testPersistedOwnerJourneyAcrossDailyWeeklyAndInactiveDetails() {
    let storeName = "HabitDetailUITests-\(UUID().uuidString)"
    let app = launch(storeName: storeName, reset: true, fixture: "habit-detail")
    let habitsTab = app.buttons["shell.tab.habits"]
    XCTAssertTrue(habitsTab.waitForExistence(timeout: 5))
    habitsTab.tap()

    let dailyRow = habitRow(named: "Daily garden", in: app)
    XCTAssertTrue(dailyRow.waitForExistence(timeout: 5))
    dailyRow.tap()

    let title = element("habitDetail.title", in: app)
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    XCTAssertEqual(title.label, "Daily garden")
    XCTAssertFalse(app.buttons["shell.tab.today"].isHittable)
    XCTAssertFalse(app.buttons["shell.tab.habits"].isHittable)

    let metadata = element("habitDetail.metadata", in: app)
    XCTAssertTrue(metadata.label.contains("2 times"))
    XCTAssertTrue(metadata.label.contains("Daily"))
    XCTAssertEqual(element("habitDetail.streak.current", in: app).label, "Current streak, 5 days")
    XCTAssertEqual(element("habitDetail.streak.best", in: app).label, "Best streak, 4 days")

    let currentMonth = element("habitDetail.month", in: app)
    let currentMonthLabel = currentMonth.label
    XCTAssertFalse(currentMonthLabel.isEmpty)
    XCTAssertEqual(element("habitDetail.legend", in: app).label, "Legend. Met, Missed, Open")
    let initialOpenBucket = historyButton(state: "Open", in: app)
    XCTAssertTrue(initialOpenBucket.waitForExistence(timeout: 2))
    XCTAssertTrue(initialOpenBucket.label.contains(", Open,"))
    let currentDateText =
      initialOpenBucket.label.components(separatedBy: ", Open").first ?? ""
    XCTAssertFalse(currentDateText.isEmpty)
    let initialDeleteControl = app.buttons.matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@",
        "habitDetail.entry.delete.",
        currentDateText
      )
    ).firstMatch
    XCTAssertTrue(initialDeleteControl.waitForExistence(timeout: 2))
    XCTAssertTrue(initialDeleteControl.label.hasPrefix("\(currentDateText), "))
    XCTAssertTrue(initialDeleteControl.label.contains(", 1 times, "))
    XCTAssertTrue(initialDeleteControl.isEnabled)
    XCTAssertTrue(initialDeleteControl.label.hasSuffix(", Delete entry"))
    assertMinimumHitRegion(initialDeleteControl)
    let initialDeleteIdentifiers = entryDeleteIdentifiers(in: app)
    XCTAssertEqual(initialDeleteIdentifiers.count, 3)
    recordScreenshot("Daily-current")

    for state in ["Open", "Grace", "Future"] {
      _ = assertHistorySelection(state: state, in: app)
    }

    let finalizedStates = ["Met", "Missed", "Inactive"]
    var verifiedFinalizedStates = Set<String>()
    var finalizedBucketIdentifier = ""
    var finalizedBucketLabel = ""
    var finalizedBucketMonthLabel = ""
    for state in finalizedStates {
      let bucket = historyButton(state: state, in: app)
      guard bucket.exists else { continue }
      let selectedBucket = assertHistorySelection(state: state, in: app)
      verifiedFinalizedStates.insert(state)
      if state == "Met" {
        finalizedBucketIdentifier = selectedBucket.identifier
        finalizedBucketLabel = selectedBucket.label
        finalizedBucketMonthLabel = currentMonth.label
      }
    }

    let previousMonth = element("habitDetail.month.previous", in: app)
    previousMonth.tap()
    XCTAssertNotEqual(currentMonth.label, currentMonthLabel)
    for state in finalizedStates where !verifiedFinalizedStates.contains(state) {
      let bucket = assertHistorySelection(state: state, in: app)
      verifiedFinalizedStates.insert(state)
      if state == "Met" {
        finalizedBucketIdentifier = bucket.identifier
        finalizedBucketLabel = bucket.label
        finalizedBucketMonthLabel = currentMonth.label
      }
    }
    XCTAssertEqual(verifiedFinalizedStates, Set(finalizedStates))
    XCTAssertFalse(finalizedBucketIdentifier.isEmpty)
    XCTAssertTrue(finalizedBucketLabel.contains("Met"))

    while previousMonth.isEnabled {
      let priorLabel = currentMonth.label
      previousMonth.tap()
      XCTAssertNotEqual(currentMonth.label, priorLabel)
    }
    let earliestMonthLabel = currentMonth.label
    previousMonth.tap()
    XCTAssertEqual(currentMonth.label, earliestMonthLabel)

    let beforeCreation = historyButton(state: "Before creation", in: app)
    XCTAssertTrue(beforeCreation.waitForExistence(timeout: 2))
    beforeCreation.tap()
    XCTAssertTrue(beforeCreation.isSelected)
    let historicalCallout = element("habitDetail.history.callout", in: app)
    XCTAssertTrue(historicalCallout.waitForExistence(timeout: 2))
    XCTAssertEqual(historicalCallout.label, beforeCreation.label)
    recordScreenshot("Daily-historical-callout")
    beforeCreation.tap()
    XCTAssertFalse(historicalCallout.waitForExistence(timeout: 1))

    let nextMonth = element("habitDetail.month.next", in: app)
    while nextMonth.isEnabled {
      let priorLabel = currentMonth.label
      nextMonth.tap()
      XCTAssertNotEqual(currentMonth.label, priorLabel)
    }
    let latestMonthLabel = currentMonth.label
    nextMonth.tap()
    XCTAssertEqual(currentMonth.label, latestMonthLabel)
    XCTAssertEqual(latestMonthLabel, currentMonthLabel)

    let graceBucket = historyButton(state: "Grace", in: app)
    XCTAssertTrue(graceBucket.waitForExistence(timeout: 2))
    let graceBucketLabelBeforeDeletion = graceBucket.label
    XCTAssertTrue(graceBucketLabelBeforeDeletion.contains("requirement met"))
    let graceProgressBeforeDeletion =
      graceBucketLabelBeforeDeletion.components(separatedBy: ", ").last
    XCTAssertEqual(graceProgressBeforeDeletion, "2 of 2 times")
    let graceDate = graceBucketLabelBeforeDeletion.components(separatedBy: ",").first ?? ""
    XCTAssertFalse(graceDate.isEmpty)
    let graceDelete = app.buttons.matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@",
        "habitDetail.entry.delete.",
        graceDate
      )
    ).firstMatch
    XCTAssertTrue(graceDelete.waitForExistence(timeout: 2))
    let deletedIdentifier = graceDelete.identifier
    let deletedElement = app.buttons[deletedIdentifier]
    graceDelete.tap()
    XCTAssertTrue(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: deletedElement)
        ],
        timeout: 5
      ) == .completed
    )
    let postDeletionIdentifiers = entryDeleteIdentifiers(in: app)
    XCTAssertEqual(postDeletionIdentifiers.count, initialDeleteIdentifiers.count - 1)
    XCTAssertEqual(
      initialDeleteIdentifiers.subtracting(postDeletionIdentifiers), [deletedIdentifier])
    let graceBucketLabelAfterDeletion = graceBucket.label
    XCTAssertNotEqual(graceBucketLabelAfterDeletion, graceBucketLabelBeforeDeletion)
    XCTAssertTrue(graceBucketLabelAfterDeletion.contains("requirement not met"))
    XCTAssertEqual(
      graceBucketLabelAfterDeletion.components(separatedBy: ", ").last,
      "1 of 2 times"
    )
    XCTAssertEqual(element("habitDetail.risk", in: app).label, "Current streak at risk")
    XCTAssertTrue(element("habitDetail.streak.current", in: app).label.contains("day"))
    recordScreenshot("Recent-entries")

    let metadataBeforeCancel = metadata.label
    element("habitDetail.edit", in: app).tap()
    let unitField = app.textFields["Unit"]
    XCTAssertTrue(unitField.waitForExistence(timeout: 2))
    replaceText(in: unitField, with: "visits")
    app.buttons["Cancel"].tap()
    XCTAssertTrue(title.waitForExistence(timeout: 2))
    XCTAssertEqual(title.label, "Daily garden")
    XCTAssertEqual(metadata.label, metadataBeforeCancel)

    element("habitDetail.edit", in: app).tap()
    let targetField = app.textFields["Target"]
    XCTAssertTrue(targetField.waitForExistence(timeout: 2))
    replaceText(in: targetField, with: "3")
    replaceText(in: app.textFields["Unit"], with: "visits")
    let save = app.buttons["Save"]
    XCTAssertTrue(save.isEnabled)
    save.tap()
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    XCTAssertEqual(title.label, "Daily garden")
    XCTAssertTrue(metadata.label.contains("3 visits"))

    if currentMonth.label != finalizedBucketMonthLabel {
      previousMonth.tap()
    }
    let persistedFinalBucket = element(finalizedBucketIdentifier, in: app)
    XCTAssertTrue(persistedFinalBucket.waitForExistence(timeout: 2))
    XCTAssertEqual(persistedFinalBucket.label, finalizedBucketLabel)
    if currentMonth.label != currentMonthLabel {
      nextMonth.tap()
    }
    let updatedGraceBucket = historyButton(state: "Grace", in: app)
    let updatedCurrentBucket = historyButton(state: "Open", in: app)
    XCTAssertTrue(updatedGraceBucket.label.contains("1 of 3 visits"))
    XCTAssertTrue(updatedCurrentBucket.label.contains("1 of 3 visits"))
    recordScreenshot("Edit-return")

    element("habitDetail.archive", in: app).tap()
    let reactivate = element("habitDetail.reactivate", in: app)
    XCTAssertTrue(reactivate.waitForExistence(timeout: 5))
    XCTAssertTrue(element("habitDetail.streak.current", in: app).label.contains("day"))
    XCTAssertTrue(element("habitDetail.streak.best", in: app).label.contains("day"))
    XCTAssertTrue(historyButton(state: "Inactive", in: app).waitForExistence(timeout: 2))
    XCTAssertTrue(element("habitDetail.entries.empty", in: app).waitForExistence(timeout: 2))
    XCTAssertTrue(entryDeleteIdentifiers(in: app).isEmpty)
    recordScreenshot("inactive-after-archive")

    reactivate.tap()
    XCTAssertTrue(element("habitDetail.archive", in: app).waitForExistence(timeout: 5))
    let reopenedCurrentBucket = historyButton(state: "Open", in: app)
    XCTAssertTrue(reopenedCurrentBucket.waitForExistence(timeout: 2))
    XCTAssertTrue(reopenedCurrentBucket.label.contains("requirement not met"))
    XCTAssertTrue(reopenedCurrentBucket.label.contains("3 visits"))
    let reactivatedCurrentBucketLabel = reopenedCurrentBucket.label
    let reactivatedHistoryLabels = historyLabels(in: app)
    XCTAssertEqual(currentMonth.label, currentMonthLabel)
    let reactivatedRecentEntryCount = entryDeleteElementCount(in: app)
    let reactivatedRecentEntryLabels = entryDeleteLabels(in: app)
    XCTAssertEqual(reactivatedRecentEntryCount, 1)
    XCTAssertEqual(reactivatedRecentEntryLabels.count, reactivatedRecentEntryCount)

    element("habitDetail.back", in: app).tap()
    XCTAssertTrue(element("shell.destination.habits", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(habitsTab.isSelected)
    XCTAssertTrue(habitsTab.isHittable)
    let reopenedDailyRow = habitRow(named: "Daily garden", in: app)
    XCTAssertTrue(reopenedDailyRow.waitForExistence(timeout: 5))
    reopenedDailyRow.press(forDuration: 1)
    XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.buttons["Archive"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 2))
    XCTAssertFalse(title.exists)
    app.tap()

    let weeklyRow = habitRow(named: "Weekly field notes", in: app)
    XCTAssertTrue(weeklyRow.waitForExistence(timeout: 5))
    weeklyRow.tap()
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    XCTAssertEqual(title.label, "Weekly field notes")
    XCTAssertTrue(metadata.label.contains("Weekly"))
    XCTAssertTrue(element("habitDetail.streak.current", in: app).label.contains("week"))
    XCTAssertTrue(element("habitDetail.streak.best", in: app).label.contains("week"))

    let weeklyStrips = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "habitDetail.history.")
    ).allElementsBoundByIndex
    XCTAssertGreaterThan(weeklyStrips.count, 1)
    for strip in weeklyStrips {
      assertMinimumHitRegion(strip)
      XCTAssertGreaterThan(strip.frame.width, 88)
    }
    var boundaryStrip = crossMonthWeeklyStrip(in: app)
    if boundaryStrip == nil {
      let weeklyMonth = element("habitDetail.month", in: app)
      let weeklyCurrentMonthLabel = weeklyMonth.label
      let weeklyPreviousMonth = element("habitDetail.month.previous", in: app)
      XCTAssertTrue(weeklyPreviousMonth.isEnabled)
      weeklyPreviousMonth.tap()
      XCTAssertNotEqual(weeklyMonth.label, weeklyCurrentMonthLabel)
      boundaryStrip = crossMonthWeeklyStrip(in: app)
    }
    guard let boundaryStrip else {
      XCTFail("A displayed weekly page must contain a cross-month period")
      return
    }
    XCTAssertTrue(isCrossMonthWeeklyIdentifier(boundaryStrip.identifier))
    let boundaryOwnerLabel = boundaryStrip.label
    XCTAssertFalse(boundaryOwnerLabel.isEmpty)
    boundaryStrip.tap()
    XCTAssertTrue(boundaryStrip.isSelected)
    XCTAssertEqual(element("habitDetail.history.callout", in: app).label, boundaryOwnerLabel)
    recordScreenshot("Weekly-strips")

    element("habitDetail.back", in: app).tap()
    let inactiveRow = habitRow(named: "Dormant reading", in: app)
    XCTAssertTrue(inactiveRow.waitForExistence(timeout: 5))
    inactiveRow.tap()
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    XCTAssertEqual(title.label, "Dormant reading")
    XCTAssertTrue(element("habitDetail.reactivate", in: app).waitForExistence(timeout: 2))
    XCTAssertTrue(element("habitDetail.streak.current", in: app).label.contains("day"))
    XCTAssertTrue(element("habitDetail.streak.best", in: app).label.contains("day"))
    XCTAssertTrue(historyButton(state: "Inactive", in: app).waitForExistence(timeout: 2))
    XCTAssertTrue(element("habitDetail.entries.empty", in: app).waitForExistence(timeout: 2))
    recordScreenshot("Inactive-detail")

    app.terminate()
    app.launchArguments = launchArguments(storeName: storeName, reset: false, fixture: nil)
    app.launch()
    let relaunchedHabitsTab = app.buttons["shell.tab.habits"]
    XCTAssertTrue(relaunchedHabitsTab.waitForExistence(timeout: 5))
    relaunchedHabitsTab.tap()
    habitRow(named: "Daily garden", in: app).tap()
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    XCTAssertEqual(title.label, "Daily garden")
    XCTAssertTrue(metadata.label.contains("3 visits"))
    XCTAssertEqual(element("habitDetail.month", in: app).label, currentMonthLabel)
    XCTAssertFalse(entryDeleteIdentifiers(in: app).contains(deletedIdentifier))
    XCTAssertEqual(entryDeleteElementCount(in: app), reactivatedRecentEntryCount)
    XCTAssertEqual(entryDeleteLabels(in: app), reactivatedRecentEntryLabels)
    let relaunchedCurrentBucket = historyButton(state: "Open", in: app)
    XCTAssertTrue(relaunchedCurrentBucket.waitForExistence(timeout: 2))
    XCTAssertEqual(relaunchedCurrentBucket.label, reactivatedCurrentBucketLabel)
    XCTAssertEqual(historyLabels(in: app), reactivatedHistoryLabels)
    if currentMonth.label != finalizedBucketMonthLabel {
      previousMonth.tap()
    }
    XCTAssertEqual(element(finalizedBucketIdentifier, in: app).label, finalizedBucketLabel)
    if currentMonth.label != currentMonthLabel {
      nextMonth.tap()
    }
    XCTAssertTrue(element("habitDetail.archive", in: app).exists)
    element("habitDetail.back", in: app).tap()
    XCTAssertTrue(element("shell.destination.habits", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(relaunchedHabitsTab.isSelected)
  }

  @MainActor
  func testAdaptiveDetailAccessibilityAndPersistentRelaunches() throws {
    let storeName = "HabitDetailAdaptiveUITests-\(UUID().uuidString)"
    let app = launch(storeName: storeName, reset: true, fixture: "habit-detail")
    openDailyDetail(in: app)

    let auditTypes: XCUIAccessibilityAuditType = [
      .contrast,
      .hitRegion,
      .sufficientElementDescription,
      .textClipped,
      .trait,
    ]
    // Element detection is intentionally omitted because this detail is a scroll surface with
    // intentionally offscreen content. Every actionable element is asserted directly below.
    let title = element("habitDetail.title", in: app)
    let metadata = element("habitDetail.metadata", in: app)
    XCTAssertEqual(title.label, "Daily garden")
    XCTAssertTrue(metadata.label.contains("2 times"))
    XCTAssertTrue(metadata.label.contains("Daily"))
    assertDetailHidesTabPill(in: app)

    let back = element("habitDetail.back", in: app)
    let edit = element("habitDetail.edit", in: app)
    let previousMonth = element("habitDetail.month.previous", in: app)
    let nextMonth = element("habitDetail.month.next", in: app)
    let initialAdaptiveMonthLabel = element("habitDetail.month", in: app).label
    XCTAssertFalse(initialAdaptiveMonthLabel.isEmpty)
    for control in [back, edit, previousMonth, nextMonth] {
      XCTAssertTrue(control.waitForExistence(timeout: 2))
      assertMinimumHitRegion(control)
    }
    XCTAssertEqual(back.label, "Back")
    XCTAssertEqual(edit.label, "Edit")
    XCTAssertEqual(previousMonth.label, "Previous month")
    XCTAssertEqual(nextMonth.label, "Next month")
    XCTAssertEqual(previousMonth.value as? String, initialAdaptiveMonthLabel)
    XCTAssertEqual(nextMonth.value as? String, initialAdaptiveMonthLabel)
    try app.performAccessibilityAudit(for: auditTypes)

    let historyButtons = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "habitDetail.history.")
    ).allElementsBoundByIndex
    XCTAssertGreaterThan(historyButtons.count, 0)
    let observableStates = [
      "Met", "Missed", "Open", "Grace", "Inactive", "Before creation", "Future",
    ]
    for bucket in historyButtons {
      scrollToHittable(bucket, in: app, swipingUp: true)
      assertMinimumHitRegion(bucket)
      XCTAssertTrue(
        observableStates.contains { bucket.label.components(separatedBy: ", ").contains($0) },
        "Unexpected history accessibility label: \(bucket.label)"
      )
    }

    let deleteControls = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "habitDetail.entry.delete.")
    ).allElementsBoundByIndex
    XCTAssertEqual(deleteControls.count, 3)
    for deleteControl in deleteControls {
      scrollToHittable(deleteControl, in: app, swipingUp: true)
      assertMinimumHitRegion(deleteControl)
      XCTAssertTrue(deleteControl.isEnabled)
      XCTAssertTrue(deleteControl.label.hasSuffix(", Delete entry"))
    }
    assertRetryTargetsWhenPresent(in: app)

    let archive = element("habitDetail.archive", in: app)
    scrollToHittable(archive, in: app, swipingUp: true)
    assertMinimumHitRegion(archive)
    XCTAssertEqual(archive.label, "Archive habit")
    try app.performAccessibilityAudit(for: auditTypes)

    scrollToHittable(title, in: app, swipingUp: false)
    edit.tap()
    let unitField = app.textFields["Unit"]
    XCTAssertTrue(unitField.waitForExistence(timeout: 2))
    replaceText(in: unitField, with: "discarded sessions")
    app.buttons["Cancel"].tap()
    XCTAssertTrue(title.waitForExistence(timeout: 2))
    XCTAssertEqual(title.label, "Daily garden")
    XCTAssertTrue(metadata.label.contains("2 times"))

    edit.tap()
    let nameField = app.textFields["Habit name"]
    XCTAssertTrue(nameField.waitForExistence(timeout: 2))
    replaceText(in: nameField, with: "Daily garden tending and reflection practice")
    replaceText(in: app.textFields["Unit"], with: "mindful practice sessions")
    let save = app.buttons["Save"]
    XCTAssertTrue(save.isEnabled)
    save.tap()
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    XCTAssertEqual(title.label, "Daily garden tending and reflection practice")
    XCTAssertTrue(metadata.label.contains("2 mindful practice sessions"))

    let accessibilitySizes = [
      (
        category: "UICTContentSizeCategoryAccessibilityL",
        screenshot: "Daily-accessibility-large"
      ),
      (
        category: "UICTContentSizeCategoryAccessibilityXL",
        screenshot: "Daily-accessibility-extra-large"
      ),
    ]
    for size in accessibilitySizes {
      relaunch(
        app,
        storeName: storeName,
        additionalArguments: [
          "-UIPreferredContentSizeCategoryName",
          size.category,
        ]
      )
      openDailyDetail(named: "Daily garden tending and reflection practice", in: app)

      let adaptiveTitle = element("habitDetail.title", in: app)
      let adaptiveMetadata = element("habitDetail.metadata", in: app)
      XCTAssertEqual(adaptiveTitle.label, "Daily garden tending and reflection practice")
      XCTAssertTrue(adaptiveMetadata.label.contains("2 mindful practice sessions"))
      XCTAssertTrue(adaptiveMetadata.label.contains("Daily"))
      XCTAssertGreaterThan(adaptiveTitle.frame.height, 60)
      XCTAssertGreaterThan(adaptiveMetadata.frame.height, 40)
      assertDetailHidesTabPill(in: app)

      let adaptiveBack = element("habitDetail.back", in: app)
      let adaptiveEdit = element("habitDetail.edit", in: app)
      let adaptivePreviousMonth = element("habitDetail.month.previous", in: app)
      let adaptiveNextMonth = element("habitDetail.month.next", in: app)
      let adaptiveMonthLabel = element("habitDetail.month", in: app).label
      XCTAssertFalse(adaptiveMonthLabel.isEmpty)
      for control in [
        adaptiveBack, adaptiveEdit, adaptivePreviousMonth, adaptiveNextMonth,
      ] {
        XCTAssertTrue(control.waitForExistence(timeout: 2))
        assertMinimumHitRegion(control)
      }
      XCTAssertEqual(adaptivePreviousMonth.label, "Previous month")
      XCTAssertEqual(adaptiveNextMonth.label, "Next month")
      XCTAssertEqual(adaptivePreviousMonth.value as? String, adaptiveMonthLabel)
      XCTAssertEqual(adaptiveNextMonth.value as? String, adaptiveMonthLabel)
      try app.performAccessibilityAudit(for: auditTypes)

      let adaptiveDeleteControls = app.buttons.matching(
        NSPredicate(format: "identifier BEGINSWITH %@", "habitDetail.entry.delete.")
      ).allElementsBoundByIndex
      XCTAssertEqual(adaptiveDeleteControls.count, 3)
      for deleteControl in adaptiveDeleteControls {
        scrollToHittable(deleteControl, in: app, swipingUp: true)
        assertMinimumHitRegion(deleteControl)
        XCTAssertTrue(deleteControl.label.hasSuffix(", Delete entry"))
      }

      let adaptiveArchive = element("habitDetail.archive", in: app)
      scrollToHittable(adaptiveArchive, in: app, swipingUp: true)
      assertMinimumHitRegion(adaptiveArchive)
      XCTAssertEqual(adaptiveArchive.label, "Archive habit")
      XCTAssertTrue(adaptiveArchive.isHittable)
      assertRetryTargetsWhenPresent(in: app)

      scrollToHittable(adaptiveTitle, in: app, swipingUp: false)
      XCTAssertTrue(adaptiveTitle.isHittable)
      XCTAssertTrue(adaptiveMetadata.isHittable)
      recordScreenshot(size.screenshot)
    }

    relaunch(app, storeName: storeName, additionalArguments: [])
    openDailyDetail(named: "Daily garden tending and reflection practice", in: app)
    let restoredTitle = element("habitDetail.title", in: app)
    element("habitDetail.edit", in: app).tap()
    replaceText(in: app.textFields["Habit name"], with: "Daily garden")
    replaceText(in: app.textFields["Unit"], with: "times")
    XCTAssertTrue(app.buttons["Save"].isEnabled)
    app.buttons["Save"].tap()
    XCTAssertTrue(restoredTitle.waitForExistence(timeout: 5))
    XCTAssertEqual(restoredTitle.label, "Daily garden")
    XCTAssertTrue(element("habitDetail.metadata", in: app).label.contains("2 times"))

    let currentMonth = element("habitDetail.month", in: app)
    let originalMonthLabel = currentMonth.label
    let finalPreviousMonth = element("habitDetail.month.previous", in: app)
    finalPreviousMonth.tap()
    XCTAssertNotEqual(currentMonth.label, originalMonthLabel)
    let selectedBucket = historyButton(state: "Met", in: app)
    XCTAssertTrue(selectedBucket.waitForExistence(timeout: 2))
    selectedBucket.tap()
    let callout = element("habitDetail.history.callout", in: app)
    XCTAssertTrue(callout.waitForExistence(timeout: 2))
    XCTAssertEqual(callout.label, selectedBucket.label)
    selectedBucket.tap()
    XCTAssertFalse(callout.waitForExistence(timeout: 1))
    element("habitDetail.month.next", in: app).tap()
    XCTAssertEqual(currentMonth.label, originalMonthLabel)

    let finalDeleteControls = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "habitDetail.entry.delete.")
    ).allElementsBoundByIndex
    XCTAssertEqual(finalDeleteControls.count, 3)
    let deletedControl = finalDeleteControls[0]
    scrollToHittable(deletedControl, in: app, swipingUp: true)
    let deletedIdentifier = deletedControl.identifier
    deletedControl.tap()
    XCTAssertTrue(
      XCTWaiter.wait(
        for: [
          XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.buttons[deletedIdentifier]
          )
        ],
        timeout: 5
      ) == .completed
    )
    XCTAssertEqual(entryDeleteElementCount(in: app), 2)

    let finalArchive = element("habitDetail.archive", in: app)
    scrollToHittable(finalArchive, in: app, swipingUp: true)
    finalArchive.tap()
    let reactivate = element("habitDetail.reactivate", in: app)
    XCTAssertTrue(reactivate.waitForExistence(timeout: 5))
    assertMinimumHitRegion(reactivate)
    XCTAssertEqual(reactivate.label, "Reactivate habit")
    reactivate.tap()
    XCTAssertTrue(finalArchive.waitForExistence(timeout: 5))

    scrollToHittable(restoredTitle, in: app, swipingUp: false)
    element("habitDetail.back", in: app).tap()
    XCTAssertTrue(element("shell.destination.habits", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["shell.tab.habits"].isHittable)
    let dailyRow = habitRow(named: "Daily garden", in: app)
    XCTAssertTrue(dailyRow.waitForExistence(timeout: 2))
    dailyRow.tap()
    XCTAssertTrue(restoredTitle.waitForExistence(timeout: 5))
    XCTAssertEqual(restoredTitle.label, "Daily garden")
    assertDetailHidesTabPill(in: app)
  }

  @MainActor
  private func openDailyDetail(named name: String = "Daily garden", in app: XCUIApplication) {
    let habitsTab = app.buttons["shell.tab.habits"]
    XCTAssertTrue(habitsTab.waitForExistence(timeout: 5))
    habitsTab.tap()
    let dailyRow = habitRow(named: name, in: app)
    XCTAssertTrue(dailyRow.waitForExistence(timeout: 5))
    dailyRow.tap()
    XCTAssertTrue(element("habitDetail.title", in: app).waitForExistence(timeout: 5))
  }

  @MainActor
  private func relaunch(
    _ app: XCUIApplication,
    storeName: String,
    additionalArguments: [String]
  ) {
    app.terminate()
    app.launchArguments =
      launchArguments(storeName: storeName, reset: false, fixture: nil)
      + additionalArguments
    app.launch()
  }

  @MainActor
  private func assertDetailHidesTabPill(
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertFalse(app.buttons["shell.tab.today"].isHittable, file: file, line: line)
    XCTAssertFalse(app.buttons["shell.tab.habits"].isHittable, file: file, line: line)
  }

  @MainActor
  private func assertRetryTargetsWhenPresent(
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let retryButtons = app.buttons.matching(NSPredicate(format: "label == %@", "Try again"))
    for retry in retryButtons.allElementsBoundByIndex where retry.exists {
      assertMinimumHitRegion(retry, file: file, line: line)
      XCTAssertTrue(retry.isEnabled, file: file, line: line)
    }
  }

  @MainActor
  private func scrollToHittable(
    _ element: XCUIElement,
    in app: XCUIApplication,
    swipingUp: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertTrue(element.waitForExistence(timeout: 2), file: file, line: line)
    var remainingSwipes = 12
    while !element.isHittable, remainingSwipes > 0 {
      if swipingUp {
        app.swipeUp()
      } else {
        app.swipeDown()
      }
      remainingSwipes -= 1
    }
    XCTAssertTrue(element.isHittable, "\(element) did not become hittable", file: file, line: line)
  }
  @MainActor
  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
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
  private func historyButton(state: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
        "habitDetail.history.",
        state
      )
    ).firstMatch
  }

  @MainActor
  private func assertHistorySelection(
    state: String,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> XCUIElement {
    let bucket = historyButton(state: state, in: app)
    XCTAssertTrue(bucket.waitForExistence(timeout: 2), file: file, line: line)
    XCTAssertTrue(bucket.label.contains(state), file: file, line: line)
    bucket.tap()
    XCTAssertTrue(bucket.isSelected, file: file, line: line)
    let callout = element("habitDetail.history.callout", in: app)
    XCTAssertTrue(callout.waitForExistence(timeout: 2), file: file, line: line)
    XCTAssertEqual(callout.label, bucket.label, file: file, line: line)
    bucket.tap()
    XCTAssertFalse(callout.waitForExistence(timeout: 1), file: file, line: line)
    return bucket
  }

  @MainActor
  private func assertMinimumHitRegion(
    _ element: XCUIElement,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let frame = element.frame
    XCTAssertGreaterThanOrEqual(frame.width, 44, file: file, line: line)
    XCTAssertGreaterThanOrEqual(frame.height, 44, file: file, line: line)
  }

  @MainActor
  private func replaceText(in field: XCUIElement, with replacement: String) {
    field.tap()
    field.tap(withNumberOfTaps: 3, numberOfTouches: 1)
    field.typeText(
      replacement.isEmpty
        ? XCUIKeyboardKey.delete.rawValue
        : replacement
    )
  }

  @MainActor
  private func recordScreenshot(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  private func entryDeleteIdentifiers(in app: XCUIApplication) -> Set<String> {
    Set(
      app.buttons.matching(
        NSPredicate(format: "identifier BEGINSWITH %@", "habitDetail.entry.delete.")
      ).allElementsBoundByIndex.map(\.identifier)
    )
  }

  @MainActor
  private func entryDeleteElementCount(in app: XCUIApplication) -> Int {
    app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "habitDetail.entry.delete.")
    ).count
  }

  @MainActor
  private func entryDeleteLabels(in app: XCUIApplication) -> [String] {
    app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "habitDetail.entry.delete.")
    ).allElementsBoundByIndex.map(\.label).sorted()
  }

  @MainActor
  private func historyLabels(in app: XCUIApplication) -> [String: String] {
    Dictionary(
      uniqueKeysWithValues: app.buttons.matching(
        NSPredicate(format: "identifier BEGINSWITH %@", "habitDetail.history.")
      ).allElementsBoundByIndex.map { ($0.identifier, $0.label) }
    )
  }

  @MainActor
  private func launch(
    storeName: String,
    reset: Bool,
    fixture: String?
  ) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["TZ"] = "America/Los_Angeles"
    app.launchArguments = launchArguments(storeName: storeName, reset: reset, fixture: fixture)
    app.terminate()
    app.launch()
    return app
  }

  @MainActor
  private func crossMonthWeeklyStrip(in app: XCUIApplication) -> XCUIElement? {
    app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "habitDetail.history.week:")
    ).allElementsBoundByIndex.first {
      isCrossMonthWeeklyIdentifier($0.identifier)
    }
  }

  private func isCrossMonthWeeklyIdentifier(_ identifier: String) -> Bool {
    let prefix = "habitDetail.history.week:"
    guard identifier.hasPrefix(prefix) else { return false }
    let components = identifier.dropFirst(prefix.count).split(separator: "-")
    guard
      components.count == 3,
      let year = Int(components[0]),
      let month = Int(components[1]),
      let day = Int(components[2])
    else {
      return false
    }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let startComponents = DateComponents(
      timeZone: calendar.timeZone,
      year: year,
      month: month,
      day: day
    )
    guard
      let start = calendar.date(from: startComponents),
      let inclusiveEnd = calendar.date(byAdding: .day, value: 6, to: start)
    else {
      return false
    }
    return calendar.dateComponents([.year, .month], from: start)
      != calendar.dateComponents([.year, .month], from: inclusiveEnd)
  }

  private func launchArguments(
    storeName: String,
    reset: Bool,
    fixture: String?
  ) -> [String] {
    var arguments = [
      "-tend-ui-testing",
      "-tend-ui-test-store",
      storeName,
    ]
    if reset {
      arguments.append("-tend-ui-test-reset")
    }
    if let fixture {
      arguments += ["-tend-ui-test-fixture", fixture]
    }
    return arguments
  }
}
