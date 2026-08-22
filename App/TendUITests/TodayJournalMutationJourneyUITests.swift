import XCTest

final class TodayJournalMutationJourneyUITests: XCTestCase {
  private let fixtureInstant = "2026-08-05T19:00:00Z"

  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testInvitationCreatesPersistsDeletesAndRestoresTodaysExactJournalPage() {
    XCUIDevice.shared.orientation = .portrait
    let storeName = "TodayJournalMutationJourneyUITests-\(UUID().uuidString)"
    let app = launch(
      storeName: storeName,
      reset: true,
      fixture: "today-journal-journey"
    )
    let invitation = app.buttons["today.journal.write"]
    scrollAbovePill(invitation, in: app)

    invitation.tap()
    let prose = app.textViews["journalEditor.prose"]
    XCTAssertTrue(prose.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["shell.tab.journal"].isSelected)
    XCTAssertFalse(element("journal.overview", in: app).exists)
    XCTAssertTrue(
      element("journalEditor.date", in: app).label.uppercased().contains("AUGUST 5")
    )
    XCTAssertTrue(app.buttons["journalEditor.scope.Today"].isSelected)
    XCTAssertEqual(app.textViews.matching(identifier: "journalEditor.prose").count, 1)

    prose.typeText("Notes from the invitation")
    XCTAssertTrue(waitForLabel("Saved", on: element("journalEditor.status", in: app)))
    app.buttons["shell.tab.today"].tap()
    XCTAssertTrue(element("shell.destination.today", in: app).waitForExistence(timeout: 5))
    XCTAssertFalse(element("today.section.journal", in: app).exists)
    XCTAssertFalse(app.buttons["today.journal.write"].exists)

    app.terminate()
    app.launchArguments = launchArguments(storeName: storeName, reset: false, fixture: nil)
    app.launch()
    XCTAssertTrue(element("shell.destination.today", in: app).waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["today.journal.write"].exists)

    app.buttons["shell.tab.journal"].tap()
    XCTAssertTrue(element("journal.overview", in: app).waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["journal.today"].label, "Notes from the invitation")
    app.buttons["journal.today"].tap()
    XCTAssertTrue(app.buttons["journalEditor.delete"].waitForExistence(timeout: 5))
    app.buttons["journalEditor.delete"].tap()
    XCTAssertTrue(app.alerts["Delete this entry?"].waitForExistence(timeout: 2))
    app.alerts["Delete this entry?"].buttons["Delete entry"].tap()
    XCTAssertTrue(element("journal.overview", in: app).waitForExistence(timeout: 5))

    app.buttons["shell.tab.today"].tap()
    let restoredInvitation = app.buttons["today.journal.write"]
    scrollAbovePill(restoredInvitation, in: app)
    XCTAssertTrue(restoredInvitation.isHittable)

    restoredInvitation.tap()
    let restoredProse = app.textViews["journalEditor.prose"]
    XCTAssertTrue(restoredProse.waitForExistence(timeout: 5))
    XCTAssertEqual(restoredProse.value as? String ?? "", "")
    XCTAssertEqual(app.textViews.matching(identifier: "journalEditor.prose").count, 1)
    restoredProse.typeText("A new page after deletion")
    XCTAssertTrue(waitForLabel("Saved", on: element("journalEditor.status", in: app)))
    app.buttons["journalEditor.back"].tap()
    XCTAssertTrue(element("journal.overview", in: app).waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["journal.today"].label, "A new page after deletion")
    XCTAssertEqual(app.buttons.matching(identifier: "journal.today").count, 1)
    recordScreenshot("today-journal-mutation-journey", of: app)
  }

  @MainActor
  private func launch(
    storeName: String,
    reset: Bool,
    fixture: String?
  ) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["TZ"] = "America/Los_Angeles"
    app.launchArguments = launchArguments(
      storeName: storeName,
      reset: reset,
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
  private func waitForLabel(
    _ label: String,
    on element: XCUIElement,
    timeout: TimeInterval = 5
  ) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label == %@", label),
      object: element
    )
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
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
