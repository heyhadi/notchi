import AppKit
import SwiftUI
import Combine
import NotchBuddyCore

final class RoamLook: ObservableObject {
    @Published var flipped = false
    @Published var tilt = 0.0
    @Published var spin = 0.0
    @Published var bubble: String?
}

/// What happens when two walkers run into each other.
private enum Bump: CaseIterable { case bonk, greet, dizzy, tumble }

private extension AvatarKind {
    /// What each buddy squeaks when poked.
    var catchphrase: String {
        switch self {
        case .bolt: "Zzzap!"
        case .mochi: "Mochi~"
        case .goo: "Blorp!"
        case .boo: "Boo!"
        case .tofu: "Tofu!"
        case .sprout: "Sprout!"
        case .ember: "Hot hot!"
        case .nimbus: "Puff!"
        case .inky: "Splat!"
        case .bun: "Bun bun!"
        case .byte: "01010!"
        case .quack: "Quack!"
        }
    }
}

/// An avatar walking along the bottom of the screen (above the Dock) while its agent is busy (`agent` nil: one avatar for all agents).
/// Off by default (Settings → Behavior). A small borderless panel; only the avatar itself takes clicks.
@MainActor
final class RoamPanel: NSPanel {
    private let model: NotchModel
    let agent: AgentKind?
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
    private var airY: CGFloat = 0               // height above the ground: dragged up, bounced, tumbled
    private var vy: CGFloat = 0
    private var ground: CGFloat = 0
    private var dragging = false
    private var grab = NSPoint.zero             // where on the avatar the mouse took hold
    private var downPoint = NSPoint.zero
    private var pokes = 0
    private var lastPoke = Date.distantPast
    private var bubbleUntil = Date.distantPast
    private var spinStart: Date?
    private var bumpCooldownUntil = Date.distantPast
    private var wasAwake = false                // only a buddy that was up falls asleep on screen
    private var sleepSince: Date?
    private var asleepDone = false
    private var lastZ = Date.distantPast
    private var zStep = 0
    var peers: () -> [RoamPanel] = { [] }       // the other walkers, set by RoamManager

