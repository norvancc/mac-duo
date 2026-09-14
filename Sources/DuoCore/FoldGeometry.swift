import Foundation

public struct FoldPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
}

public struct FoldQuad: Equatable, Sendable {
    public var topLeft: FoldPoint
    public var topRight: FoldPoint
    public var bottomLeft: FoldPoint
    public var bottomRight: FoldPoint
    public var points: [FoldPoint] { [bottomLeft, bottomRight, topRight, topLeft] }
    public static let identity = FoldQuad(topLeft: .init(0, 1), topRight: .init(1, 1),
                                          bottomLeft: .init(0, 0), bottomRight: .init(1, 0))
}

public struct FoldSettings: Equatable, Sendable {
    public var startAngle: Double = 110
    public var perspective: Double = 0.55
    /// Eye distance in units of panel height, measured normal to the reference panel.
    public var viewingDistance: Double = 2.4
    public var maxBlur: Double = 36
    public init() {}
}

public struct FoldFrame: Sendable {
    public var quad: FoldQuad
    public var progress: Double
    public var blur: Double
    public var darkness: Double
    /// Uniform scale in the observer's reference plane, before inverse projection.
    public var referenceScale: Double
    public var compensatedAngle: Double
}

public enum FoldGeometry {
    public static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(upper, max(lower, value))
    }
    public static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = clamp((x - a) / (b - a), 0, 1)
        return t * t * (3 - 2 * t)
    }

    /// Ray/plane intersection used only to calculate the visibility mask.
    /// The screenshot itself always stays in its original screen coordinates.
    /// Coordinates are normalized panel coordinates, with the hinge at y = 0.
    /// The eye is centered horizontally and half a panel-height above the hinge
    /// in the reference plane. It never tracks the user's face or camera.
    public static func inverseProject(_ point: FoldPoint, angle: Double,
                                      referenceAngle: Double, distance: Double) -> FoldPoint {
        let a = angle * .pi / 180
        let r = referenceAngle * .pi / 180
        let eyeY = 0.5 * sin(r) - distance * cos(r)
        let eyeZ = 0.5 * cos(r) + distance * sin(r)
        let targetY = point.y * sin(r)
        let targetZ = point.y * cos(r)
        let numerator = eyeY * cos(a) - eyeZ * sin(a)
        let denominator = (eyeY - targetY) * cos(a) - (eyeZ - targetZ) * sin(a)
        guard abs(denominator) > 1e-9 else { return .init(0.5, 0) }
        let t = numerator / denominator
        let y = eyeY + t * (targetY - eyeY)
        let z = eyeZ + t * (targetZ - eyeZ)
        return .init(0.5 + t * (point.x - 0.5), y * sin(a) + z * cos(a))
    }

    public static func frame(angle: Double, settings: FoldSettings) -> FoldFrame {
        let start = clamp(settings.startAngle, 70, 130)
        let actual = angle.isFinite ? clamp(angle, 0, 180) : start
        let progress = clamp((start - actual) / (start - 12), 0, 1)
        let distance = clamp(settings.viewingDistance, 1.2, 5)
        let strength = clamp(settings.perspective, 0, 1)
        // Once the panel is edge-on to the modeled eye, an inverse projection
        // has a pole. Freeze geometry before that horizon and fade to black.
        let r = start * .pi / 180
        let eyeY = 0.5 * sin(r) - distance * cos(r)
        let eyeZ = 0.5 * cos(r) + distance * sin(r)
        let horizon = atan2(eyeY, eyeZ) * 180 / .pi
        let safeAngle = max(horizon + 8, min(actual, start))
        let compensated = start + (safeAngle - start) * strength
        func quad(scale: Double) -> FoldQuad {
            func project(_ x: Double, _ y: Double) -> FoldPoint {
                inverseProject(.init(0.5 + (x - 0.5) * scale, y * scale),
                               angle: compensated, referenceAngle: start, distance: distance)
            }
            return .init(topLeft: project(0, 1), topRight: project(1, 1),
                         bottomLeft: project(0, 0), bottomRight: project(1, 0))
        }
        // Keep the mask's hinge endpoints at the screen corners. Its upper
        // boundary may extend past the panel; the renderer feathers visibility
        // at the viewport edges. These coordinates never deform the screenshot.
        let scale = 1.0
        return .init(quad: progress == 0 ? .identity : quad(scale: scale), progress: progress,
                     blur: max(0, settings.maxBlur) * smoothstep(0, 0.92, progress),
                     darkness: smoothstep(0.62, 1, progress), referenceScale: scale,
                     compensatedAngle: compensated)
    }
}
