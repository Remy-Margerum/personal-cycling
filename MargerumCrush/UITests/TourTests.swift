import XCTest

/// Plays a short first vintage in the simulator, screenshotting each screen
/// on the way: wait for the Sauvignon Blanc to ripen, pick it and let Doug
/// make it (he plays himself with -autopick), let the crew pick Grenache for
/// rosé and make it, end the harvest, walk Doug to the lab bench, bottle
/// Sybarite and the rosé, and release them.
/// .github/workflows/screenshots-crush.yml runs it and uploads the
/// screenshots.
final class TourTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-seed", "3", "-resetGame", "YES", "-autopick", "YES"]
        app.launch()
    }

    func testTour() throws {
        sleep(8) // the freshly booted simulator likes to show a notification first
        snap("01 Title")
        tap(app.buttons["Start the harvest"])
        snap("02 Harvest")

        // A few weeks for the Sauvignon Blanc to ripen.
        for _ in 0..<3 { tap(button(startingWith: "Wait until")) }
        scrollToTop()
        snap("03 Harvest, week 4")

        tap(app.buttons["Pick"])
        XCTAssertTrue(app.buttons["Start picking"].waitForExistence(timeout: 10))
        sleep(1) // let it finish sliding up
        snap("04 Briefing")
        tap(app.buttons["Start picking"])
        play(screenshot: "05 Picking")
        snap("06 Results")
        tap(app.buttons["To the crush pad"])
        snap("07 Crush briefing")

        // Doug makes the Sybarite (he plays himself with -autopick).
        tap(app.buttons["Make it with Doug"])
        sleep(7)
        snap("08 Doug at the press")
        sleep(12)
        snap("09 Doug in the cellar")
        XCTAssertTrue(app.buttons["Back to the vineyard"].waitForExistence(timeout: 180), "the crush never finished")
        snap("10 Crush results")
        tap(app.buttons["Back to the vineyard"])

        // The crew picks Grenache for rosé, and makes it.
        tap(button(startingWith: "Wait until"))
        tap(app.buttons["Let the crew pick it"].firstMatch)
        tap(app.buttons["For rosé"])
        tap(app.buttons["Leave it to the cellar crew"])
        snap("11 The cellar crew")
        tap(app.buttons["The crew makes it"])

        tap(app.buttons["End the harvest now"])
        tap(app.buttons["Leave it for the rain"])
        scrollToTop()
        snap("12 Cellar")

        // Doug walks to the lab bench on his own (-autopick) to blend.
        tap(app.buttons["Into the cellar with Doug"])
        let blend = app.buttons["Blend and bottle"]
        XCTAssertTrue(blend.waitForExistence(timeout: 15))
        waitUntilEnabled(blend, timeout: 30)
        snap("13 Barrel room")
        blend.tap()

        tap(button(containing: "Sybarite"))
        snap("14 Blending lab")
        tap(button(startingWith: "Bottle "))
        sleep(2) // let the score land
        snap("15 Critic")
        tap(app.buttons["Done"])

        tap(button(containing: "Rosé"))
        tap(button(startingWith: "Bottle "))
        sleep(2)
        snap("16 Critic, rosé")
        tap(app.buttons["Done"])
        tap(app.buttons["Done"]) // the lab bench
        tap(app.buttons["Leave the cellar"])

        tap(button(startingWith: "Release the"))
        let bulk = app.buttons["Release, and sell the rest in bulk"]
        if bulk.waitForExistence(timeout: 5) { bulk.tap() }
        scrollToTop()
        snap("17 The vintage report")
        app.swipeUp()
        snap("18 Between vintages")

        tap(app.buttons["Wine library"])
        snap("19 Wine library")
    }

    // MARK: Helpers

    /// Waits out a picking round. The app picks for itself (-autopick):
    /// XCUITest waits for the app to go idle before every query and tap, and
    /// a round never does, so a test can't pick fast enough.
    private func play(screenshot name: String?) {
        if let name {
            sleep(14)
            snap(name)
        }
        XCTAssertTrue(app.buttons["To the crush pad"].waitForExistence(timeout: 50), "nothing was picked")
    }

    private func button(startingWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func button(containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Waits for a button, scrolls it into view and taps it.
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "no \(element)", file: file, line: line)
        for _ in 0..<8 where !element.isHittable {
            if element.frame.midY < app.frame.midY { app.swipeDown() } else { app.swipeUp() }
        }
        element.tap()
    }

    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let enabled = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: element)
        wait(for: [enabled], timeout: timeout)
    }

    private func scrollToTop() {
        for _ in 0..<3 { app.swipeDown() }
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
