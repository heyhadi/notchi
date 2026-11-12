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

/// Chat with one session from the notch. Replies go out through the agent's Stop hook (see AgentKind.chatOutput).
struct ChatState {
    var open = false
    var queued: [String] = []                        // typed while the agent was busy; sent when its turn ends
    var held: (@Sendable (Data?) -> Void)?           // a finished turn we're holding until you reply
    var heldSince: Date?
    var lastReply: String?                           // what the agent said when it stopped
    var sentAt: Date?
    var lastSent: String?                            // shown in the chat box so you can see it went through
}

extension NotchModel {
    /// Entry point for every hook event. `respond` must be called once (nil = no decision).
    func handle(_ e: HookEvent, respond: @escaping @Sendable (Data?) -> Void) {
        if e.name == "SessionEnd", let s = store.sessions[SessionStore.key(e)] { recordHistory(s) }
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
        case "Stop" where e.agent.supportsChat:
            let key = SessionStore.key(e)
            releasePending(key: key)
            var c = chats[key] ?? ChatState()
            c.lastReply = e.message ?? c.lastReply
            if !c.queued.isEmpty {
                respond(e.agent.chatOutput(c.queued.joined(separator: "\n\n")))
                c.queued = []; c.sentAt = Date()
                store.markThinking(key: key)
            } else if c.open || UserDefaults.standard.bool(forKey: Prefs.holdForReply) {
                c.held?(nil) // never two holds for one session
                c.held = respond; c.heldSince = Date()
            } else {
                respond(nil)
            }
            if chats[key] != nil || c.held != nil { chats[key] = c }
        case "PermissionRequest", "Notification":
            respond(nil)
        default:
            let key = SessionStore.key(e)
            if e.name == "PostToolUse", var c = chats[key], !c.queued.isEmpty,
               let out = e.agent.midTurnOutput(c.queued.joined(separator: "\n\n")) {
                respond(out) // queued chat reaches the agent after this tool call, not at the end of its turn
                c.queued = []; c.sentAt = Date()
                chats[key] = c
            } else {
                respond(nil)
            }
            // Any further progress means the request was answered elsewhere (terminal) or abandoned.
            releasePending(key: SessionStore.key(e))
        }
        refresh(after: e)
    }

    /// Send a chat message to a session: right away if its finished turn is being held, else when its turn ends.
    func sendChat(_ key: String, _ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let agent = store.sessions[key]?.agent else { return }
        var c = chats[key] ?? ChatState()
        c.lastSent = text
        if let held = c.held {
            held(agent.chatOutput(text))
            c.held = nil; c.heldSince = nil; c.sentAt = Date()
            store.markThinking(key: key)
            SoundPlayer.shared.react(.delivered)
        } else {
            c.queued.append(text)
            SoundPlayer.shared.react(.queued)
        }
        chats[key] = c
        refresh(after: nil)
    }

    func setChatOpen(_ key: String, _ open: Bool) {
        var c = chats[key] ?? ChatState()
        c.open = open
        if !open { c.held?(nil); c.held = nil; c.heldSince = nil } // closing lets the agent finish normally
        chats[key] = c
        if open { onWantsKeyboard?() }
    }

    func closeChats() {
        for key in chats.keys where chats[key]?.open == true { setChatOpen(key, false) }
    }

    var isChatting: Bool { chats.values.contains { $0.open } }

    /// The user clicked Allow once / Deny / Answer in terminal on a card.
    func decide(_ id: PendingRequest.ID, _ decision: PermissionDecision?) {
        guard let i = pending.firstIndex(where: { $0.id == id }) else { return }
        let req = pending.remove(at: i)
        req.respond?(decision.flatMap { req.event.agent.output(for: $0) })
        if decision != nil { store.resolvePermission(sessionID: SessionStore.key(req.event)) }
        refresh(after: nil)
    }

    /// The user picked answers on a question card (question text → label or free text).
    func answer(_ id: PendingRequest.ID, _ answers: [String: String]) {
        guard let i = pending.firstIndex(where: { $0.id == id }) else { return }
        let req = pending.remove(at: i)
        req.respond?(req.event.agent.answerOutput(for: req.event, answers: answers))
        store.resolvePermission(sessionID: SessionStore.key(req.event))
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
        // Hooks give up after 590 s; drop holds nobody can answer anymore, and chats of ended sessions.
        for (k, c) in chats {
            if let since = c.heldSince, Date().timeIntervalSince(since) > 585 { chats[k]?.held?(nil); chats[k]?.held = nil; chats[k]?.heldSince = nil }
            if store.sessions[k] == nil { c.held?(nil); chats[k] = nil }
        }
        sessions = store.current()
        saveSessions()
        state = pending.isEmpty ? store.topState() : .needsYou
        if let e { peekText = peek(for: e) }
        if Date().timeIntervalSince(tokensRead) > 5 { // hooks fire many times a second during a turn
            tokensRead = Date()
            tokenMeter.update { [weak self] bySession, today in self?.tokens = bySession; self?.tokensToday = today; self?.alertIfOverLimit() }
        }
    }

    /// At most every 5 s; a change inside that window is written by one trailing save, so the last events aren't lost.
    private func saveSessions() {
        let wait = 5 - Date().timeIntervalSince(sessionsSaved)
        guard wait <= 0 else {
            if !sessionsSavePending { sessionsSavePending = true; DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in self?.sessionsSavePending = false; self?.saveSessions() } }
            return
        }
        guard let data = store.encoded() else { return }
        sessionsSaved = Date()
        try? data.write(to: Self.sessionsFile, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.sessionsFile.path) // owner-only like the socket dir
    }

    private func recordHistory(_ s: AgentSession) {
        let entry = HistoryEntry(agentLabel: s.agentLabel, project: s.project, started: s.started, ended: Date(), tokens: tokens[s.id])
        guard let data = SessionHistory.appending(entry, to: try? Data(contentsOf: Self.historyFile)) else { return }
        try? data.write(to: Self.historyFile, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.historyFile.path)
    }

    /// Once per day, when today's tokens pass the limit: one bwomp (if sounds are on). The footer turns amber meanwhile.
    private func alertIfOverLimit() {
        let day = Date().formatted(.iso8601.year().month().day())
        guard overTokenLimit, UserDefaults.standard.string(forKey: Prefs.limitAlertDay) != day else { return }
        UserDefaults.standard.set(day, forKey: Prefs.limitAlertDay)
        if UserDefaults.standard.bool(forKey: Prefs.soundsOn) { SoundPlayer.shared.preview(.bwomp) }
    }

    private func peek(for e: HookEvent) -> String? {
        switch e.name {
        case "PermissionRequest" where e.questions != nil:
            return String(format: L("%@ asks: %@"), e.agentLabel, e.questions?.first?.question ?? "")
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
