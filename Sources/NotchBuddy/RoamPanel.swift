import AppKit
import SwiftUI
import Combine
import NotchBuddyCore

final class RoamLook: ObservableObject { @Published var flipped = false; @Published var tilt = 0.0 }

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
    private var phase = 0.0                     // step cycle, drives the bob and the tilt
    private var pauseUntil = Date.distantPast   // standing and looking around until then
    private var nextPauseAt = Date().addingTimeInterval(3)
    private var hopStart: Date?
    private var lastHop = Date.distantPast
    private var lastShown = AgentState.sleeping

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

    /// Walks with a bob and tilt, stops now and then to look around or hop, turns to watch the cursor when it is near the Dock,
    /// hops for joy when an agent finishes and keeps hopping for attention while one needs you.
    private func tick() {
        let now = Date(); let dt = now.timeIntervalSince(last); last = now
        guard let f = NSScreen.main?.visibleFrame else { return }
        let mouse = NSEvent.mouseLocation, mid = x + side / 2
        let curious = walking && abs(mouse.x - mid) < 160 && mouse.y < f.minY + 240
        if curious { direction = mouse.x >= mid ? 1 : -1 }
        if walking, !curious, now >= nextPauseAt {
            pauseUntil = now.addingTimeInterval(.random(in: 1...3))
            nextPauseAt = pauseUntil.addingTimeInterval(.random(in: 3...7))
            if Bool.random() { direction = -direction }
            if Int.random(in: 0..<10) < 3 { hopStart = now }
        }
        if model.shown != lastShown { lastShown = model.shown; if lastShown == .done { hopStart = now } }
        if model.shown == .needsYou, hopStart == nil, now.timeIntervalSince(lastHop) > 1.4 { hopStart = now }
        let standing = !walking || curious || now < pauseUntil
        var bob = 0.0
        if standing {
            look.tilt = 0
        } else {
            phase += dt * 9
            bob = abs(sin(phase)) * 3
            look.tilt = sin(phase) * 4
            x += direction * 70 * CGFloat(dt)
            if x < f.minX { x = f.minX; direction = 1 } else if x > f.maxX - side { x = f.maxX - side; direction = -1 }
        }
        var hop = 0.0
        if let h = hopStart {
            let u = now.timeIntervalSince(h) / 0.4
            if u < 1 { hop = 24 * 4 * u * (1 - u) } else { hopStart = nil; lastHop = now }
        }
        setFrameOrigin(NSPoint(x: x, y: f.minY + hop + bob))
    }
}

private final class RoamHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct RoamAvatar: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var look: RoamLook
    @AppStorage(Prefs.avatar) private var avatar = "bolt"
    @State private var prefsTick = 0

    var body: some View {
        AvatarView(kind: { _ = prefsTick; return model.currentAvatar(fallback: avatar) }(), state: model.shown, size: 56)
            .scaleEffect(x: look.flipped ? -1 : 1, y: 1)
            .rotationEffect(.degrees(look.tilt))
            .frame(width: 64, height: 64)
            .contentShape(Rectangle())
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in prefsTick += 1 }
            .onTapGesture { withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) { model.mode = .expanded } }
    }
}
