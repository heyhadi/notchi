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
        case "PermissionRequest" where e.agent.approvesInNotch:
            let risks = CommandRisk.reasons(for: e)
            if risks.isEmpty {
                pending.append(PendingRequest(event: e, risks: risks, respond: respond))
            } else {
                respond(nil) // risky: never decided here, the agent asks in its own UI
                pending.append(PendingRequest(event: e, risks: risks, respond: nil))
            }
        case "PreToolUse" where !e.agent.approvesInNotch:
            // Status-only agents: never approve, but make sure a risky command gets the agent's own prompt.
            let risks = CommandRisk.reasons(for: e)
            respond(risks.isEmpty ? nil : e.agent.forceAskOutput(reasons: risks))
            if risks.isEmpty { releasePending(key: SessionStore.key(e)) }
            else { pending.append(PendingRequest(event: e, risks: risks, respond: nil)) }
        case "PermissionRequest", "Notification":
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
        req.respond?(decision.flatMap { req.event.agent.output(for: $0) })
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
            return String(format: L("%@ needs approval"), "\(e.agentLabel) · \(e.project)")
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
