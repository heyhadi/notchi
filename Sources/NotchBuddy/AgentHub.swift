import Foundation
import NotchBuddyCore

/// A permission request shown in the notch. Risky ones were already handed back to the terminal
/// (`respond == nil`) and can only be dismissed here.
struct PendingRequest: Identifiable {
    let id = UUID()
    let event: HookEvent
    let risks: [String]
    let received = Date()
    var respond: (@Sendable (Data?) -> Void)?
    var isRisky: Bool { !risks.isEmpty }
}

extension NotchModel {
    /// Entry point for every hook event. `respond` must be called once (nil = no decision).
    func handle(_ e: HookEvent, respond: @escaping @Sendable (Data?) -> Void) {
        store.apply(e)
        switch e.name {
        case "PermissionRequest":
            let risks = CommandRisk.reasons(for: e)
            if risks.isEmpty {
                pending.append(PendingRequest(event: e, risks: risks, respond: respond))
            } else {
                respond(nil) // risky: never decided here, Claude Code asks in the terminal
                pending.append(PendingRequest(event: e, risks: risks, respond: nil))
            }
        case "Notification":
            respond(nil)
        default:
            respond(nil)
            // Any further progress means the request was answered elsewhere (terminal) or abandoned.
            releasePending(key: SessionStore.key(e))
        }
        refresh(after: e)
    }

    /// The user clicked Allow once / Deny / Answer in terminal on a card.
    func decide(_ id: PendingRequest.ID, _ decision: PermissionDecision?) {
        guard let i = pending.firstIndex(where: { $0.id == id }) else { return }
        let req = pending.remove(at: i)
        req.respond?(decision?.hookOutput)
        if decision != nil { store.resolvePermission(sessionID: SessionStore.key(req.event)) }
        refresh(after: nil)
    }

    private func releasePending(key: String) {
        pending.removeAll { req in
            guard SessionStore.key(req.event) == key else { return false }
            req.respond?(nil)
            return true
        }
    }

    /// Recompute sessions/state; also called by a timer so Done/Error decay to Sleeping.
    func refresh(after e: HookEvent?) {
        // The hook gives up after 590 s; drop cards nobody can answer anymore.
        pending.removeAll { req in
            guard Date().timeIntervalSince(req.received) > 600 else { return false }
            req.respond?(nil)
            return true
        }
        sessions = store.current()
        state = pending.isEmpty ? store.topState() : .needsYou
        if let e { peekText = peek(for: e) }
    }

    private func peek(for e: HookEvent) -> String? {
        switch e.name {
        case "PermissionRequest", "Notification":
            return String(format: L("%@ needs approval"), "\(e.agent.displayName) · \(e.project)")
        case "Stop":
            let steps = store.sessions[SessionStore.key(e)]?.steps ?? 0
            return String(format: L("Done · %d steps"), steps)
        case "PostToolUseFailure", "StopFailure":
            return e.message.flatMap { $0.split(separator: "\n").first.map(String.init) } ?? L("Something went wrong")
        case "PreToolUse":
            return e.stepSummary
        default:
            return nil
        }
    }
}
