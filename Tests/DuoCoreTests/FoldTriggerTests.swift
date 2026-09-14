import XCTest
@testable import DuoCore

final class FoldTriggerTests: XCTestCase {
    func testLaunchBelowThresholdDoesNotCapture() {
        var trigger = FoldTrigger()
        for angle in [85.0, 70, 55, 85, 109, 110] {
            XCTAssertEqual(trigger.consume(angle: angle, startAngle: 110, enabled: true), .none)
        }
        XCTAssertFalse(trigger.active)
    }

    func testCrossingCaptureOnlyOnceAndReopeningDismisses() {
        var trigger = FoldTrigger()
        XCTAssertEqual(trigger.consume(angle: 117, startAngle: 110, enabled: true), .none)
        XCTAssertEqual(trigger.consume(angle: 110, startAngle: 110, enabled: true), .capture)
        for angle in [105.0, 80, 50, 60, 80, 109, 110] {
            XCTAssertEqual(trigger.consume(angle: angle, startAngle: 110, enabled: true), .update)
        }
        XCTAssertEqual(trigger.consume(angle: 111, startAngle: 110, enabled: true), .dismiss)
        XCTAssertEqual(trigger.consume(angle: 110, startAngle: 110, enabled: true), .none)
        XCTAssertEqual(trigger.consume(angle: 113, startAngle: 110, enabled: true), .none)
        XCTAssertEqual(trigger.consume(angle: 108, startAngle: 110, enabled: true), .capture)
    }

    func testDisableOrResetCancelsAndRequiresRearm() {
        var trigger = FoldTrigger()
        _ = trigger.consume(angle: 120, startAngle: 110, enabled: true)
        _ = trigger.consume(angle: 95, startAngle: 110, enabled: true)
        XCTAssertEqual(trigger.consume(angle: 90, startAngle: 110, enabled: false), .dismiss)
        XCTAssertEqual(trigger.consume(angle: 80, startAngle: 110, enabled: true), .none)
        trigger.reset()
        XCTAssertFalse(trigger.active)
        XCTAssertFalse(trigger.armed)
    }

    func testInvalidReadingsCannotTriggerCapture() {
        var trigger = FoldTrigger()
        _ = trigger.consume(angle: 120, startAngle: 110, enabled: true)
        for angle in [Double.nan, .infinity, -1, 360] {
            XCTAssertEqual(trigger.consume(angle: angle, startAngle: 110, enabled: true), .none)
        }
    }
}
