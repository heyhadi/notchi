import SwiftUI
import NotchBuddyCore

public struct NotchShape: Shape {
    public var bottomRadius: CGFloat
    public var openTop = false // the glow skips the top edge: it sits on the screen edge

    public var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    public init(bottomRadius: CGFloat, openTop: Bool = false) {
        self.bottomRadius = bottomRadius
        self.openTop = openTop
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = max(0, min(bottomRadius, rect.width / 2, rect.height))
        if openTop {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        if !openTop { path.closeSubpath() }
        return path
    }
}

public struct NotchView: View {
    @ObservedObject public var model: NotchModel
    @AppStorage(Prefs.language) private var language = "en" // re-render strings when the language changes
    @AppStorage(Prefs.avatar) private var avatar = "bolt"
    @AppStorage(Prefs.glow) private var glow = true
    @State private var prefsTick = 0 // re-render when a per-agent avatar is changed in Settings
    private var avatarKind: AvatarKind { _ = prefsTick; return model.currentAvatar(fallback: avatar) }

    @State private var hoverTask: Task<Void, Never>?
    @State private var leaveTask: Task<Void, Never>?
    @State private var showExpandedContent: Bool = false
    @State private var measuredExpandedHeight: CGFloat = 240

    public init(model: NotchModel) {
        self.model = model
    }

    private var currentRadius: CGFloat {
        switch model.mode {
        case .compact: return 14
        case .peek: return 22
        case .expanded: return 32
        }
    }

    private var currentWidth: CGFloat {
        switch model.mode {
        case .compact:
            return max(200, model.geometry.width + 2 * NotchModel.earWidth)
        case .peek:
            return 300
        case .expanded:
            return 600
        }
    }

    private var currentHeight: CGFloat {
        switch model.mode {
        case .compact:
            return model.compactHeight
        case .peek:
            return 68
        case .expanded:
            return min(500, max(200, measuredExpandedHeight))
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Background black notch shape, with the moving glow around its edge
                if glow && model.shown != .sleeping {
                    NotchGlow(state: model.shown, radius: currentRadius, blurred: true)
                        .frame(width: currentWidth, height: currentHeight)
                }
                NotchShape(bottomRadius: currentRadius)
                    .fill(Color.black)
                    .frame(width: currentWidth, height: currentHeight)
                if glow && model.shown != .sleeping {
                    NotchGlow(state: model.shown, radius: currentRadius, blurred: false)
                        .frame(width: currentWidth, height: currentHeight)
                }

                // Content inside the shape
                Group {
                    switch model.mode {
                    case .compact:
                        compactView
                    case .peek:
                        peekView
                    case .expanded:
                        expandedView
                            .opacity(showExpandedContent ? 1.0 : 0.0)
                    }
                }
                .frame(width: currentWidth, height: currentHeight, alignment: .top)
                .clipped()
            }
            .contentShape(NotchShape(bottomRadius: currentRadius))
            .onHover { isHovering in
                handleHover(isHovering)
            }
            .onTapGesture {
                handleTap()
            }
            Spacer()
        }
        .frame(width: 640, height: 520, alignment: .top)
        .animation(.spring(response: 0.55, dampingFraction: 0.68), value: model.mode)
        .animation(.spring(response: 0.55, dampingFraction: 0.68), value: currentHeight)
        .animation(.spring(response: 0.55, dampingFraction: 0.68), value: currentWidth)
        .onChange(of: model.mode) {
            handleModeTransition()
        }
        .onAppear { handleModeTransition() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in prefsTick += 1 }
        .ignoresSafeArea() // the panel overlaps the notch; don't let the safe area push content down
        .onPreferenceChange(ContentHeightPreferenceKey.self) { height in
            if height > 0 {
                measuredExpandedHeight = height
                if model.mode == .expanded {
                    model.updateCurrentSize(contentHeight: height)
                }
            }
        }
    }

    // MARK: - Compact Mode

