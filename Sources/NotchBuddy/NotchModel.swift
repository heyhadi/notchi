import SwiftUI
import AppKit
import NotchBuddyCore

public enum NotchMode: String, CaseIterable, Sendable {
    case compact
    case peek
    case expanded
}

@MainActor
public final class NotchModel: ObservableObject {
    @Published public var state: AgentState = .sleeping {
        didSet {
            let oldShown = debugOverride ?? oldValue
            let newShown = shown
            if oldShown != newShown {
                handleShownChanged(oldValue: oldShown, newValue: newShown)
            }
        }
    }

    @Published public var debugOverride: AgentState? {
        didSet {
            let oldShown = oldValue ?? state
            let newShown = shown
            if oldShown != newShown {
                handleShownChanged(oldValue: oldShown, newValue: newShown)
            }
        }
    }

    public var shown: AgentState {
        debugOverride ?? state
    }

    @Published public var mode: NotchMode = .compact {
        didSet {
            if oldValue != mode {
                updateCurrentSize()
            }
        }
    }

    @Published public var peekText: String?

    @Published public var geometry: NotchGeometry = .current {
        didSet {
            updateCurrentSize()
        }
    }

    /// Visible width beside the camera on each side, and the avatar size in that ear.
    static let earWidth: CGFloat = 52
    static let earAvatar: CGFloat = 30
    @Published public var currentSize: CGSize = .zero
    // Phase 2: live agent data (see AgentHub.swift)
    @Published var sessions: [AgentSession] = []
    @Published var pending: [PendingRequest] = []
    @Published var chats: [String: ChatState] = [:]   // by SessionStore key
    var onWantsKeyboard: (() -> Void)?                 // the panel makes itself key so the chat box can take typing
    var store = SessionStore()
    @Published public var workingStartTime: Date?

    private var doneReturnTask: Task<Void, Never>?
    private var isDoneActive: Bool = false

    public init() {
        self.geometry = NotchGeometry.compute()
        self.mode = .compact
        updateCurrentSize()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func screenParametersChanged() {
        geometry = NotchGeometry.compute()
        updateCurrentSize()
    }

    public func updateCurrentSize(contentHeight: CGFloat? = nil) {
        switch mode {
        case .compact:
            currentSize = CGSize(width: max(200, geometry.width + 2 * Self.earWidth), height: geometry.height)
        case .peek:
            currentSize = CGSize(width: 300, height: 68)
        case .expanded:
            let h = min(500, max(200, contentHeight ?? 240))
            currentSize = CGSize(width: 600, height: h)
        }
    }

    public func requestCollapse() {
        if shown == .needsYou || shown == .error || (shown == .done && isDoneActive) {
            mode = .peek
        } else {
            mode = .compact
        }
    }

    private func handleShownChanged(oldValue: AgentState, newValue: AgentState) {
        SoundPlayer.shared.play(for: newValue)

        doneReturnTask?.cancel()
        doneReturnTask = nil

        if newValue == .working {
            if workingStartTime == nil {
                workingStartTime = Date()
            }
        } else {
            workingStartTime = nil
        }

        if newValue == .needsYou || newValue == .error || newValue == .done {
            if mode != .expanded {
                mode = .peek
            }
            if newValue == .done {
                isDoneActive = true
                doneReturnTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    guard !Task.isCancelled else { return }
                    guard let self = self else { return }
                    self.isDoneActive = false
                    if self.mode == .peek && self.shown == .done {
                        self.mode = .compact
                    }
                }
            }
        } else {
            if oldValue == .needsYou || oldValue == .error || oldValue == .done {
                if mode == .peek {
                    mode = .compact
                }
            }
        }
    }
}
