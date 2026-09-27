import XCTest

final class CSVViewerUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testLaunchShowsImportActionAndAContentState() {
    let app = XCUIApplication()
    app.launch()

    XCTAssertTrue(app.buttons["importCSVButton"].waitForExistence(timeout: 5))
    let stateIdentifiers = ["csvLoadingState", "csvTable", "csvEmptyState", "csvErrorState"]
    XCTAssertTrue(
      stateIdentifiers.contains {
        app.descendants(matching: .any)[$0].waitForExistence(timeout: 5)
      }
    )
  }

  @MainActor
  func testTablePlacesAdjacentColumnsWithoutWideEmptyGaps() {
    let app = XCUIApplication()
    app.launch()

    let firstHeader = app.staticTexts["First name"]
    let secondHeader = app.staticTexts["Sur name"]

    XCTAssertTrue(firstHeader.waitForExistence(timeout: 5))
    XCTAssertTrue(secondHeader.waitForExistence(timeout: 5))
    XCTAssertLessThan(secondHeader.frame.minX - firstHeader.frame.maxX, 40)
  }

  @MainActor
  func testTableScrollsHorizontallyWhenColumnsExceedScreenWidth() {
    let app = XCUIApplication()
    app.launch()

    let table = app.scrollViews["csvTable"]
    let lastHeader = app.staticTexts["Date of birth"]

    XCTAssertTrue(table.waitForExistence(timeout: 5))
    XCTAssertTrue(lastHeader.waitForExistence(timeout: 5))
    let window = app.windows.firstMatch
    XCTAssertGreaterThan(lastHeader.frame.maxX, window.frame.maxX)

    let start = table.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
    let end = table.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
    start.press(forDuration: 0.05, thenDragTo: end)

    XCTAssertLessThanOrEqual(lastHeader.frame.maxX, window.frame.maxX)
    XCTAssertGreaterThanOrEqual(lastHeader.frame.minX, window.frame.minX)
  }

  @MainActor
  func testNavigationUsesCompactTitle() {
    let app = XCUIApplication()
    app.launch()

    let navigationBar = app.navigationBars["CSV Viewer"]

    XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
    XCTAssertLessThan(navigationBar.frame.height, 60)
  }
}