    /// The notch is faded out while every agent sleeps; don't keep animating an avatar nobody can see.
    @ViewBuilder private var earAvatar: some View {
        if model.shown == .sleeping && model.mode != .expanded && !model.isChatting {
            Color.clear.frame(width: NotchModel.earAvatar, height: NotchModel.earAvatar)
        } else {
            AvatarView(kind: avatarKind, state: model.shown, size: NotchModel.earAvatar)
        }
    }

    private var compactView: some View {
        HStack(alignment: .center, spacing: 0) {
            // Left ear: 22pt avatar
            earAvatar
                .padding(.leading, 8)

            Spacer()

            // Right ear: state dot + elapsed timer
            HStack(spacing: 6) {
                if model.overTokenLimit { // today's tokens passed the limit set in Settings
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundColor(Color(hex: 0xFFB020))
                        .accessibilityLabel(L("Daily token limit"))
                }
                if model.shown != .sleeping {
                    PulsingDotView(
                        color: Color(hex: model.shown.colorHex),
                        shouldPulse: model.shown == .working || model.shown == .needsYou
                    )
                }
                if model.shown == .working {
                    ElapsedTimerView(startTime: model.workingStartTime)
                }
            }
            .padding(.trailing, 8)
        }
        .frame(height: model.compactHeight)
    }

    // MARK: - Peek Mode

    private var peekView: some View {
        VStack(spacing: 6) {
            // Row 1: ears
            HStack(alignment: .center, spacing: 0) {
                AvatarView(kind: avatarKind, state: model.shown, size: NotchModel.earAvatar)
                    .padding(.leading, 8)

                Spacer()

                HStack(spacing: 6) {
                    PulsingDotView(
                        color: Color(hex: model.shown.colorHex),
                        shouldPulse: model.shown == .working || model.shown == .needsYou
                    )
                    if model.shown == .working {
                        ElapsedTimerView(startTime: model.workingStartTime)
                    }
                }
                .padding(.trailing, 8)
            }
            .frame(height: max(26, model.geometry.height - 4))
            .padding(.top, 4)

            // Row 2: below the camera
            HStack(alignment: .center, spacing: 8) {
                Text(peekDefaultText(for: model.shown))
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                if model.shown == .needsYou {
                    Button(action: {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) {
                            model.mode = .expanded
                        }
                    }) {
                        Text(L("Review"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: 0x3D2600))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(hex: 0xFFB020)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(width: 300, height: 68)
    }

    // MARK: - Expanded Mode

    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header: 44pt avatar + title
            HStack(spacing: 12) {
                AvatarView(kind: avatarKind, state: model.shown, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headerTitle)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    if !model.pending.isEmpty {
                        Text(String(format: L("%d needs you"), model.pending.count))
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: 0xFFC15C))
                    }
                }
                Spacer()
            }

            SessionPanelView(model: model)

