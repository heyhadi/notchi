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
            ForEach(model.sessions.prefix(5)) { SessionRow(session: $0) }
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
                    Text("\(session.agent.displayName) · \(session.project)").font(.system(size: 14)).foregroundColor(.white)
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

/// Always shows the full command (or full tool input) and the working directory.
/// Risky requests get a red label and no Allow button: they must be answered in the terminal.
private struct ApprovalCard: View {
    let req: PendingRequest
    let decide: (PermissionDecision?) -> Void

    var body: some View {
        let e = req.event
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(e.agent.displayName) · \(e.project)").font(.system(size: 14, weight: .medium)).foregroundColor(.white)
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
