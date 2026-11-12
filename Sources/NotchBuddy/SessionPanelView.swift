import SwiftUI
import AppKit
import NotchBuddyCore

/// Expanded-panel body: the first pending approval card, then one row per session.
struct SessionPanelView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let req = model.pending.first {
                if let questions = req.event.questions {
                    QuestionCard(req: req, questions: questions,
                                 answer: { model.answer(req.id, $0) }, toTerminal: { model.decide(req.id, nil) })
                } else {
                    ApprovalCard(req: req) { model.decide(req.id, $0) }
                }
            }
            if model.sessions.isEmpty {
                Text(L("No active sessions"))
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: 0x8D8C94))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0x1E1D23)))
            }
            ForEach(model.sessions.prefix(5)) { session in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        ClickableRow(session: session, tokens: model.tokens[session.id])
                        if session.agent.supportsChat {
                            let open = model.chats[session.id]?.open == true
                            Button { model.setChatOpen(session.id, !open) } label: {
                                Image(systemName: open ? "bubble.left.fill" : "bubble.left")
                                    .font(.system(size: 13))
                                    .foregroundColor(model.chats[session.id]?.held != nil ? Color(hex: 0xFFB020)
                                                     : open ? Color(hex: 0x9BF2D0) : Color(hex: 0xA9A8B0))
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(format: open ? L("Close chat with %@") : L("Chat with %@"), session.agentLabel))
                        }
                    }
                    if model.chats[session.id]?.open == true {
                        ChatBox(model: model, session: session)
                    }
                }
            }
        }
    }
}

/// Row that jumps to the session's app on click; the highlight, arrow and pointer tell you it is clickable.
private struct ClickableRow: View {
    let session: AgentSession
    let tokens: Int?
    @State private var hovering = false

    var body: some View {
        SessionRow(session: session, tokens: tokens)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(hovering ? 0.07 : 0)))
            .overlay(alignment: .trailing) {
                if hovering {
                    Label(L("Open app"), systemImage: "arrow.up.forward.app")
                        .font(.system(size: 11)).foregroundColor(Color(hex: 0x9BF2D0))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color(hex: 0x1E1D23)))
                        .padding(.trailing, 4)
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0; PointerState.overRow = $0; if $0 { NSCursor.pointingHand.set() } }
            .onContinuousHover { if case .active = $0 { NSCursor.pointingHand.set() } }
            .onDisappear { if hovering { PointerState.overRow = false } }
            .onTapGesture { TerminalJump.activate(for: session) }
            .help(L("Open the app this session runs in"))
    }
}

private struct SessionRow: View {
    let session: AgentSession
    let tokens: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(Color(hex: session.state.colorHex)).frame(width: 9, height: 9).padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(session.agentLabel) · \(session.project)").font(.system(size: 14)).foregroundColor(.white)
                    Spacer()
                    Text(detail).font(.system(size: 13)).foregroundColor(Color(hex: 0xA9A8B0))
                    if let tokens, tokens > 0 {
                        Text(String(format: L("%@ tokens"), TokenCount.short(tokens)))
                            .font(.system(size: 12, design: .monospaced)).foregroundColor(Color(hex: 0x8D8C94))
                    }
                }
                if let step = session.state == .error ? session.message : session.lastStep {
                    Text(step).font(.system(size: 12, design: .monospaced)).foregroundColor(Color(hex: 0x8D8C94))
                        .lineLimit(1).truncationMode(.tail)
                }
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        switch session.state {
        case .done:
            let mins = Int(Date().timeIntervalSince(session.updated) / 60)
            return mins < 1 ? L("Done just now") : String(format: L("Done %d min ago"), mins)
        case .working, .thinking:
            return String(format: L("%d steps"), session.steps)
        default:
            return stateName(session.state)
        }
    }
}

/// An agent's question with choices. One single-choice question sends on click; otherwise pick, then Send.
private struct QuestionCard: View {
    let req: PendingRequest
    let questions: [AgentQuestion]
    let answer: ([String: String]) -> Void
    let toTerminal: () -> Void
    @State private var picked: [String: Set<String>] = [:]
    @State private var other: [String: String] = [:]

