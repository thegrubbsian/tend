import XCTest

final class TendLaunchUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testColdLaunchShowsToday() {
    let app = XCUIApplication()

    app.launch()

    XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))
  }
}
