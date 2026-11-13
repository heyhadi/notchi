import Foundation

/// Release versions as GitHub tags spell them ("v0.2.0") or Info.plist does ("0.2.0").
public enum AppVersion {
    /// Numeric parts, "v1.2.10" → [1, 2, 10]; nil when any part isn't a number.
    public static func parts(_ s: String) -> [Int]? {
        let t = s.hasPrefix("v") ? String(s.dropFirst()) : s
        let p = t.split(separator: ".").map { Int($0) }
        return p.isEmpty || p.contains(nil) ? nil : p.compactMap { $0 }
    }

    /// True only when `candidate` is a strictly newer version than `current` (missing parts count as 0).
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = parts(candidate), let b = parts(current) else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