    private var oneClick: Bool { questions.count == 1 && !questions[0].multiSelect }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(req.event.agentLabel) · \(req.event.project)").font(.system(size: 14, weight: .medium)).foregroundColor(.white)
                Spacer()
                Text(L("Question")).font(.system(size: 12, weight: .medium)).foregroundColor(Color(hex: 0x3D2600))
                    .padding(.horizontal, 10).padding(.vertical, 3).background(Capsule().fill(Color(hex: 0xFFB020)))
            }
            ForEach(questions, id: \.question) { q in
                VStack(alignment: .leading, spacing: 8) {
                    Text(q.question).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(q.options, id: \.label) { o in
                        let on = picked[q.question]?.contains(o.label) == true
                        Button { tap(q, o.label) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(o.label).font(.system(size: 13, weight: .medium))
                                if !o.description.isEmpty && o.description != o.label {
                                    Text(o.description).font(.system(size: 11)).opacity(0.75).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .foregroundColor(on ? Color(hex: 0x3D2600) : .white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(on ? Color(hex: 0xFFB020) : Color(hex: 0x2A2A30)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                    TextField(L("Other answer…"), text: Binding(get: { other[q.question] ?? "" }, set: { other[q.question] = $0 }))
                        .textFieldStyle(.plain).font(.system(size: 13)).foregroundColor(.white)
                        .padding(.horizontal, 12).frame(minHeight: 32)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x0B0B0D)))
                        .onSubmit { if oneClick { send() } }
                }
            }
            HStack(spacing: 8) {
                if !oneClick || !(other[questions[0].question] ?? "").isEmpty {
                    Button(action: send) {
                        Text(L("Send answer")).font(.system(size: 14, weight: .medium)).foregroundColor(Color(hex: 0x3D2600))
                            .padding(.horizontal, 16).frame(minHeight: 36)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: complete ? 0xFFB020 : 0x6B5A2E)))
                    }
                    .buttonStyle(.plain).disabled(!complete)
                }
                Spacer()
                Button(action: toTerminal) {
                    Text(L("Answer in terminal")).font(.system(size: 14)).foregroundColor(Color(hex: 0xA9A8B0)).frame(minHeight: 36)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(hex: 0x1E1D23)))
    }

    private func value(_ q: AgentQuestion) -> String? {
        let typed = (other[q.question] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        let labels = q.options.map(\.label).filter { picked[q.question]?.contains($0) == true } // keep option order
        return labels.isEmpty ? nil : labels.joined(separator: ", ")
    }

    private var complete: Bool { questions.allSatisfy { value($0) != nil } }

    private func tap(_ q: AgentQuestion, _ label: String) {
        var set = picked[q.question] ?? []
        if q.multiSelect { if set.contains(label) { set.remove(label) } else { set.insert(label) } } else { set = [label] }
        picked[q.question] = set
        other[q.question] = nil
        if oneClick { send() }
    }

    private func send() {
        guard complete else { return }
        answer(Dictionary(uniqueKeysWithValues: questions.compactMap { q in value(q).map { (q.question, $0) } }))
    }
}

/// Reply to one agent session. Enter or the send button sends.
private struct ChatBox: View {
    @ObservedObject var model: NotchModel
    let session: AgentSession
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var chat: ChatState { model.chats[session.id] ?? ChatState() }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if chat.held != nil, let reply = chat.lastReply, !reply.isEmpty {
                ScrollView {
                    Text(reply).font(.system(size: 12)).foregroundColor(Color(hex: 0xD9D8DE))
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                .frame(maxHeight: 90)
            }
            HStack(spacing: 8) {
                TextField(String(format: L("Message %@…"), session.agentLabel), text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .focused($focused)
                    .onSubmit(send)
                    .padding(.horizontal, 12).frame(minHeight: 34)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x0B0B0D)))
                Button(action: send) {
                    Image(systemName: "paperplane.fill").font(.system(size: 13))
                        .foregroundColor(Color(hex: 0x3D2600))
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: draft.isEmpty ? 0x6B5A2E : 0xFFB020)))
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(L("Send"))
            }
            Text(status).font(.system(size: 11)).foregroundColor(Color(hex: 0x8D8C94))
            if let mine = chat.lastSent {
                Text(String(format: L("You: %@"), mine)).font(.system(size: 11)).foregroundColor(Color(hex: 0xA9A8B0))
                    .lineLimit(2).truncationMode(.tail)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0x1E1D23)))
        .onAppear { focused = true }
    }

    private var status: String {
        let name = session.agentLabel
        if let sent = chat.sentAt, Date().timeIntervalSince(sent) < 5 { return L("Sent") }
        if chat.held != nil { return String(format: L("%@ is waiting for your reply"), name) }
        if !chat.queued.isEmpty { return String(format: L("Will be sent when %@ finishes this turn"), name) }
        let stale = Date().timeIntervalSince(session.updated) > 600 // no event for 10 min: it is not mid-turn any more
        switch session.state {
        case .working, .thinking, .needsYou where !stale: return String(format: L("Your message goes in when %@ finishes this turn"), name)
        default: return String(format: L("%@ already finished. Your message goes in at the end of its next turn, or turn on \"Wait for my reply\" in Settings."), name)
        }
    }

    private func send() {
        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.sendChat(session.id, draft)
        draft = ""
    }
}

