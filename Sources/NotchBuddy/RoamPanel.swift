import AppKit
import SwiftUI
import Combine

final class RoamLook: ObservableObject { @Published var flipped = false }

/// The avatar walking along the bottom of the screen (above the Dock) while an agent is busy.
/// Off by default (Settings → Behavior). A small borderless panel; only the avatar itself takes clicks.
@MainActor
final class RoamPanel: NSPanel {
    private let model: NotchModel
    private let side: CGFloat = 64
    private var timer: Timer?
    private var observer: AnyCancellable?
    private var x: CGFloat = 0
    private var direction: CGFloat = 1 { didSet { if direction != oldValue { look.flipped = direction < 0 } } }
    private let look = RoamLook()
    private var last = Date()

    init(model: NotchModel) {
        self.model = model
        super.init(contentRect: NSRect(x: 0, y: 0, width: 64, height: 64), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        alphaValue = 0
        contentView = RoamHost(rootView: RoamAvatar(model: model, look: look))
        observer = model.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.sync() } }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
        sync()
    }

    override var canBecomeKey: Bool { false }

    private var enabled: Bool { UserDefaults.standard.bool(forKey: Prefs.roam) }
    private var walking: Bool { [.working, .thinking].contains(model.shown) }

    /// Show/hide and start/stop the walk timer from the current pref and agent state.
    private func sync() {
        let visible = enabled && model.shown != .sleeping
        if visible, timer == nil {
            if let f = screen?.visibleFrame ?? NSScreen.main?.visibleFrame { x = f.midX - side / 2; setFrameOrigin(NSPoint(x: x, y: f.minY)) }
            last = Date()
            orderFrontRegardless()
            timer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.4; animator().alphaValue = visible ? 1 : 0 } completionHandler: {
            MainActor.assumeIsolated { if !(self.enabled && self.model.shown != .sleeping) { self.timer?.invalidate(); self.timer = nil; self.orderOut(nil) } }
        }
    }

    private func tick() {
        let now = Date(); let dt = now.timeIntervalSince(last); last = now
        guard let f = NSScreen.main?.visibleFrame else { return }
        if walking {
            x += direction * 70 * CGFloat(dt)
            if x < f.minX { x = f.minX; direction = 1 } else if x > f.maxX - side { x = f.maxX - side; direction = -1 }
        } // done / needs you / error: stand still where it is
        setFrameOrigin(NSPoint(x: x, y: f.minY))
    }
}

private final class RoamHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct RoamAvatar: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var look: RoamLook
    @AppStorage(Prefs.avatar) private var avatar = "bolt"

    var body: some View {
        AvatarView(kind: AvatarKind(rawValue: avatar) ?? .bolt, state: model.shown, size: 56)
            .scaleEffect(x: look.flipped ? -1 : 1, y: 1)
            .frame(width: 64, height: 64)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) { model.mode = .expanded } }
    }
}