    init(model: NotchModel, agent: AgentKind?) {
        self.model = model
        self.agent = agent
        super.init(contentRect: NSRect(x: 0, y: 0, width: 64, height: 64), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        alphaValue = 0
        let host = RoamHost(rootView: RoamAvatar(model: model, agent: agent, look: look))
        host.owner = self
        contentView = host
        observer = model.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.sync() } }
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
        sync()
    }

    private var defaultsObserver: NSObjectProtocol?

    override func close() {
        timer?.invalidate(); timer = nil; observer = nil
        defaultsObserver.map(NotificationCenter.default.removeObserver)
        super.close()
    }

    override var canBecomeKey: Bool { false }

    private var retired = false
    /// The agent is gone: fade out, then the manager drops this panel.
    func retire() { retired = true; sync() }

    private var enabled: Bool { UserDefaults.standard.bool(forKey: Prefs.roam) }
    private var shownState: AgentState { model.shown(for: agent) }
    private var walking: Bool { [.working, .thinking].contains(shownState) }

    private static let sleepFor: TimeInterval = 600 // lies there snoring this long, then fades away (an idle machine goes quiet)

    private var shouldShow: Bool {
        guard enabled && !retired else { return false }
        if shownState != .sleeping { return true }
        return sleepSince.map { Date().timeIntervalSince($0) < Self.sleepFor } ?? false
    }

    /// Show/hide and start/stop the walk timer from the current pref and agent state.
    private func sync() {
        if shownState != .sleeping { wasAwake = true; sleepSince = nil; asleepDone = false }
        else if wasAwake, sleepSince == nil { sleepSince = Date() }
        let visible = shouldShow
        if visible, timer == nil {
            if let span = walkSpan { x = .random(in: span.lowerBound...(span.upperBound - side)); setFrameOrigin(NSPoint(x: x, y: screenFrame(atX: x)?.minY ?? 0)) }
            last = Date()
            orderFrontRegardless()
            timer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.4; animator().alphaValue = visible ? 1 : 0 } completionHandler: {
            MainActor.assumeIsolated { if !self.shouldShow { self.timer?.invalidate(); self.timer = nil; self.orderOut(nil) } }
        }
    }

    /// Publishing re-renders the view; only do it when the angle visibly changes.
    private func setTilt(_ t: Double) { if abs(t - look.tilt) > 0.5 { look.tilt = t } }

    /// The screen a point on the x axis falls on (walkers cross from one screen to the next); the main screen as a fallback.
    private func screenFrame(atX px: CGFloat) -> NSRect? {
        (NSScreen.screens.first { $0.frame.minX <= px && px < $0.frame.maxX } ?? NSScreen.main)?.visibleFrame
    }

    /// Left and right limits over all screens side by side.
    private var walkSpan: ClosedRange<CGFloat>? {
        let f = NSScreen.screens.map(\.frame)
        guard let lo = f.map(\.minX).min(), let hi = f.map(\.maxX).max() else { return nil }
        return lo...hi
    }

    private var isOnGround: Bool { !dragging && airY == 0 && vy == 0 }

    private func say(_ lines: [String], for seconds: TimeInterval = 1.6) {
        look.bubble = lines.randomElement()
        bubbleUntil = Date().addingTimeInterval(seconds)
    }

    /// Moves the panel to the avatar's spot; it grows upward while a speech bubble is showing.
    private func place(hop: Double = 0, bob: Double = 0) {
        let wide = look.bubble != nil
        let w: CGFloat = wide ? 160 : side, h: CGFloat = wide ? 104 : side
        let r = NSRect(x: (x - (w - side) / 2).rounded(), y: (ground + airY + hop + bob).rounded(), width: w, height: h) // whole points: no sub-pixel redraws
        if r != frame { setFrame(r, display: false) }
    }

    /// Walks with a bob and tilt, stops now and then to look around or hop, watches a cursor near the Dock, hops for joy when an
    /// agent finishes and for attention while one needs you. Can be picked up and dropped (it falls and bounces), and bumps into other walkers.
    private func tick() {
        let now = Date(); let dt = now.timeIntervalSince(last); last = now
        guard let f = screenFrame(atX: x + side / 2), let span = walkSpan else { return }
        ground = f.minY
        if look.bubble != nil, now > bubbleUntil { look.bubble = nil }
        if shownState == .sleeping, !asleepDone, let s0 = sleepSince, now.timeIntervalSince(s0) > Self.sleepFor { asleepDone = true; sync() }
        if let s0 = spinStart {
            let u = now.timeIntervalSince(s0) / 0.7
            if u >= 1 { spinStart = nil; look.spin = 0 } else { look.spin = 360 * (1 - (1 - u) * (1 - u)) }
        }
        if dragging { setTilt(sin(now.timeIntervalSinceReferenceDate * 9) * 18); place(); return } // dangling from the mouse
        if airY > 0 || vy > 0 {
            vy -= 1800 * CGFloat(dt); airY += vy * CGFloat(dt)
            setTilt(Double(max(-15, min(15, vy / 60))))
            if airY <= 0 {
                airY = 0
                if vy < -300 { vy = -vy * 0.4; airY = 0.01; if look.bubble == nil { say(["Oof!", "Ouch!", "Bonk!"]) }
                    SoundPlayer.shared.react(.thud) } else { vy = 0; setTilt(0) }
            }
            place(); return
        }
        let mouse = NSEvent.mouseLocation, mid = x + side / 2
        let curious = walking && abs(mouse.x - mid) < 160 && mouse.y < f.minY + 240 && mouse.x >= f.minX && mouse.x < f.maxX
        if curious { direction = mouse.x >= mid ? 1 : -1 }
        if walking, !curious, now >= nextPauseAt {
            pauseUntil = now.addingTimeInterval(.random(in: 1...3))
            nextPauseAt = pauseUntil.addingTimeInterval(.random(in: 3...7))
            if Bool.random() { direction = -direction }
            if Int.random(in: 0..<10) < 3 { hopStart = now }
        }
        if shownState != lastShown { lastShown = shownState; if lastShown == .done { hopStart = now } }
        if shownState == .needsYou, hopStart == nil, now.timeIntervalSince(lastHop) > 1.4 { hopStart = now }
        let standing = !walking || curious || now < pauseUntil
        var bob = 0.0
        if shownState == .sleeping {
            setTilt(-80) // lying on its side
            if look.bubble == nil, now.timeIntervalSince(lastZ) > 1.8 {
                say([["z", "zZ", "zZz", "Zzz…"][zStep % 4]], for: 1.2); zStep += 1; lastZ = now
            }
        } else if standing {
            setTilt(0)
        } else {
            phase += dt * 9
            bob = abs(sin(phase)) * 3
            setTilt(sin(phase) * 4)
            x += direction * 70 * CGFloat(dt)
            if x < span.lowerBound { x = span.lowerBound; direction = 1 } else if x > span.upperBound - side { x = span.upperBound - side; direction = -1 }
            if now >= bumpCooldownUntil,
               let o = peers().first(where: { $0 !== self && $0.isOnGround && $0.alphaValue > 0.5 && abs($0.x - x) < 48 }) {
                bump(with: o)
            }
        }
        var hop = 0.0
        if let h = hopStart {
            let u = now.timeIntervalSince(h) / 0.4
            if u < 1 { hop = 24 * 4 * u * (1 - u) } else { hopStart = nil; lastHop = now }
        }
        place(hop: hop, bob: bob)
    }

    // MARK: Bumping into each other

    private func bump(with o: RoamPanel) {
        let until = Date().addingTimeInterval(3.5)
        bumpCooldownUntil = until; o.bumpCooldownUntil = until
        let kind = Bump.allCases.randomElement()!
        SoundPlayer.shared.react([.bonk: .bonk, .greet: .greet, .dizzy: .dizzy, .tumble: .whoa][kind]!) // once, not once per walker
        let away: CGFloat = x <= o.x ? -1 : 1 // I bounce left if I'm the left one
        // tumble: the one who got hit goes flying, the one who ran into it says sorry
        react(kind, away: away, partner: o.agent?.displayName ?? "friend", victim: false)
        o.react(kind, away: -away, partner: agent?.displayName ?? "friend", victim: true)
    }

    private func react(_ kind: Bump, away: CGFloat, partner: String, victim: Bool) {
        let now = Date()
        switch kind {
        case .bonk:
            direction = away; x += away * 14; hopStart = now
            say(["Bonk!", "Ow!", "Hey, watch it!", "Sorry!"])
        case .greet:
            direction = -away; pauseUntil = now.addingTimeInterval(2.2); nextPauseAt = pauseUntil.addingTimeInterval(4)
            if Bool.random() { hopStart = now }
            say(["Hi \(partner)!", "Hello!", "Oh, hi!", "\(partner)! Long time!"], for: 2)
        case .dizzy:
            direction = away; spinStart = now; pauseUntil = now.addingTimeInterval(1.5); nextPauseAt = pauseUntil.addingTimeInterval(4)
            say(["Dizzy…", "Whoa…", "Everything is spinning"])
        case .tumble:
            direction = away
            if victim { vy = 520; airY = 0.01; say(["Whoa!", "Waaah!", "Mayday!"]) }
            else { hopStart = now; say(["Oops!", "Sorry!", "My bad!"]) }
        }
    }

    // MARK: Mouse: drag, poke, double-click

    fileprivate func grabDown(_ e: NSEvent) {
        let m = NSEvent.mouseLocation
        downPoint = m; grab = NSPoint(x: m.x - x, y: m.y - (ground + airY))
        if e.clickCount == 2 { withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) { model.mode = .expanded } }
    }

    fileprivate func grabDrag(_ e: NSEvent) {
        let m = NSEvent.mouseLocation
        if !dragging, hypot(m.x - downPoint.x, m.y - downPoint.y) > 4 {
            dragging = true; vy = 0; hopStart = nil
            say(["Wooaah!", "Put me down!", "Heeelp!", "I can fly?!"], for: 3)
            SoundPlayer.shared.react(.grab)
        }
        guard dragging, let f = screenFrame(atX: m.x), let span = walkSpan else { return }
        x = max(span.lowerBound, min(span.upperBound - side, m.x - grab.x))
        ground = f.minY
        airY = max(0, min(f.height - 130, m.y - grab.y - f.minY))
    }

    fileprivate func grabUp(_ e: NSEvent) {
        if dragging { dragging = false; nextPauseAt = Date().addingTimeInterval(3); return } // let go: gravity takes over
        guard e.clickCount < 2 else { return }
        let now = Date()
        pokes = now.timeIntervalSince(lastPoke) > 3 ? 1 : pokes + 1
        lastPoke = now; hopStart = now
        if shownState == .sleeping { SoundPlayer.shared.react(.poke(level: 1)); say(["Huh?! Five more minutes…", "Zzz… who's there?", "Mmm… not now"], for: 2); return }
        let mine = model.currentAvatar(fallback: UserDefaults.standard.string(forKey: Prefs.avatar) ?? "bolt", for: agent)
        SoundPlayer.shared.react(pokes >= 4 ? .dizzy : .poke(level: pokes))
        switch pokes {
        case 1: say([mine.catchphrase, "Hehe!", "Hi!"])
        case 2, 3: say(["Tickles!", "Hey!", "That's my nose!", "Stop it, hehe"])
        default: spinStart = now; pokes = 0; say(["Dizzy… 🌀", "You're making me spin!"], for: 2)
        }
    }
}

