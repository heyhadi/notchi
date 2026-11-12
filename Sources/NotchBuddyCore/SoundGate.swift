import Foundation

/// Hard limit: at most one notification sound per `interval` (60 s; "needs you" has its own shorter gate) (previews in Settings bypass it).
public struct SoundGate: Sendable {
    public var interval: TimeInterval = 60
    private var last: Date?

    public init(interval: TimeInterval = 60) { self.interval = interval }

    public mutating func allow(at now: Date = Date()) -> Bool {
        if let last, now.timeIntervalSince(last) < interval { return false }
        last = now
        return true
    }
}
