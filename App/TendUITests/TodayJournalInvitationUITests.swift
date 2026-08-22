import XCTest

final class TodayJournalInvitationUITests: XCTestCase {
  private let fixtureInstant = "2026-08-05T19:00:00Z"

  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testEligibleJournalSectionFollowsHabitsAndGoalsWithOneQuietAction() {
    XCUIDevice.shared.orientation = .portrait
    let app = launch(fixture: "today-journal-eligible")

    XCTAssertTrue(element("today.dashboard", in: app).waitForExistence(timeout: 5))
    let journalHeading = element("today.section.journal", in: app)
    let goalsHeading = element("today.section.goals", in: app)
    let card = app.buttons["today.journal.write"]
    let action = app.buttons["today.journal.write"]
    scrollAbovePill(action, in: app)

    XCTAssertEqual(journalHeading.label, "JOURNAL")
    XCTAssertGreaterThan(journalHeading.frame.minY, goalsHeading.frame.maxY)
    XCTAssertTrue(card.exists)
    XCTAssertEqual(action.label, "Write today's Journal entry")
    XCTAssertEqual(
      action.value as? String,
      "Gather a few lines from the day while they’re fresh."
    )
    XCTAssertEqual(card.descendants(matching: .button).count, 1)
    XCTAssertEqual(
      app.buttons.matching(
        NSPredicate(format: "identifier BEGINSWITH %@", "today.journal.")
      ).count,
      1
    )
    XCTAssertEqual(card.descendants(matching: .progressIndicator).count, 0)
    XCTAssertEqual(card.descendants(matching: .switch).count, 0)
    XCTAssertEqual(card.descendants(matching: .textField).count, 0)
    XCTAssertEqual(card.descendants(matching: .textView).count, 0)
    XCTAssertGreaterThanOrEqual(action.frame.height, 44)
    XCTAssertGreaterThan(action.frame.width, 280)
    XCTAssertLessThanOrEqual(action.frame.maxY, app.buttons["shell.tab.today"].frame.minY)
    recordScreenshot("today-journal-eligible", of: app)
  }

  @MainActor
  func testJournalSectionIsOmittedWhenCompleteAndComposesAfterEveryEmptyBody() {
    XCUIDevice.shared.orientation = .portrait
    let complete = launch(fixture: "today-journal-complete")
    XCTAssertTrue(element("today.dashboard", in: complete).waitForExistence(timeout: 5))
    XCTAssertFalse(element("today.section.journal", in: complete).exists)
    XCTAssertFalse(complete.buttons["today.journal.write"].exists)
    complete.terminate()

    let firstLaunch = launch(fixture: "today-journal-first-launch")
    XCTAssertTrue(element("today.empty", in: firstLaunch).waitForExistence(timeout: 5))
    let firstAction = firstLaunch.buttons["today.journal.write"]
    scrollAbovePill(firstAction, in: firstLaunch)
    XCTAssertGreaterThan(
      element("today.section.journal", in: firstLaunch).frame.minY,
      firstLaunch.buttons["today.plant-habit"].frame.maxY
    )
    firstLaunch.terminate()

    let inactive = launch(fixture: "today-journal-inactive")
    XCTAssertTrue(element("today.inactive", in: inactive).waitForExistence(timeout: 5))
    let inactiveAction = inactive.buttons["today.journal.write"]
    scrollAbovePill(inactiveAction, in: inactive)
    XCTAssertGreaterThan(
      element("today.section.journal", in: inactive).frame.minY,
      inactive.staticTexts["No active habits."].frame.maxY
    )
    inactive.terminate()

    let allTended = launch(fixture: "today-journal-all-tended")
    XCTAssertTrue(element("today.dashboard", in: allTended).waitForExistence(timeout: 5))
    XCTAssertTrue(element("today.all-tended", in: allTended).exists)
    let tendedHeading = element("today.section.tended", in: allTended)
    let allTendedAction = allTended.buttons["today.journal.write"]
    scrollAbovePill(allTendedAction, in: allTended)
    XCTAssertGreaterThan(
      element("today.section.journal", in: allTended).frame.minY,
      tendedHeading.frame.maxY
    )
  }