private final class RoamHost<Content: View>: NSHostingView<Content> {
    weak var owner: RoamPanel?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { MainActor.assumeIsolated { owner?.grabDown(event) } }
    override func mouseDragged(with event: NSEvent) { MainActor.assumeIsolated { owner?.grabDrag(event) } }
    override func mouseUp(with event: NSEvent) { MainActor.assumeIsolated { owner?.grabUp(event) } }
}

private struct RoamAvatar: View {
    @ObservedObject var model: NotchModel
    let agent: AgentKind?
    @ObservedObject var look: RoamLook
    @AppStorage(Prefs.avatar) private var avatar = "bolt"
    @State private var prefsTick = 0

    var body: some View {
        VStack(spacing: 2) {
            if let text = look.bubble {
                Text(text)
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(Color(hex: 0x1B1B1F))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.white).shadow(color: .black.opacity(0.25), radius: 3, y: 1))
                    .fixedSize()
            }
            AvatarView(kind: { _ = prefsTick; return model.currentAvatar(fallback: avatar, for: agent) }(), state: model.shown(for: agent), size: 56)
                .scaleEffect(x: look.flipped ? -1 : 1, y: 1)
                .rotationEffect(.degrees(look.tilt + look.spin))
                .frame(width: 64, height: 64)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .contentShape(Rectangle())
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in prefsTick += 1 }
    }
}

/// Keeps one walker for all agents, or (with "one avatar per agent") one per agent that has a session.
@MainActor
final class RoamManager {
    private let model: NotchModel
    private var walkers: [AgentKind?: RoamPanel] = [:]
    private var observer: AnyCancellable?

    init(model: NotchModel) {
        self.model = model
        observer = model.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.sync() } }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
        sync()
    }

    private func sync() {
        let perAgent = UserDefaults.standard.bool(forKey: Prefs.avatarPerAgent)
        let want: Set<AgentKind?> = perAgent ? Set(model.sessions.map { Optional($0.agent) } + model.pending.map { Optional($0.event.agent) }) : [nil]
        for key in want where walkers[key] == nil {
            let w = RoamPanel(model: model, agent: key)
            w.peers = { [weak self] in Array(self?.walkers.values ?? [:].values) }
            walkers[key] = w
        }
        for (key, panel) in walkers where !want.contains(key) {
            walkers[key] = nil
            panel.retire()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { panel.close() }
        }
    }
}
