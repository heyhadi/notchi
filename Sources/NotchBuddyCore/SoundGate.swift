import Foundation

/// Hard limit: at most one notification sound per `interval` (previews in Settings bypass it).
public struct SoundGate: Sendable {
    public var interval: TimeInterval = 60
    private var last: Date?

    public init() {}

    public mutating func allow(at now: Date = Date()) -> Bool {
        if let last, now.timeIntervalSince(last) < interval { return false }
        last = now
        return true
    }
}
