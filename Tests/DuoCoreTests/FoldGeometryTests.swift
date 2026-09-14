import XCTest
@testable import DuoCore

final class FoldGeometryTests: XCTestCase {
    func testOpenFrameIsUnmodified() {
        for angle in [110.0, 117, 130, 180] {
            let frame = FoldGeometry.frame(angle: angle, settings: FoldSettings())
            XCTAssertEqual(frame.quad, .identity)
            XCTAssertEqual(frame.blur, 0)
            XCTAssertEqual(frame.darkness, 0)
        }
    }

    func testPhysicalProjectionCancelsRenderedTrapezoid() {
        var settings = FoldSettings()
        settings.perspective = 1
        for angle in stride(from: 109.0, through: 40, by: -3) {
            let frame = FoldGeometry.frame(angle: angle, settings: settings)
            for x in [0.0, 0.25, 0.5, 0.75, 1] {
                for y in [0.0, 0.3, 0.6, 1] {
                    let expected = FoldPoint(0.5 + (x - 0.5) * frame.referenceScale, y * frame.referenceScale)
                    let pixel = FoldGeometry.inverseProject(expected, angle: frame.compensatedAngle,
                                                            referenceAngle: settings.startAngle,
                                                            distance: settings.viewingDistance)
                    // Independently project the physically tilted screen back onto
                    // the reference plane along a ray from the modeled eye.
                    let a = frame.compensatedAngle * .pi / 180
                    let r = settings.startAngle * .pi / 180
                    let eyeY = 0.5 * sin(r) - settings.viewingDistance * cos(r)
                    let eyeZ = 0.5 * cos(r) + settings.viewingDistance * sin(r)
                    let py = pixel.y * sin(a), pz = pixel.y * cos(a)
                    let distanceEye = eyeY * cos(r) - eyeZ * sin(r)
                    let distancePixel = py * cos(r) - pz * sin(r)
                    let t = distanceEye / (distanceEye - distancePixel)
                    let actualX = 0.5 + t * (pixel.x - 0.5)
                    let actualY = (eyeY + t * (py - eyeY)) * sin(r) + (eyeZ + t * (pz - eyeZ)) * cos(r)
                    XCTAssertEqual(actualX, expected.x, accuracy: 1e-9)
                    XCTAssertEqual(actualY, expected.y, accuracy: 1e-9)
                }
            }
        }
    }

    func testFrameIsFiniteAndBoundedThroughoutSupportedSettings() {
        for start in [70.0, 90, 110, 125] {
            for distance in [1.2, 2.4, 5] {
                for strength in [0.0, 0.5, 1] {
                    var settings = FoldSettings()
                    settings.startAngle = start
                    settings.viewingDistance = distance
                    settings.perspective = strength
                    for angle in 0...180 {
                        let frame = FoldGeometry.frame(angle: Double(angle), settings: settings)
                        for point in frame.quad.points {
                            XCTAssertTrue(point.x.isFinite && point.y.isFinite)
                            XCTAssertTrue((-0.000001...1.000001).contains(point.x))
                            // Full-size projection can extend above the panel;
                            // viewport cropping must replace whole-image fitting.
                            XCTAssertTrue((-0.000001...6).contains(point.y))
                        }
                        XCTAssertGreaterThanOrEqual(frame.quad.topLeft.y, frame.quad.bottomLeft.y)
                        XCTAssertGreaterThanOrEqual(frame.quad.topRight.x, frame.quad.topLeft.x)
                        XCTAssertEqual(frame.quad.bottomLeft.x, 0, accuracy: 1e-9)
                        XCTAssertEqual(frame.quad.bottomRight.x, 1, accuracy: 1e-9)
                        XCTAssertEqual(frame.quad.bottomLeft.y, 0, accuracy: 1e-9)
                        XCTAssertEqual(frame.quad.bottomRight.y, 0, accuracy: 1e-9)
                    }
                }
            }
        }
    }

    func testCompensationNarrowsTopAndHingeStaysFixed() {
        let frame = FoldGeometry.frame(angle: 65, settings: FoldSettings())
        XCTAssertLessThan(frame.quad.topRight.x - frame.quad.topLeft.x,
                          frame.quad.bottomRight.x - frame.quad.bottomLeft.x)
        XCTAssertEqual(frame.quad.bottomLeft.y, 0, accuracy: 1e-9)
        XCTAssertEqual(frame.quad.bottomRight.y, 0, accuracy: 1e-9)
        XCTAssertEqual(frame.quad.bottomLeft.x, 0, accuracy: 1e-9)
        XCTAssertEqual(frame.quad.bottomRight.x, 1, accuracy: 1e-9)
        XCTAssertEqual(frame.referenceScale, 1)
    }

    func testDefaultDoesNotTurnDesktopIntoTallNarrowCutout() {
        let frame = FoldGeometry.frame(angle: 65, settings: FoldSettings())
        XCTAssertGreaterThan(frame.quad.topRight.x - frame.quad.topLeft.x, 0.8)
        XCTAssertLessThan(frame.quad.topLeft.y, 1.05)
        XCTAssertEqual(frame.quad.bottomRight.x - frame.quad.bottomLeft.x, 1, accuracy: 1e-9)
    }

    func testClosingAndReversingAreContinuous() {
        let settings = FoldSettings()
        var previous = FoldGeometry.frame(angle: 110, settings: settings)
        for i in 1...980 {
            let angle = 110 - Double(i) / 10
            let next = FoldGeometry.frame(angle: angle, settings: settings)
            for (a, b) in zip(previous.quad.points, next.quad.points) {
                XCTAssertLessThan(abs(a.x - b.x), 0.01)
                XCTAssertLessThan(abs(a.y - b.y), 0.01)
            }
            XCTAssertGreaterThanOrEqual(next.blur, previous.blur)
            XCTAssertGreaterThanOrEqual(next.darkness, previous.darkness)
            XCTAssertEqual(next.quad, FoldGeometry.frame(angle: angle, settings: settings).quad)
            previous = next
        }
        XCTAssertEqual(previous.darkness, 1)
    }

    func testZeroCompensationKeepsRectangle() {
        var settings = FoldSettings()
        settings.perspective = 0
        let frame = FoldGeometry.frame(angle: 50, settings: settings)
        for (actual, expected) in zip(frame.quad.points, FoldQuad.identity.points) {
            XCTAssertEqual(actual.x, expected.x, accuracy: 1e-9)
            XCTAssertEqual(actual.y, expected.y, accuracy: 1e-9)
        }
    }
}
