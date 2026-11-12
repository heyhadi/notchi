import AppKit
import SwiftUI
import Combine

/// The panel isn't key until clicked; without this the first click only focuses it and a second one reaches the buttons.
enum PointerState { @MainActor static var overRow = false }

private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // SwiftUI's own cursor update resets the arrow after ours; keep the hand while a clickable row is hovered.
    override func cursorUpdate(with event: NSEvent) { PointerState.overRow ? NSCursor.pointingHand.set() : super.cursorUpdate(with: event) }
    override func mouseMoved(with event: NSEvent) { super.mouseMoved(with: event); if PointerState.overRow { NSCursor.pointingHand.set() } }
}

@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSSetConnectionProperty") private func CGSSetConnectionProperty(_ cid: Int32, _ target: Int32, _ key: CFString, _ value: CFTypeRef) -> Int32

/// Lets this (never-frontmost) app change the cursor over its own panel. Private WindowServer call; if it ever vanishes the cursor just stays an arrow.
private func allowCursorWhileInBackground() {
    _ = CGSSetConnectionProperty(CGSMainConnectionID(), CGSMainConnectionID(), "SetsCursorInBackground" as CFString, kCFBooleanTrue)
}

public final class NotchPanel: NSPanel {
    public let model: NotchModel
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var clickMonitor: Any?
    private var idleObserver: AnyCancellable?
    private var idleHidden = false

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    public init(model: NotchModel) {
        self.model = model
        let initialRect = CGRect(x: 0, y: 0, width: 640, height: 520)
        super.init(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true

        let hostingView = FirstClickHostingView(rootView: NotchView(model: model))
        hostingView.frame = initialRect
        hostingView.autoresizingMask = [.width, .height]
        self.contentView = hostingView

        allowCursorWhileInBackground()
        updatePanelFrame()
        setupEventMonitors()
        idleObserver = model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateIdleVisibility() } // objectWillChange fires before the new value lands
        }
        updateIdleVisibility()
        model.onWantsKeyboard = { [weak self] in self?.makeKey() } // non-activating: typing works without stealing focus from other apps' windows

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        if let g = globalMonitor {
            NSEvent.removeMonitor(g)
        }
        if let l = localMonitor {
            NSEvent.removeMonitor(l)
        }
        if let c = clickMonitor {
            NSEvent.removeMonitor(c)
        }
        NotificationCenter.default.removeObserver(self)
    }

    public var currentContentRect: CGRect {
        let g = model.geometry
        let shapeSize = model.currentSize
        let width = shapeSize.width > 0 ? shapeSize.width : 200
        let height = shapeSize.height > 0 ? shapeSize.height : 32
        let x = g.centerX - width / 2.0
        let y = g.screenFrame.maxY - height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    public func updatePanelFrame() {
        let g = NotchGeometry.compute()
        let panelWidth: CGFloat = 640
        let panelHeight: CGFloat = 520
        let x = g.centerX - panelWidth / 2.0
        let y = g.screenFrame.maxY - panelHeight
        let panelFrame = CGRect(x: x, y: y, width: panelWidth, height: panelHeight)
        setFrame(panelFrame, display: true)
    }

    private func setupEventMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.updateMouseHitTesting()
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.updateMouseHitTesting()
            return event
        }

        // A click in any other app or on the desktop closes the chat box and folds the panel away.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.model.isChatting else { return }
            self.model.closeChats()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) { self.model.requestCollapse() }
        }
    }

    /// No agent busy for a while (every session asleep): fade the notch away; any new activity brings it back.
    private func updateIdleVisibility() {
        let idle = model.shown == .sleeping && model.mode != .expanded && !model.isChatting
        guard idle != idleHidden else { return }
        idleHidden = idle
        if idle { ignoresMouseEvents = true }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.4; animator().alphaValue = idle ? 0 : 1 }
    }

    private func updateMouseHitTesting() {
        guard !idleHidden else { return }
        let mouseLoc = NSEvent.mouseLocation
        let isInside = currentContentRect.contains(mouseLoc)
        let shouldIgnore = !isInside
        if self.ignoresMouseEvents != shouldIgnore {
            self.ignoresMouseEvents = shouldIgnore
        }
    }

    @objc private func screenParametersChanged() {
        updatePanelFrame()
    }
}
