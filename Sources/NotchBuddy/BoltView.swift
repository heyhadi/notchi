import SwiftUI
import NotchBuddyCore

public struct BoltView: View {
    public let state: AgentState
    public let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastStateChange: Date = Date()

    public init(state: AgentState, size: CGFloat) {
        self.state = state
        self.size = size
    }

    public var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0.0 : timeline.date.timeIntervalSinceReferenceDate
            let startle = computeStartle(time: time)

            ZStack {
                BoltCanvas(state: state, time: time, reduceMotion: reduceMotion)
            }
            .frame(width: 120, height: 120)
            .scaleEffect(startle, anchor: .center)
            .scaleEffect(size / 120.0, anchor: .center)
            .frame(width: size, height: size)
        }
        .onChange(of: state) {
            lastStateChange = Date()
        }
    }

    private func computeStartle(time: Double) -> CGFloat {
        guard !reduceMotion else { return 1.0 }
        let elapsed = time - lastStateChange.timeIntervalSinceReferenceDate
        if elapsed >= 0 && elapsed < 0.18 {
            let p = elapsed / 0.18
            let easeOut = 1.0 - (1.0 - p) * (1.0 - p)
            return CGFloat(1.12 - 0.12 * easeOut)
        }
        return 1.0
    }
}

private struct BoltCanvas: View {
    let state: AgentState
    let time: Double
    let reduceMotion: Bool

    // Tokens
    private let bodyColor = Color(hex: 0x3DDC97)
    private let darkGreen = Color(hex: 0x1E8E66)
    private let visorColor = Color(hex: 0x1B1B1F)
    private let faceMint = Color(hex: 0x9BF2D0)
    private let cheekPink = Color(hex: 0xFF8FB1)
    private let shadowColor = Color(hex: 0x1B1B1F, opacity: 0.1)

    var body: some View {
        ZStack {
            // Shadow (120x120 space)
            Ellipse()
                .fill(shadowColor)
                .frame(width: 52, height: 8)
                .position(x: 60, y: 113)

            // Animated character body/head
            let motion = computeMotion()
            ZStack {
                // Antenna
                Path { p in
                    p.move(to: CGPoint(x: 60, y: 24))
                    p.addLine(to: CGPoint(x: 60, y: 12))
                }
                .stroke(darkGreen, style: StrokeStyle(lineWidth: 4, lineCap: .round))

                // Bulb
                Circle()
                    .fill(Color(hex: state.colorHex))
                    .frame(width: 12, height: 12)
                    .position(x: 60, y: 10)
                    .opacity(bulbOpacity())

                // Lower Body (hidden in working state where laptop sits in front)
                if state != .working {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(bodyColor)
                        .frame(width: 36, height: 22)
                        .position(x: 60, y: 93)

                    // Belly plate
                    RoundedRectangle(cornerRadius: 3)
                        .fill(darkGreen)
                        .frame(width: 16, height: 9)
                        .position(x: 60, y: 92.5)
                }

                // Side ears
                RoundedRectangle(cornerRadius: 5)
                    .fill(darkGreen)
                    .frame(width: 10, height: 18)
                    .position(x: 21, y: 53)

                RoundedRectangle(cornerRadius: 5)
                    .fill(darkGreen)
                    .frame(width: 10, height: 18)
                    .position(x: 99, y: 53)

                // Head
                RoundedRectangle(cornerRadius: 27)
                    .fill(bodyColor)
                    .frame(width: 72, height: 62)
                    .position(x: 60, y: 53)

                // Visor
                RoundedRectangle(cornerRadius: 18)
                    .fill(visorColor)
                    .frame(width: 54, height: 40)
                    .position(x: 60, y: 52)

                // Cheeks
                Ellipse()
                    .fill(cheekPink)
                    .frame(width: 9, height: 5.2)
                    .position(x: 39, y: 63)

                Ellipse()
                    .fill(cheekPink)
                    .frame(width: 9, height: 5.2)
                    .position(x: 81, y: 63)

                // Face expressions (eyes & mouth)
                faceContent
            }
            .offset(x: motion.dx, y: motion.dy)
            .rotationEffect(.degrees(motion.rotation), anchor: motion.anchor)
            .scaleEffect(x: motion.scaleX, y: motion.scaleY, anchor: motion.anchor)

            // Overlays: laptop, bubbles, badges, confetti, smoke
            stateOverlays
        }
        .frame(width: 120, height: 120)
    }

