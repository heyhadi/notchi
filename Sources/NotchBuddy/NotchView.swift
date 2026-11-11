import SwiftUI
import NotchBuddyCore

public struct NotchShape: Shape {
    public var bottomRadius: CGFloat

    public var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    public init(bottomRadius: CGFloat) {
        self.bottomRadius = bottomRadius
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = max(0, min(bottomRadius, rect.width / 2, rect.height))
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
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
        path.closeSubpath()
        return path
    }
}

public struct NotchView: View {
    @ObservedObject public var model: NotchModel

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
            return max(200, model.geometry.width + 60)
        case .peek:
            return 300
        case .expanded:
            return 600
        }
    }

    private var currentHeight: CGFloat {
        switch model.mode {
        case .compact:
            return model.geometry.height
        case .peek:
            return 68
        case .expanded:
            return min(500, max(200, measuredExpandedHeight))
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Background black notch shape
                NotchShape(bottomRadius: currentRadius)
                    .fill(Color.black)
                    .frame(width: currentWidth, height: currentHeight)

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

    private var compactView: some View {
        HStack(alignment: .center, spacing: 0) {
            // Left ear: 22pt avatar
            BoltView(state: model.shown, size: 22)
                .padding(.leading, 10)

            Spacer()

            // Right ear: state dot + elapsed timer
            HStack(spacing: 6) {
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
            .padding(.trailing, 12)
        }
        .frame(height: model.geometry.height)
    }

    // MARK: - Peek Mode

    private var peekView: some View {
        VStack(spacing: 6) {
            // Row 1: ears
            HStack(alignment: .center, spacing: 0) {
                BoltView(state: model.shown, size: 22)
                    .padding(.leading, 10)

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
                .padding(.trailing, 12)
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
                BoltView(state: model.shown, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(L("Notch Buddy")) · \(localizedState(model.shown))")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                Spacer()
            }

            // Placeholder area: "No active sessions"
            VStack(spacing: 8) {
                Text(L("No active sessions"))
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: 0x8D8C94))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(hex: 0x1E1D23))
            )

            // Footer
            VStack(spacing: 12) {
                Rectangle()
                    .fill(Color(hex: 0x2A2A30))
                    .frame(height: 1)

                HStack {
                    Text(L("All data stays on this Mac"))
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: 0x8D8C94))
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, model.geometry.hasNotch ? model.geometry.height + 8 : 14) // keep text out from under the camera
        .padding(.bottom, 20)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ContentHeightPreferenceKey.self, value: geo.size.height)
            }
        )
    }

    // MARK: - Helpers

    private func handleHover(_ isHovering: Bool) {
        if isHovering {
            leaveTask?.cancel()
            leaveTask = nil

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

            if model.mode == .expanded {
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

    private func localizedState(_ state: AgentState) -> String {
        switch state {
        case .sleeping: return L("Sleeping")
        case .thinking: return L("Thinking")
        case .working: return L("Working")
        case .needsYou: return L("Needs you")
        case .done: return L("Done")
        case .error: return L("Error")
        }
    }
}

// MARK: - Subviews & Preferences

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
    static var defaultValue: CGFloat = 240
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
