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
    XCTAssertEqual(currentMonth.label, expectedCurrentMonthLabel())
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

    let previousMonth = element("habitDetail.month.previous", in: app)
    let currentMonthLabel = currentMonth.label
    previousMonth.tap()
    XCTAssertNotEqual(currentMonth.label, currentMonthLabel)

    var finalizedBucketIdentifier = ""
    var finalizedBucketLabel = ""
    for state in ["Met", "Missed", "Inactive"] {
      let bucket = assertHistorySelection(state: state, in: app)
      if state == "Met" {
        finalizedBucketIdentifier = bucket.identifier
        finalizedBucketLabel = bucket.label
      }
    }
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
        for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: deletedElement)],
        timeout: 5
      ) == .completed
    )
    let postDeletionIdentifiers = entryDeleteIdentifiers(in: app)
    XCTAssertEqual(postDeletionIdentifiers.count, initialDeleteIdentifiers.count - 1)
    XCTAssertEqual(initialDeleteIdentifiers.subtracting(postDeletionIdentifiers), [deletedIdentifier])
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

    previousMonth.tap()
    let persistedFinalBucket = element(finalizedBucketIdentifier, in: app)
    XCTAssertTrue(persistedFinalBucket.waitForExistence(timeout: 2))
    XCTAssertEqual(persistedFinalBucket.label, finalizedBucketLabel)
    nextMonth.tap()
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
    let reactivatedRecentEntryLabels = entryDeleteLabels(in: app)
    XCTAssertEqual(reactivatedRecentEntryLabels.count, 1)

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
    let expectedBoundaryRange = expectedCrossMonthWeekRange()
    let boundaryStrip = app.buttons.matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@",
        "habitDetail.history.",
        expectedBoundaryRange
      )
    ).firstMatch
    XCTAssertTrue(boundaryStrip.waitForExistence(timeout: 2))
    XCTAssertTrue(boundaryStrip.label.hasPrefix("\(expectedBoundaryRange), "))
    boundaryStrip.tap()
    XCTAssertTrue(boundaryStrip.isSelected)
    XCTAssertEqual(element("habitDetail.history.callout", in: app).label, boundaryStrip.label)
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
    XCTAssertFalse(entryDeleteIdentifiers(in: app).contains(deletedIdentifier))
    XCTAssertEqual(entryDeleteLabels(in: app), reactivatedRecentEntryLabels)
    let relaunchedCurrentBucket = historyButton(state: "Open", in: app)
    XCTAssertTrue(relaunchedCurrentBucket.waitForExistence(timeout: 2))
    XCTAssertEqual(relaunchedCurrentBucket.label, reactivatedCurrentBucketLabel)
    XCTAssertEqual(historyLabels(in: app), reactivatedHistoryLabels)
    previousMonth.tap()
    XCTAssertEqual(element(finalizedBucketIdentifier, in: app).label, finalizedBucketLabel)
    nextMonth.tap()
    XCTAssertTrue(element("habitDetail.archive", in: app).exists)
    element("habitDetail.back", in: app).tap()
    XCTAssertTrue(element("shell.destination.habits", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(relaunchedHabitsTab.isSelected)
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
    if let existing = field.value as? String {
      field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
    }
    field.typeText(replacement)
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
  private func entryDeleteLabels(in app: XCUIApplication) -> Set<String> {
    Set(
      app.buttons.matching(
        NSPredicate(format: "identifier BEGINSWITH %@", "habitDetail.entry.delete.")
      ).allElementsBoundByIndex.map(\.label)
    )
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

  private func expectedCurrentMonthLabel() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
    formatter.dateFormat = "MMMM yyyy"
    return formatter.string(from: Date())
  }

  private func expectedCrossMonthWeekRange() -> String {
    let timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let locale = Locale(identifier: "en_US")
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = locale
    calendar.timeZone = timeZone
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4

    let currentMonthComponents = calendar.dateComponents([.year, .month], from: Date())
    let monthStart = calendar.date(from: currentMonthComponents)!
    let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart)!
    let firstWeek = calendar.dateInterval(of: .weekOfYear, for: monthStart)!
    let currentMonth = calendar.component(.month, from: monthStart)
    let boundaryWeek: DateInterval
    if calendar.component(.month, from: firstWeek.start) != currentMonth {
      boundaryWeek = firstWeek
    } else {
      let monthEnd = calendar.date(byAdding: .day, value: -1, to: nextMonthStart)!
      boundaryWeek = calendar.dateInterval(of: .weekOfYear, for: monthEnd)!
    }
    let inclusiveEnd = calendar.date(byAdding: .day, value: -1, to: boundaryWeek.end)!

    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.calendar = calendar
    formatter.timeZone = timeZone
    formatter.setLocalizedDateFormatFromTemplate("MMM d yyyy")
    return "\(formatter.string(from: boundaryWeek.start)) – \(formatter.string(from: inclusiveEnd))"
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
