import SwiftUI
import NotchBuddyCore

/// Expanded-panel body: the first pending approval card, then one row per session.
struct SessionPanelView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let req = model.pending.first {
                ApprovalCard(req: req) { model.decide(req.id, $0) }
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
                        SessionRow(session: session)
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

private struct SessionRow: View {
    let session: AgentSession

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(Color(hex: session.state.colorHex)).frame(width: 9, height: 9).padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(session.agentLabel) · \(session.project)").font(.system(size: 14)).foregroundColor(.white)
                    Spacer()
                    Text(detail).font(.system(size: 13)).foregroundColor(Color(hex: 0xA9A8B0))
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
        switch session.state {
        case .working, .thinking, .needsYou: return String(format: L("Your message goes in when %@ finishes this turn"), name)
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