    // MARK: - State Faces

    @ViewBuilder
    private var faceContent: some View {
        let blinkScale = computeBlink()

        switch state {
        case .sleeping:
            // Closed arc eyes
            Path { p in
                p.move(to: CGPoint(x: 42, y: 52))
                p.addQuadCurve(to: CGPoint(x: 54, y: 52), control: CGPoint(x: 48, y: 57))
                p.move(to: CGPoint(x: 66, y: 52))
                p.addQuadCurve(to: CGPoint(x: 78, y: 52), control: CGPoint(x: 72, y: 57))
            }
            .stroke(faceMint, style: StrokeStyle(lineWidth: 3, lineCap: .round))

            // Small mouth
            Ellipse()
                .fill(faceMint)
                .frame(width: 5, height: 4)
                .position(x: 60, y: 63)

        case .thinking:
            // Eyes glance up (cy 47)
            Group {
                Ellipse()
                    .fill(faceMint)
                    .frame(width: 10, height: 13)
                    .position(x: 51, y: 47)

                Ellipse()
                    .fill(faceMint)
                    .frame(width: 10, height: 13)
                    .position(x: 75, y: 47)
            }
            .scaleEffect(x: 1.0, y: blinkScale, anchor: UnitPoint(x: 0.5, y: 47.0 / 120.0))

            // Flat mouth
            Path { p in
                p.move(to: CGPoint(x: 55, y: 63))
                p.addLine(to: CGPoint(x: 65, y: 63))
            }
            .stroke(faceMint, style: StrokeStyle(lineWidth: 3, lineCap: .round))

        case .working:
            // Eyes lower (cy 54)
            Group {
                Ellipse()
                    .fill(faceMint)
                    .frame(width: 11, height: 13)
                    .position(x: 48, y: 54)

                Ellipse()
                    .fill(faceMint)
                    .frame(width: 11, height: 13)
                    .position(x: 72, y: 54)
            }
            .scaleEffect(x: 1.0, y: blinkScale, anchor: UnitPoint(x: 0.5, y: 54.0 / 120.0))

            // Mouth
            Path { p in
                p.move(to: CGPoint(x: 55, y: 64))
                p.addQuadCurve(to: CGPoint(x: 65, y: 64), control: CGPoint(x: 60, y: 66))
            }
            .stroke(faceMint, style: StrokeStyle(lineWidth: 3, lineCap: .round))

        case .needsYou:
            // Big round eyes with highlights
            Group {
                Circle()
                    .fill(faceMint)
                    .frame(width: 16, height: 16)
                    .position(x: 48, y: 50)

                Circle()
                    .fill(Color.white)
                    .frame(width: 5, height: 5)
                    .position(x: 50.5, y: 46.5)

                Circle()
                    .fill(faceMint)
                    .frame(width: 16, height: 16)
                    .position(x: 72, y: 50)

                Circle()
                    .fill(Color.white)
                    .frame(width: 5, height: 5)
                    .position(x: 74.5, y: 46.5)
            }
            .scaleEffect(x: 1.0, y: blinkScale, anchor: UnitPoint(x: 0.5, y: 50.0 / 120.0))

            // "o" mouth
            Ellipse()
                .fill(faceMint)
                .frame(width: 7, height: 8)
                .position(x: 60, y: 64)

        case .done:
            // Happy arc eyes
            Path { p in
                p.move(to: CGPoint(x: 42, y: 54))
                p.addQuadCurve(to: CGPoint(x: 54, y: 54), control: CGPoint(x: 48, y: 45))
                p.move(to: CGPoint(x: 66, y: 54))
                p.addQuadCurve(to: CGPoint(x: 78, y: 54), control: CGPoint(x: 72, y: 45))
            }
            .stroke(faceMint, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))

            // Open pink mouth
            Path { p in
                p.move(to: CGPoint(x: 53, y: 60))
                p.addQuadCurve(to: CGPoint(x: 67, y: 60), control: CGPoint(x: 60, y: 70))
                p.closeSubpath()
            }
            .fill(cheekPink)

        case .error:
            // Spinning dashed spiral eyes
            let spinAngle = reduceMotion ? 0.0 : (time.truncatingRemainder(dividingBy: 1.0)) * 360.0
            Group {
                Circle()
                    .stroke(Color(hex: 0xFF9B9B), style: StrokeStyle(lineWidth: 2.5, dash: [10, 4]))
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(spinAngle))
                    .position(x: 48, y: 51)

                Circle()
                    .stroke(Color(hex: 0xFF9B9B), style: StrokeStyle(lineWidth: 2.5, dash: [10, 4]))
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(spinAngle))
                    .position(x: 72, y: 51)
            }

            // Wavy mouth
            Path { p in
                p.move(to: CGPoint(x: 52, y: 64))
                p.addQuadCurve(to: CGPoint(x: 60, y: 64), control: CGPoint(x: 56, y: 61))
                p.addQuadCurve(to: CGPoint(x: 68, y: 64), control: CGPoint(x: 64, y: 67))
            }
            .stroke(Color(hex: 0xFF9B9B), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
    }

    // MARK: - Overlays per state

    @ViewBuilder
    private var stateOverlays: some View {
        switch state {
        case .sleeping:
            if !reduceMotion {
                // Rising "z z Z"
                risingZ(index: 0, x: 92, y: 30, fontSize: 12, delay: 0.0, text: "z")
                risingZ(index: 1, x: 98, y: 22, fontSize: 14, delay: 0.9, text: "z")
                risingZ(index: 2, x: 104, y: 14, fontSize: 16, delay: 1.8, text: "Z")
            }

        case .thinking:
            // Thought bubble
            Circle()
                .fill(Color.white)
                .overlay(Circle().stroke(Color(hex: 0xD9CFFF), lineWidth: 1.5))
                .frame(width: 5, height: 5)
                .position(x: 94, y: 26)

            RoundedRectangle(cornerRadius: 9)
                .fill(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(hex: 0xD9CFFF), lineWidth: 1.5))
                .frame(width: 34, height: 18)
                .position(x: 101, y: 11)

            // 3 pulsing dots
            pulsingDot(x: 93, y: 11, delay: 0.0)
            pulsingDot(x: 101, y: 11, delay: 0.2)
            pulsingDot(x: 109, y: 11, delay: 0.4)

        case .working:
            // Small laptop in front (body rect 42, 82 hidden behind)
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(hex: 0x2A2A30))
                .frame(width: 64, height: 20)
                .position(x: 60, y: 98)

            RoundedRectangle(cornerRadius: 1.5)
                .fill(bodyColor)
                .frame(width: 22, height: 3)
                .position(x: 46, y: 94.5)

            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(hex: 0x5E5D66))
                .frame(width: 34, height: 3)
                .position(x: 52, y: 101.5)

        case .needsYou:
            // Pulsing orange "!" badge
            let popScale: CGFloat = reduceMotion ? 1.0 : computePopScale()
            ZStack {
                Circle()
                    .fill(Color(hex: 0xFFB020))
                    .frame(width: 24, height: 24)

                Text("!")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: 0x3D2600))
            }
            .scaleEffect(popScale, anchor: .center)
            .position(x: 102, y: 20)

        case .done:
            if !reduceMotion {
                // Confetti bursts
                confetti(startX: 18, startY: 36, dx: -12, dy: -22, color: Color(hex: 0xFFB020), delay: 0.0)
                confetti(startX: 98, startY: 34, dx: 12, dy: -24, color: Color(hex: 0xFF8FB1), delay: 0.0)
                confetti(startX: 28, startY: 16, dx: -8, dy: -20, color: Color(hex: 0x5AB8FF), delay: 0.2)
                confetti(startX: 88, startY: 14, dx: 8, dy: -22, color: Color(hex: 0x3DDC97), delay: 0.2)
                confetti(startX: 74, startY: 4, dx: 4, dy: -18, color: Color(hex: 0xA78BFA), delay: 0.4)
            }

        case .error:
            if !reduceMotion {
                // Rising smoke puffs
                smokePuff(x: 86, y: 20, r: 5, delay: 0.0)
                smokePuff(x: 94, y: 14, r: 4, delay: 0.7)
                smokePuff(x: 80, y: 12, r: 3.5, delay: 1.4)
            }
        }
    }

    // MARK: - Animation Computations

    private struct MotionData {
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        var rotation: Double = 0
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
        var anchor: UnitPoint = .center
    }

    private func computeMotion() -> MotionData {
        guard !reduceMotion else { return MotionData() }

        switch state {
        case .sleeping:
            // Slow 4 s float (nbFloat: 50% translateY(-5px))
            let t = (time.truncatingRemainder(dividingBy: 4.0)) / 4.0
            let dy = CGFloat(-5.0 * (0.5 - 0.5 * cos(t * 2.0 * .pi)))
            return MotionData(dy: dy)

        case .thinking:
            // Float 2.6s
            let t = (time.truncatingRemainder(dividingBy: 2.6)) / 2.6
            let dy = CGFloat(-5.0 * (0.5 - 0.5 * cos(t * 2.0 * .pi)))
            return MotionData(dy: dy)

        case .working:
            // Bob 0.5s (nbBob: 50% translateY(-3px))
            let t = (time.truncatingRemainder(dividingBy: 0.5)) / 0.5
            let dy = CGFloat(-3.0 * (0.5 - 0.5 * cos(t * 2.0 * .pi)))
            return MotionData(dy: dy)

        case .needsYou:
            // Hop 0.9s: 0%,100% translateY(0); 30% translateY(-10px) rotate(-4deg); 60% translateY(0) rotate(4deg)
            let p = (time.truncatingRemainder(dividingBy: 0.9)) / 0.9
            var dy: CGFloat = 0
            var rot: Double = 0
            if p < 0.3 {
                let s = p / 0.3
                dy = CGFloat(-10.0 * s)
                rot = -4.0 * s
            } else if p < 0.6 {
                let s = (p - 0.3) / 0.3
                dy = CGFloat(-10.0 * (1.0 - s))
                rot = -4.0 + 8.0 * s
            } else {
                let s = (p - 0.6) / 0.4
                dy = 0
                rot = 4.0 * (1.0 - s)
            }
            return MotionData(dy: dy, rotation: rot, anchor: .bottom)

        case .done:
            // Squash-and-stretch jump 1s:
            // 0%,100% scale(1.08,.92)
            // 40% translateY(-12px) scale(.94,1.08)
            // 60% translateY(-12px) scale(1)
            let p = (time.truncatingRemainder(dividingBy: 1.0)) / 1.0
            var dy: CGFloat = 0
            var sx: CGFloat = 1
            var sy: CGFloat = 1
            if p < 0.4 {
                let s = p / 0.4
                dy = CGFloat(-12.0 * s)
                sx = CGFloat(1.08 + (0.94 - 1.08) * s)
                sy = CGFloat(0.92 + (1.08 - 0.92) * s)
            } else if p < 0.6 {
                let s = (p - 0.4) / 0.2
                dy = -12.0
                sx = CGFloat(0.94 + (1.0 - 0.94) * s)
                sy = CGFloat(1.08 + (1.0 - 1.08) * s)
            } else {
                let s = (p - 0.6) / 0.4
                dy = CGFloat(-12.0 * (1.0 - s))
                sx = CGFloat(1.0 + (1.08 - 1.0) * s)
                sy = CGFloat(1.0 + (0.92 - 1.0) * s)
            }
            return MotionData(dy: dy, scaleX: sx, scaleY: sy, anchor: .bottom)

        case .error:
            // Wobble +-6 deg 1.2s
            let t = (time.truncatingRemainder(dividingBy: 1.2)) / 1.2
            let rot = -6.0 + 12.0 * (0.5 - 0.5 * cos(t * 2.0 * .pi))
            return MotionData(rotation: rot, anchor: .bottom)
        }
    }

    private func bulbOpacity() -> Double {
        guard !reduceMotion else { return 1.0 }
        switch state {
        case .thinking, .working, .needsYou, .error:
            // nbBulb .6s steps(1) infinite: 50% opacity .25
            let step = Int((time.truncatingRemainder(dividingBy: 0.6)) / 0.3)
            return step == 0 ? 1.0 : 0.25
        case .sleeping, .done:
            return 1.0
        }
    }

    private func computeBlink() -> CGFloat {
        guard !reduceMotion else { return 1.0 }
        switch state {
        case .thinking, .working, .needsYou:
            let block = floor(time / 4.0)
            let jitter = (sin(block * 12.9898) + 1.0) * 0.5
            let period = 3.2 + 1.6 * jitter
            let t = time.truncatingRemainder(dividingBy: period)
            return t < 0.12 ? 0.1 : 1.0
        case .sleeping, .done, .error:
            return 1.0
        }
    }

    private func computePopScale() -> CGFloat {
        let t = (time.truncatingRemainder(dividingBy: 0.9)) / 0.9
        return CGFloat(1.0 + 0.2 * (0.5 - 0.5 * cos(t * 2.0 * .pi)))
    }

    @ViewBuilder
    private func risingZ(index: Int, x: CGFloat, y: CGFloat, fontSize: CGFloat, delay: Double, text: String) -> some View {
        let cycle = (time - delay).truncatingRemainder(dividingBy: 2.7)
        let raw = cycle < 0 ? cycle + 2.7 : cycle
        let p = raw / 2.7
        let dx = CGFloat(6.0 * p)
        let dy = CGFloat(-16.0 * p)
        let opacity = p < 0.25 ? (p / 0.25) : max(0, 1.0 - (p - 0.25) / 0.75)

        Text(text)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundColor(Color(hex: 0x7C7690))
            .opacity(opacity)
            .position(x: x + dx, y: y + dy)
    }

    @ViewBuilder
    private func pulsingDot(x: CGFloat, y: CGFloat, delay: Double) -> some View {
        let t = (time - delay).truncatingRemainder(dividingBy: 1.2)
        let raw = t < 0 ? t + 1.2 : t
        let p = raw / 1.2
        let opacity = 0.25 + 0.75 * (0.5 - 0.5 * cos(p * 2.0 * .pi))

        Circle()
            .fill(Color(hex: 0xA78BFA))
            .frame(width: 5, height: 5)
            .opacity(reduceMotion ? 1.0 : opacity)
            .position(x: x, y: y)
    }

    @ViewBuilder
    private func confetti(startX: CGFloat, startY: CGFloat, dx: CGFloat, dy: CGFloat, color: Color, delay: Double) -> some View {
        let t = (time - delay).truncatingRemainder(dividingBy: 1.0)
        let raw = t < 0 ? t + 1.0 : t
        let p = CGFloat(raw / 1.0)
        let currX = startX + dx * p
        let currY = startY + dy * p
        let rot = Double(180.0 * p)
        let opacity = Double(1.0 - p)

        RoundedRectangle(cornerRadius: 1)
            .fill(color)
            .frame(width: 5, height: 8)
            .rotationEffect(.degrees(rot))
            .opacity(opacity)
            .position(x: currX, y: currY)
    }

    @ViewBuilder
    private func smokePuff(x: CGFloat, y: CGFloat, r: CGFloat, delay: Double) -> some View {
        let t = (time - delay).truncatingRemainder(dividingBy: 2.7)
        let raw = t < 0 ? t + 2.7 : t
        let p = raw / 2.7
        let dx = CGFloat(6.0 * p)
        let dy = CGFloat(-16.0 * p)
        let opacity = p < 0.25 ? (p / 0.25) : max(0, 1.0 - (p - 0.25) / 0.75)

        Circle()
            .fill(Color(hex: 0xB4B2A9))
            .frame(width: r * 2, height: r * 2)
            .opacity(opacity)
            .position(x: x + dx, y: y + dy)
    }
}

#Preview("Bolt States") {
    HStack(spacing: 20) {
        ForEach(AgentState.allCases, id: \.self) { state in
            VStack(spacing: 8) {
                BoltView(state: state, size: 60)
                Text(state.rawValue)
                    .font(.caption)
                    .foregroundColor(.white)
            }
        }
    }
    .padding(30)
    .background(Color(hex: 0x1B1B1F))
}
