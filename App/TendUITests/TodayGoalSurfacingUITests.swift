import UIKit
import XCTest

final class TodayGoalSurfacingUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  private let fixtureInstantArgument = "2026-08-05T19:00:00Z"

  private let mixedBehindID = "71abcdef-0000-0000-0000-000000000001"
  private let mixedNearID = "71000000-0000-0000-0000-000000000002"
  private let mixedPastDueID = "71000000-0000-0000-0000-000000000003"
  private let mixedDistantID = "71000000-0000-0000-0000-000000000004"
  private let mixedNoDeadlineID = "71000000-0000-0000-0000-000000000005"
  private let mixedHarvestedID = "71000000-0000-0000-0000-000000000006"
  private let mixedLetGoID = "71000000-0000-0000-0000-000000000007"
  private let journeyID = "71abcdef-0000-0000-0000-000000000501"

  @MainActor
  func testMixedGoalsFollowHabitSectionsInUrgencyOrderWithoutChangingHabitFraction() {
    let app = launch(fixture: "today-goals-mixed")

    XCTAssertTrue(app.otherElements["today.dashboard"].waitForExistence(timeout: 5))
    XCTAssertEqual(element("today.summary", in: app).label, "2 of 5")
    XCTAssertTrue(element("today.section.to-tend", in: app).exists)
    XCTAssertTrue(element("today.section.tended", in: app).exists)

    let goals = element("today.section.goals", in: app)
    XCTAssertTrue(goals.exists, "Expected the GOALS section after the habit groups")
    XCTAssertEqual(goals.label, "GOALS")
    XCTAssertGreaterThan(
      goals.frame.minY,
      element("today.row.Water seedlings", in: app).frame.maxY
    )

    let orderedRows = [
      goalRow(mixedPastDueID, in: app),
      goalRow(mixedBehindID, in: app),
      goalRow(mixedNearID, in: app),
    ]
    for row in orderedRows {
      XCTAssertTrue(row.exists)
      assertInformationalGoalRow(row, in: app)
    }
    for pair in zip(orderedRows, orderedRows.dropFirst()) {
      XCTAssertLessThan(pair.0.frame.minY, pair.1.frame.minY)
    }
    XCTAssertEqual(
      orderedRows.map(\.label),
      ["Past-due grant goal", "Behind practice goal", "Near on-pace measure"]
    )

    XCTAssertEqual(
      orderedRows[0].value as? String,
      "7 of 10 sections, Due Aug 4, 2026, Past due"
    )
    XCTAssertEqual(
      orderedRows[1].value as? String,
      "2 of 10 sessions, Due Aug 12, 2026, Behind"
    )
    XCTAssertEqual(
      orderedRows[2].value as? String,
      "160 pages now · 60 of 100 pages, Due Aug 9, 2026, On pace"
    )

    for absentID in [
      mixedDistantID,
      mixedNoDeadlineID,
      mixedHarvestedID,
      mixedLetGoID,
    ] {
      XCTAssertFalse(goalRow(absentID, in: app).exists)
    }
    for absentName in [
      "Distant on-pace goal",
      "No-deadline goal",
      "Harvested goal",
      "Let-go goal",
    ] {
      XCTAssertFalse(app.staticTexts[absentName].exists)
    }
    scrollToVisible(orderedRows[0], in: app)

    recordScreenshot("Today-goals-mixed", of: app)
  }

  @MainActor
  func testAllTendedHabitsKeepTheirFractionAndYieldCelebrationToEligibleGoal() {
    let app = launch(fixture: "today-goals-all-tended")

    XCTAssertTrue(app.otherElements["today.dashboard"].waitForExistence(timeout: 5))
    XCTAssertEqual(element("today.summary", in: app).label, "2 of 2")
    XCTAssertFalse(element("today.section.to-tend", in: app).exists)
    XCTAssertTrue(element("today.section.tended", in: app).exists)
    XCTAssertFalse(element("today.all-tended", in: app).exists)

    let goals = element("today.section.goals", in: app)
    let row = goalRow("71000000-0000-0000-0000-000000000101", in: app)
    XCTAssertTrue(goals.exists)
    XCTAssertTrue(row.exists)
    XCTAssertGreaterThan(goals.frame.minY, element("today.row.Weekly review", in: app).frame.maxY)
    XCTAssertEqual(row.value as? String, "1 of 8 chapters, Due Aug 12, 2026, Behind")
    assertInformationalGoalRow(row, in: app)
  }

  @MainActor
  func testFirstLaunchBodyComposesAboveEligibleGoal() {
    let app = launch(fixture: "today-goals-first-launch")

    XCTAssertTrue(app.otherElements["today.empty"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.staticTexts["Tend is a quiet place to grow the habits you want to keep."].exists
    )
    XCTAssertTrue(app.buttons["today.plant-habit"].exists)
    XCTAssertFalse(element("today.summary", in: app).exists)
    XCTAssertFalse(element("today.section.to-tend", in: app).exists)
    XCTAssertFalse(element("today.section.tended", in: app).exists)
    XCTAssertTrue(element("today.section.goals", in: app).exists)

    let row = goalRow("71000000-0000-0000-0000-000000000201", in: app)
    XCTAssertTrue(row.exists)
    XCTAssertGreaterThan(row.frame.minY, app.buttons["today.plant-habit"].frame.maxY)
    XCTAssertEqual(row.value as? String, "1 of 6 drafts, Due Aug 12, 2026, Behind")
    assertInformationalGoalRow(row, in: app)
  }

  @MainActor
  func testInactiveHabitBodyComposesAboveEligibleGoal() {
    let app = launch(fixture: "today-goals-inactive")

    XCTAssertTrue(app.otherElements["today.inactive"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["No active habits."].exists)
    XCTAssertFalse(element("today.summary", in: app).exists)
    XCTAssertFalse(element("today.section.to-tend", in: app).exists)
    XCTAssertFalse(element("today.section.tended", in: app).exists)
    XCTAssertTrue(element("today.section.goals", in: app).exists)

    let row = goalRow("71000000-0000-0000-0000-000000000301", in: app)
    XCTAssertTrue(row.exists)
    XCTAssertGreaterThan(row.frame.minY, app.staticTexts["No active habits."].frame.maxY)
    XCTAssertEqual(row.value as? String, "2 of 9 visits, Due Aug 12, 2026, Behind")
    assertInformationalGoalRow(row, in: app)
  }

  @MainActor
  func testUnavailableGoalIsIsolatedAndRetryIsTheOnlyGoalControl() {
    let app = launch(fixture: "today-goals-failure")

    XCTAssertTrue(app.otherElements["today.dashboard"].waitForExistence(timeout: 5))
    XCTAssertTrue(element("today.section.goals", in: app).exists)

    let malformedID = "71abcdef-0000-0000-0000-000000000401"
    let pastDueID = "71000000-0000-0000-0000-000000000402"
    let nearID = "71000000-0000-0000-0000-000000000403"
    let malformed = goalRow(malformedID, in: app)
    let pastDue = goalRow(pastDueID, in: app)
    let near = goalRow(nearID, in: app)
    XCTAssertTrue(malformed.exists)
    XCTAssertTrue(pastDue.exists)
    XCTAssertTrue(near.exists)
    XCTAssertLessThan(malformed.frame.minY, pastDue.frame.minY)
    XCTAssertLessThan(pastDue.frame.minY, near.frame.minY)
    XCTAssertEqual(
      malformed.value as? String,
      "Progress unavailable, Deadline unavailable, Standing unavailable, Goal facts unavailable., Try again"
    )
    XCTAssertEqual(pastDue.value as? String, "3 of 5 reports, Due Aug 4, 2026, Past due")
    XCTAssertEqual(
      near.value as? String,
      "8 of 10 reviews, Due Aug 9, 2026, On pace"
    )
    scrollToVisible(malformed, in: app)

    assertInformationalGoalRow(pastDue, in: app)
    assertInformationalGoalRow(near, in: app)
    XCTAssertNotEqual(malformed.elementType, .button)
    XCTAssertFalse(app.buttons["today.goal.\(malformedID)"].exists)

    let retryID = "today.goal.retry.\(malformedID)"
    let retry = app.buttons[retryID]
    XCTAssertEqual(app.buttons.matching(identifier: retryID).count, 1)
    XCTAssertEqual(
      app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "today.goal.retry."))
        .count, 1)
    XCTAssertTrue(retry.exists)
    XCTAssertEqual(retry.label, "Try again")
    retry.tap()
    XCTAssertTrue(malformed.waitForExistence(timeout: 2))
    XCTAssertTrue(retry.exists)
    XCTAssertEqual(pastDue.value as? String, "3 of 5 reports, Due Aug 4, 2026, Past due")
    XCTAssertEqual(near.value as? String, "8 of 10 reviews, Due Aug 9, 2026, On pace")

    recordScreenshot("Today-goals-failure", of: app)
  }

  @MainActor
  func testMixedGoalRowsPersistAcrossRelaunchWithoutDuplicates() {
    let storeName = "TodayGoalSurfacingUITests-relaunch-\(UUID().uuidString)"
    let app = launch(fixture: "today-goals-mixed", storeName: storeName)

    XCTAssertTrue(app.otherElements["today.dashboard"].waitForExistence(timeout: 5))
    let expectedValues = [
      mixedPastDueID: "7 of 10 sections, Due Aug 4, 2026, Past due",
      mixedBehindID: "2 of 10 sessions, Due Aug 12, 2026, Behind",
      mixedNearID: "160 pages now · 60 of 100 pages, Due Aug 9, 2026, On pace",
    ]
    for (id, value) in expectedValues {
      XCTAssertEqual(goalRow(id, in: app).value as? String, value)
    }

    app.terminate()
    app.launchArguments = launchArguments(storeName: storeName, reset: false, fixture: nil)
    app.launch()

    XCTAssertTrue(app.otherElements["today.dashboard"].waitForExistence(timeout: 5))
    XCTAssertEqual(element("today.summary", in: app).label, "2 of 5")
    XCTAssertTrue(element("today.section.goals", in: app).exists)
    for (id, value) in expectedValues {
      XCTAssertEqual(goalElements(id, in: app).count, 1)
      XCTAssertEqual(goalRow(id, in: app).value as? String, value)
    }
  }

  @MainActor
  func testNoEligibleGoalsOmitGoalsHeadingAndLeaveHabitsUnchanged() {
    let app = launch(fixture: "today-goals-empty")

    XCTAssertTrue(app.otherElements["today.dashboard"].waitForExistence(timeout: 5))
    XCTAssertEqual(element("today.summary", in: app).label, "2 of 5")
    XCTAssertTrue(element("today.section.to-tend", in: app).exists)
    XCTAssertTrue(element("today.section.tended", in: app).exists)
    XCTAssertFalse(element("today.section.goals", in: app).exists)
    for suffix in 601...604 {
      XCTAssertFalse(goalRow("71000000-0000-0000-0000-000000000\(suffix)", in: app).exists)
    }
  }

  @MainActor
  func testGoalDetailMutationsMoveOnePersistentIdentityThroughTodayWithoutDuplicates() {
    let storeName = "TodayGoalSurfacingUITests-journey-\(UUID().uuidString)"
    let app = launch(fixture: "today-goals-journey", storeName: storeName)
    let todayIdentifier = "today.goal.\(journeyID)"

    XCTAssertTrue(app.otherElements["today.dashboard"].waitForExistence(timeout: 5))
    XCTAssertEqual(element("today.summary", in: app).label, "2 of 2")
    XCTAssertFalse(element("today.all-tended", in: app).exists)
    XCTAssertEqual(goalElements(journeyID, in: app).count, 1)
    XCTAssertEqual(
      goalRow(journeyID, in: app).value as? String,
      "1 of 10 sessions, Due Aug 20, 2026, Behind"
    )

    selectGoals(in: app)
    openGoalFromRoster(journeyID, in: app)
    addProgress("9", in: app)
    backToGoals(in: app)

    selectToday(in: app)
    assertAllTendedWithoutJourneyGoal(in: app)

    selectGoals(in: app)
    openGoalFromRoster(journeyID, in: app)
    let edit = element("goalDetail.edit", in: app)
    scrollToVisible(edit, in: app)
    edit.tap()
    XCTAssertTrue(element("goalForm.sheet", in: app).waitForExistence(timeout: 2))
    let removeDeadline = element("goalForm.deadline.remove", in: app)
    scrollToVisible(removeDeadline, in: app)
    removeDeadline.tap()
    let addDeadline = app.buttons["goalForm.deadline.add"]
    XCTAssertTrue(addDeadline.waitForExistence(timeout: 2))
    scrollToVisible(addDeadline, in: app)
    addDeadline.tap()
    XCTAssertTrue(element("goalForm.deadline.picker", in: app).waitForExistence(timeout: 2))
    let editSave = app.buttons["goalForm.save"]
    XCTAssertTrue(editSave.isEnabled)
    editSave.tap()
    XCTAssertTrue(element("goalForm.sheet", in: app).waitForNonExistence(timeout: 5))
    backToGoals(in: app)

    selectToday(in: app)
    var returned = goalRow(journeyID, in: app)
    XCTAssertTrue(returned.waitForExistence(timeout: 5))
    XCTAssertEqual(goalElements(journeyID, in: app).count, 1)
    XCTAssertEqual(returned.identifier, todayIdentifier)
    XCTAssertEqual(
      returned.value as? String,
      "10 of 10 sessions, Due Aug 5, 2026, On pace"
    )
    XCTAssertFalse(element("today.all-tended", in: app).exists)

    selectGoals(in: app)
    openGoalFromRoster(journeyID, in: app)
    let harvest = element("goalDetail.harvest", in: app)
    scrollToVisible(harvest, in: app)
    harvest.tap()
    XCTAssertTrue(
      app.staticTexts["Harvest “Journey practice goal”?"].waitForExistence(timeout: 2)
    )
    confirmPendingAction(named: "Harvest", in: app)
    XCTAssertTrue(app.staticTexts["Harvested"].waitForExistence(timeout: 2))
    backToGoals(in: app)

    selectToday(in: app)
    assertAllTendedWithoutJourneyGoal(in: app)

    selectGoals(in: app)
    let disclosure = app.buttons["goals.closed.disclosure"]
    scrollToRosterElement(disclosure, in: app)
    disclosure.tap()
    openGoalFromRoster(journeyID, in: app)
    let reopen = element("goalDetail.reopen", in: app)
    scrollToVisible(reopen, in: app)
    reopen.tap()
    XCTAssertTrue(
      app.staticTexts["Reopen “Journey practice goal”?"].waitForExistence(timeout: 2)
    )
    confirmPendingAction(named: "Reopen", in: app)
    backToGoals(in: app)

    selectToday(in: app)
    returned = goalRow(journeyID, in: app)
    XCTAssertTrue(returned.waitForExistence(timeout: 5))
    XCTAssertEqual(goalElements(journeyID, in: app).count, 1)
    XCTAssertEqual(returned.identifier, todayIdentifier)
    XCTAssertEqual(
      returned.value as? String,
      "10 of 10 sessions, Due Aug 5, 2026, On pace"
    )
    XCTAssertFalse(element("today.all-tended", in: app).exists)

    selectGoals(in: app)
    openGoalFromRoster(journeyID, in: app)
    let deleteGoal = element("goalDetail.deleteGoal", in: app)
    scrollToVisible(deleteGoal, in: app)
    deleteGoal.tap()
    XCTAssertTrue(
      app.staticTexts["Delete “Journey practice goal” permanently?"].waitForExistence(timeout: 2)
    )
    confirmPendingAction(named: "Delete Goal", in: app)
    XCTAssertTrue(element("shell.destination.goals", in: app).waitForExistence(timeout: 5))

    selectToday(in: app)
    assertAllTendedWithoutJourneyGoal(in: app)

    app.terminate()
    app.launchArguments = launchArguments(storeName: storeName, reset: false, fixture: nil)
    app.launch()

    XCTAssertTrue(element("shell.destination.today", in: app).waitForExistence(timeout: 5))
    assertAllTendedWithoutJourneyGoal(in: app)
    selectGoals(in: app)
    XCTAssertFalse(element("goals.row.\(journeyID)", in: app).exists)
  }

  @MainActor
  private func assertInformationalGoalRow(_ row: XCUIElement, in app: XCUIApplication) {
    XCTAssertNotEqual(row.elementType, .button)
    XCTAssertFalse(app.buttons[row.identifier].exists)
    XCTAssertEqual(row.descendants(matching: .button).count, 0)
    XCTAssertEqual(row.descendants(matching: .progressIndicator).count, 0)
  }

  @MainActor
  private func goalRow(_ id: String, in app: XCUIApplication) -> XCUIElement {
    element("today.goal.\(id.lowercased())", in: app)
  }

  @MainActor
  private func goalElements(_ id: String, in app: XCUIApplication) -> XCUIElementQuery {
    app.descendants(matching: .any).matching(identifier: "today.goal.\(id.lowercased())")
  }
  @MainActor
  private func assertAllTendedWithoutJourneyGoal(in app: XCUIApplication) {
    XCTAssertTrue(app.otherElements["today.dashboard"].waitForExistence(timeout: 5))
    XCTAssertEqual(element("today.summary", in: app).label, "2 of 2")
    XCTAssertEqual(element("today.all-tended", in: app).label, "All tended.")
    XCTAssertFalse(element("today.section.goals", in: app).exists)
    XCTAssertEqual(goalElements(journeyID, in: app).count, 0)
  }

  @MainActor
  private func openGoalFromRoster(_ id: String, in app: XCUIApplication) {
    let row = element("goals.row.\(id.uppercased())", in: app)
    scrollToRosterElement(row, in: app)
    XCTAssertTrue(row.exists)
    row.tap()
    XCTAssertTrue(element("goalDetail.screen", in: app).waitForExistence(timeout: 5))
  }

  @MainActor
  private func selectGoals(in app: XCUIApplication) {
    let tab = app.buttons["shell.tab.goals"]
    XCTAssertTrue(tab.waitForExistence(timeout: 5))
    tab.tap()
    XCTAssertTrue(element("shell.destination.goals", in: app).waitForExistence(timeout: 5))
  }

  @MainActor
  private func selectToday(in app: XCUIApplication) {
    let tab = app.buttons["shell.tab.today"]
    XCTAssertTrue(tab.waitForExistence(timeout: 5))
    tab.tap()
    XCTAssertTrue(element("shell.destination.today", in: app).waitForExistence(timeout: 5))
  }

  @MainActor
  private func addProgress(_ value: String, in app: XCUIApplication) {
    let add = element("goalDetail.addProgress", in: app)
    scrollToVisible(add, in: app)
    add.tap()
    XCTAssertTrue(element("goalProgressEntry.sheet", in: app).waitForExistence(timeout: 2))
    let today = app.buttons["goalProgressEntry.destination.today"]
    XCTAssertTrue(today.exists)
    today.tap()
    XCTAssertTrue(today.isSelected)
    replaceText(in: app.textFields["goalProgressEntry.value"], with: value)
    let save = app.buttons["goalProgressEntry.save"]
    XCTAssertTrue(save.isEnabled)
    save.tap()
    XCTAssertTrue(element("goalProgressEntry.sheet", in: app).waitForNonExistence(timeout: 5))
  }

  @MainActor
  private func backToGoals(in app: XCUIApplication) {
    let back = element("goalDetail.back", in: app)
    XCTAssertTrue(back.waitForExistence(timeout: 2))
    back.tap()
    XCTAssertTrue(element("shell.destination.goals", in: app).waitForExistence(timeout: 5))
  }

  @MainActor
  private func confirmPendingAction(named title: String, in app: XCUIApplication) {
    let confirm = app.buttons.matching(identifier: "goalDetail.confirmation.confirm").firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 2))
    XCTAssertEqual(confirm.label, title)
    confirm.tap()
    XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
  }

  @MainActor
  private func replaceText(in field: XCUIElement, with replacement: String) {
    XCTAssertTrue(field.waitForExistence(timeout: 2))
    field.tap()
    field.tap(withNumberOfTaps: 3, numberOfTouches: 1)
    field.typeText(replacement)
  }

  @MainActor
  private func scrollToRosterElement(_ target: XCUIElement, in app: XCUIApplication) {
    let overlay = app.buttons["shell.tab.goals"]
    for _ in 0..<24 {
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
      "Expected \(target.identifier.isEmpty ? target.label : target.identifier) in the Goals viewport"
    )
  }

  @MainActor
  private func scrollToVisible(_ target: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<24 {
      if target.exists, target.isHittable {
        return
      }
      app.swipeUp(velocity: .slow)
    }
    XCTFail(
      "Expected \(target.identifier.isEmpty ? target.label : target.identifier) to become visible")
  }

  @MainActor
  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }

  @MainActor
  private func launch(
    fixture: String,
    storeName: String? = nil
  ) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["TZ"] = "America/Los_Angeles"
    app.launchArguments = launchArguments(
      storeName: storeName ?? "TodayGoalSurfacingUITests-\(fixture)-\(UUID().uuidString)",
      reset: true,
      fixture: fixture
    )
    app.terminate()
    app.launch()
    return app
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
      "-tend-ui-test-instant",
      fixtureInstantArgument,
      "-AppleLanguages",
      "(en)",
      "-AppleLocale",
      "en_US",
    ]
    if reset {
      arguments.append("-tend-ui-test-reset")
    }
    if let fixture {
      arguments += ["-tend-ui-test-fixture", fixture]
    }
    return arguments
  }

  @MainActor
  private func recordScreenshot(_ name: String, of app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
