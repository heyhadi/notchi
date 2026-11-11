import AppKit

public struct NotchGeometry: Equatable, Sendable {
    public let width: CGFloat
    public let height: CGFloat
    public let hasNotch: Bool
    public let screenFrame: CGRect
    /// Horizontal center of the notch in global screen coordinates.
    public let centerX: CGFloat

    public static let fallback = NotchGeometry(width: 200, height: 32, hasNotch: false,
                                               screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), centerX: 720)

    public static var current: NotchGeometry { compute() }

    /// The built-in notched display if there is one (even when an external monitor is primary), else the menu-bar screen.
    public static var screen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil } ?? NSScreen.screens.first
    }

    public static func compute() -> NotchGeometry {
        guard let screen else { return fallback }
        let f = screen.frame
        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = f.width - left.width - right.width
            return NotchGeometry(width: width, height: screen.safeAreaInsets.top, hasNotch: true,
                                 screenFrame: f, centerX: f.minX + left.width + width / 2)
        }
        return NotchGeometry(width: 200, height: 32, hasNotch: false, screenFrame: f, centerX: f.midX)
    }
}
