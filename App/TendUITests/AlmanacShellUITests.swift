import XCTest

final class AlmanacShellUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testColdLaunchShowsTodaySelectedWithoutNativeTabBar() {
    let app = launchFreshApp()
    let todayTab = app.buttons["shell.tab.today"]
    let habitsTab = app.buttons["shell.tab.habits"]

    XCTAssertTrue(app.otherElements["shell.destination.today"].waitForExistence(timeout: 5))
    XCTAssertTrue(todayTab.exists)
    XCTAssertEqual(todayTab.label, "Today")
    XCTAssertTrue(todayTab.isSelected)
    XCTAssertTrue(habitsTab.exists)
    XCTAssertEqual(habitsTab.label, "Habits")
    XCTAssertFalse(habitsTab.isSelected)
    XCTAssertEqual(app.tabBars.count, 0)
  }

  @MainActor
  func testTappingHabitsSwitchesDestinationAndSelectedState() {
    let app = launchFreshApp()
    let todayTab = app.buttons["shell.tab.today"]
    let habitsTab = app.buttons["shell.tab.habits"]

    XCTAssertTrue(todayTab.waitForExistence(timeout: 5))
    habitsTab.tap()

    XCTAssertTrue(app.otherElements["shell.destination.habits"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.otherElements["shell.destination.today"].exists)
    XCTAssertFalse(todayTab.isSelected)
    XCTAssertTrue(habitsTab.isSelected)
  }

  @MainActor
  func testBackgroundPreservesHabitsAndRelaunchRestoresToday() {
    let app = launchFreshApp()
    let todayTab = app.buttons["shell.tab.today"]
    let habitsTab = app.buttons["shell.tab.habits"]

    XCTAssertTrue(todayTab.waitForExistence(timeout: 5))
    habitsTab.tap()
    XCTAssertTrue(app.otherElements["shell.destination.habits"].waitForExistence(timeout: 5))

    XCUIDevice.shared.press(.home)
    app.activate()

    XCTAssertTrue(app.otherElements["shell.destination.habits"].waitForExistence(timeout: 5))
    XCTAssertTrue(habitsTab.isSelected)

    app.terminate()
    app.launch()

    XCTAssertTrue(app.otherElements["shell.destination.today"].waitForExistence(timeout: 5))
    XCTAssertTrue(todayTab.isSelected)
    XCTAssertFalse(habitsTab.isSelected)
  }

  @MainActor
  private func launchFreshApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.terminate()
    app.launch()
    return app
  }
}