/// Always shows the full command (or full tool input) and the working directory.
/// Risky requests get a red label and no Allow button: they must be answered in the terminal.
private struct ApprovalCard: View {
    let req: PendingRequest
    let decide: (PermissionDecision?) -> Void

    var body: some View {
        let e = req.event
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(e.agentLabel) · \(e.project)").font(.system(size: 14, weight: .medium)).foregroundColor(.white)
                Spacer()
                Text(req.isRisky ? L("Risky") : L("Needs approval"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(req.isRisky ? .white : Color(hex: 0x3D2600))
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(Color(hex: req.isRisky ? 0xD93636 : 0xFFB020)))
            }
            Text(String(format: L("Wants to use %@ in %@:"), e.toolName ?? "?", abbreviate(e.cwd)))
                .font(.system(size: 13)).foregroundColor(Color(hex: 0xA9A8B0))
            // Never truncate: a hidden tail could hide the dangerous part. Long input scrolls instead.
            ViewThatFits(in: .vertical) {
                commandText
                ScrollView { commandText }.frame(height: 160)
            }
            .frame(maxHeight: 160)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x0B0B0D)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(req.isRisky ? Color(hex: 0xFF6B6B) : .clear, lineWidth: 1.5))

            if req.isRisky {
                Text(req.risks.joined(separator: " · ")).font(.system(size: 12, weight: .medium)).foregroundColor(Color(hex: 0xFF6B6B))
                Text(L("Risky commands can only be approved in the terminal."))
                    .font(.system(size: 13)).foregroundColor(.white)
                HStack { Spacer(); button(L("Dismiss"), primary: false) { decide(nil) } }
            } else {
                HStack(spacing: 8) {
                    button(L("Allow once"), primary: true) { decide(.allow) }
                    button(L("Deny"), primary: false) { decide(.deny(L("Denied from Notch Buddy"))) }
                    Spacer()
                    button(L("Answer in terminal"), primary: false, quiet: true) { decide(nil) }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(hex: 0x1E1D23)))
    }

    private var commandText: some View {
        Text(req.event.command ?? req.event.toolInputJSON ?? req.event.filePath ?? "")
            .font(.system(size: 13, design: .monospaced))
            .foregroundColor(req.isRisky ? Color(hex: 0xFF9B9B) : Color(hex: 0x9BF2D0))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func button(_ title: String, primary: Bool, quiet: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: primary ? .medium : .regular))
                .foregroundColor(primary ? Color(hex: 0x3D2600) : quiet ? Color(hex: 0xA9A8B0) : .white)
                .padding(.horizontal, 16).frame(minHeight: 36)
                .background(RoundedRectangle(cornerRadius: 12).fill(primary ? Color(hex: 0xFFB020) : .clear))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(primary || quiet ? .clear : Color(hex: 0x3A3940)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func abbreviate(_ path: String) -> String {
        path.hasPrefix(NSHomeDirectory()) ? "~" + path.dropFirst(NSHomeDirectory().count) : path
    }
}

func stateName(_ s: AgentState) -> String {
    switch s {
    case .sleeping: L("Sleeping")
    case .thinking: L("Thinking")
    case .working: L("Working")
    case .needsYou: L("Needs you")
    case .done: L("Done")
    case .error: L("Error")
    }
}

/// Brings the app a session runs in to the front. Hooks carry no tty/pid, so it can't pick the exact tab or window.
enum TerminalJump {
    private static let terminals = ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
                                    "net.kovidgoyal.kitty", "com.github.wez.wezterm", "org.alacritty"]

    static func activate(for s: AgentSession) {
        let ids: [String]
        if s.agentLabel.contains("VS Code") { ids = ["com.microsoft.VSCode"] }
        else if s.agentLabel.contains("JetBrains") { ids = [] }
        else if s.agentLabel.contains("Desktop") { ids = ["com.anthropic.claudefordesktop"] }
        else { ids = terminals }
        let apps = NSWorkspace.shared.runningApplications
        let app = ids.lazy.compactMap { id in apps.first { $0.bundleIdentifier == id } }.first
            ?? (s.agentLabel.contains("JetBrains") ? apps.first { $0.bundleIdentifier?.hasPrefix("com.jetbrains.") == true } : nil)
        app?.activate()
    }
}
