import XCTest

final class SmokeUITests: XCTestCase {
    func testLaunches() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetState"]
        app.launch()
        XCTAssertTrue(app.buttons["onboard-skip"].waitForExistence(timeout: 10))
    }
}