  @MainActor
  func testUnavailableJournalOffersOnlyRetryWithoutDisturbingSiblings() {
    XCUIDevice.shared.orientation = .portrait
    let app = launch(fixture: "today-journal-unavailable")

    XCTAssertTrue(element("today.dashboard", in: app).waitForExistence(timeout: 5))
    let summary = element("today.summary", in: app)
    let stableSummary = summary.label
    let stableHabitValue = element("today.row.Water seedlings", in: app).value as? String
    let card = element("today.journal.card", in: app)
    let retry = app.buttons["today.journal.retry"]
    scrollAbovePill(retry, in: app)

    XCTAssertEqual(
      element("today.journal.failure", in: app).label, "Journal is unavailable right now.")
    XCTAssertFalse(app.buttons["today.journal.write"].exists)
    XCTAssertEqual(card.descendants(matching: .button).count, 1)
    XCTAssertEqual(retry.label, "Try again")
    XCTAssertGreaterThanOrEqual(retry.frame.height, 44)

    retry.tap()
    XCTAssertTrue(element("today.journal.failure", in: app).waitForExistence(timeout: 2))
    XCTAssertEqual(summary.label, stableSummary)
    XCTAssertEqual(element("today.row.Water seedlings", in: app).value as? String, stableHabitValue)
    XCTAssertTrue(element("today.section.goals", in: app).exists)
    recordScreenshot("today-journal-unavailable", of: app)
  }

  @MainActor
  func testInvitationGrowsAtTwoAccessibilityTextSizesAndClearsFloatingPill() throws {
    XCUIDevice.shared.orientation = .portrait
    let sizes = [
      ("UICTContentSizeCategoryAccessibilityL", "accessibility-large"),
      ("UICTContentSizeCategoryAccessibilityXXL", "accessibility-extra-extra-large"),
    ]

    for size in sizes {
      let app = launch(
        fixture: "today-journal-eligible",
        additionalArguments: [
          "-UIPreferredContentSizeCategoryName",
          size.0,
          "-UIAccessibilityReduceMotionEnabled",
          "YES",
        ]
      )
      let action = app.buttons["today.journal.write"]
      scrollAbovePill(action, in: app)

      XCTAssertEqual(
        action.value as? String,
        "Gather a few lines from the day while they’re fresh."
      )
      XCTAssertTrue(action.isHittable)
      XCTAssertGreaterThan(action.frame.height, 44)
      XCTAssertLessThanOrEqual(action.frame.maxY, app.buttons["shell.tab.today"].frame.minY)
      try app.performAccessibilityAudit(for: [
        .hitRegion, .sufficientElementDescription, .textClipped,
      ])
      recordScreenshot("today-journal-\(size.1)", of: app)
      app.terminate()
    }
  }

  @MainActor
  private func launch(
    fixture: String,
    storeName: String? = nil,
    reset: Bool = true,
    additionalArguments: [String] = []
  ) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["TZ"] = "America/Los_Angeles"
    app.launchArguments =
      launchArguments(
        storeName: storeName ?? "TodayJournalInvitationUITests-\(fixture)-\(UUID().uuidString)",
        reset: reset,
        fixture: fixture
      ) + additionalArguments
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
      fixtureInstant,
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
  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)[identifier]
  }

  @MainActor
  private func scrollAbovePill(_ target: XCUIElement, in app: XCUIApplication) {
    let pill = app.buttons["shell.tab.today"]
    for _ in 0..<24 {
      if target.exists, target.isHittable, target.frame.maxY <= pill.frame.minY {
        return
      }
      app.swipeUp(velocity: .slow)
    }
    XCTFail("Expected \(target.identifier) above the floating tab pill")
  }

  @MainActor
  private func recordScreenshot(_ name: String, of app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