            // Footer
            VStack(spacing: 12) {
                Rectangle()
                    .fill(Color(hex: 0x2A2A30))
                    .frame(height: 1)

                HStack {
                    if model.tokensToday > 0 {
                        Text(model.tokenLimit > 0
                             ? String(format: L("Today: %@ of %@ tokens"), TokenCount.short(model.tokensToday), TokenCount.short(model.tokenLimit))
                             : String(format: L("Today: %@ tokens"), TokenCount.short(model.tokensToday)))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(model.overTokenLimit ? Color(hex: 0xFFB020) : Color(hex: 0xA9A8B0))
                        Text("·").font(.system(size: 12)).foregroundColor(Color(hex: 0x8D8C94))
                    }
                    Text(L("All data stays on this Mac"))
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: 0x8D8C94))
                    Spacer()
                    Button(action: {
                        SettingsWindow.show()
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: 0x8D8C94))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("Settings"))
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, model.geometry.hasNotch ? model.geometry.height + 8 : 14) // keep text out from under the camera
        .padding(.bottom, 20)
        .fixedSize(horizontal: false, vertical: true) // measure the natural height, not the clipped one
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ContentHeightPreferenceKey.self, value: geo.size.height)
            }
        )
    }

    // MARK: - Helpers

    private var headerTitle: String {
        let active = model.sessions.filter { $0.state != .sleeping }.count
        switch active {
        case 0: return L("All quiet")
        case 1: return L("1 agent running")
        default: return String(format: L("%d agents running"), active)
        }
    }

    private func handleHover(_ isHovering: Bool) {
        if isHovering {
            leaveTask?.cancel()
            leaveTask = nil

            guard UserDefaults.standard.bool(forKey: Prefs.openOnHover) else { return }

            if model.mode != .expanded {
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) {
                        model.mode = .expanded
                    }
                }
            }
        } else {
            hoverTask?.cancel()
            hoverTask = nil

            if model.mode == .expanded && !model.isChatting { // keep the panel open while a chat box is open
                leaveTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) {
                        model.requestCollapse()
                    }
                }
            }
        }
    }

    private func handleTap() {
        hoverTask?.cancel()
        hoverTask = nil
        leaveTask?.cancel()
        leaveTask = nil

        if model.mode != .expanded {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) {
                model.mode = .expanded
            }
        }
    }

    private func handleModeTransition() {
        if model.mode == .expanded {
            showExpandedContent = false
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard model.mode == .expanded else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    showExpandedContent = true
                }
            }
        } else {
            showExpandedContent = false
        }
    }

    private func peekDefaultText(for state: AgentState) -> String {
        if let custom = model.peekText, !custom.isEmpty {
            return custom
        }
        switch state {
        case .thinking:
            return L("Thinking…")
        case .working:
            return L("Working…")
        case .needsYou:
            return L("Needs you")
        case .done:
            return L("Done!")
        case .error:
            return L("Something went wrong")
        case .sleeping:
            return L("Sleeping")
        }
    }
}

// MARK: - Subviews & Preferences

/// Glowbar-style light running around the notch edge: four colors while busy, the state color (pulsing) when it wants you.
private struct NotchGlow: View {
    let state: AgentState
    let radius: CGFloat
    let blurred: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var alert: Bool { [.needsYou, .done, .error].contains(state) }
    private var colors: [Color] {
        if alert {
            let c = Color(hex: state.colorHex)
            return [c, c.opacity(0.2), c, c.opacity(0.2), c]
        }
        return [0x4285F4, 0x34A853, 0xFBBC05, 0xEA4335, 0x4285F4].map { Color(hex: $0) }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { ctx in
            let t = reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate
            let turn = alert ? 2.0 : 4.0 // seconds per lap
            let gradient = AngularGradient(colors: colors, center: .center,
                                           angle: .degrees(t.truncatingRemainder(dividingBy: turn) / turn * 360))
            let pulse = alert && !reduceMotion ? 0.65 + 0.35 * sin(t * 2 * .pi / 1.2) : 1
            Group {
                if blurred {
                    NotchShape(bottomRadius: radius, openTop: true).stroke(gradient, lineWidth: 6).blur(radius: 7)
                } else {
                    NotchShape(bottomRadius: radius, openTop: true).stroke(gradient, lineWidth: 1.5)
                }
            }
            .opacity(pulse)
        }
        .allowsHitTesting(false)
    }
}

private struct PulsingDotView: View {
    let color: Color
    let shouldPulse: Bool

    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .opacity((shouldPulse && !reduceMotion && isPulsing) ? 0.35 : 1.0)
            .onAppear {
                if shouldPulse && !reduceMotion {
                    withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }
            }
            .onChange(of: shouldPulse) {
                if shouldPulse && !reduceMotion {
                    withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                } else {
                    isPulsing = false
                }
            }
    }
}

private struct ElapsedTimerView: View {
    let startTime: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let start = startTime ?? context.date
            let elapsed = Int(max(0, context.date.timeIntervalSince(start)))
            let minutes = elapsed / 60
            let seconds = elapsed % 60
            Text(String(format: "%d:%02d", minutes, seconds))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white)
        }
    }
}

private struct ContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue()) // siblings without the preference report 0
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}
