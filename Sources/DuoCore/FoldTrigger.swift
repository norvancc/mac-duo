import Foundation

/// Requires a downward threshold crossing, so launching/waking at a low angle
/// never covers an already active desktop. Hysteresis prevents threshold chatter.
public struct FoldTrigger: Sendable {
    public enum Action: Equatable { case none, capture, update, dismiss }
    public private(set) var active = false
    public private(set) var armed = false
    private var previous: Double?
    public init() {}

    public mutating func reset() { active = false; armed = false; previous = nil }
    public mutating func consume(angle: Double, startAngle: Double, enabled: Bool) -> Action {
        guard enabled, angle.isFinite, (0...180).contains(angle) else {
            let wasActive = active
            reset()
            return wasActive ? .dismiss : .none
        }
        defer { previous = angle }
        if angle >= startAngle + 2 { armed = true }
        if active {
            if angle >= startAngle + 1 {
                active = false
                return .dismiss
            }
            return .update
        }
        if armed, let previous, previous > startAngle, angle <= startAngle {
            active = true
            armed = false
            return .capture
        }
        return .none
    }
}
