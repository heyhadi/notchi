import SwiftUI
import NotchBuddyCore

// MARK: - Public API

enum AvatarKind: String, CaseIterable, Identifiable {
    case bolt, mochi, goo, boo, tofu, sprout, ember, nimbus, inky, bun, byte, quack
    var id: String { rawValue }
    /// Each agent starts with a different avatar so "one per agent" is visible before anyone picks.
    static func defaultFor(_ a: AgentKind) -> AvatarKind { allCases[(AgentKind.allCases.firstIndex(of: a) ?? 0) % allCases.count] }
    var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

struct AvatarView: View {
    let kind: AvatarKind
    let state: AgentState
    let size: CGFloat

    var body: some View {
        if kind == .bolt {
            BoltView(state: state, size: size)
        } else {
            PortedAvatar(spec: AvatarSpec.all[kind] ?? AvatarSpec.mochi, state: state, size: size)
        }
    }
}

private struct PortedAvatar: View {
    let spec: AvatarSpec
    let state: AgentState
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastStateChange = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0.0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, _ in
                var c = ctx
                c.scaleBy(x: size / 120, y: size / 120)
                Painter(a: spec, state: state, time: time, reduce: reduceMotion).paint(&c)
            }
            .frame(width: size, height: size)
            .scaleEffect(startle(time))
        }
        .onChange(of: state) { lastStateChange = Date() }
    }

    // 180 ms pop on state change (same as Bolt)
    private func startle(_ time: Double) -> CGFloat {
        guard !reduceMotion else { return 1 }
        let e = time - lastStateChange.timeIntervalSinceReferenceDate
        guard e >= 0, e < 0.18 else { return 1 }
        let p = e / 0.18
        return CGFloat(1.12 - 0.12 * (1 - (1 - p) * (1 - p)))
    }
}

// MARK: - Spec model

private enum Idle { case float, squash, sway, flicker }

private struct Part {
    var path: Path
    var fill: UInt32?
    var op = 1.0
    var stroke: UInt32?
    var sw: CGFloat = 0
}

private struct Layer {
    var idle: [Idle] = []
    var origin = CGPoint(x: 60, y: 100)   // pivot for .sway
    var parts: [Part]
    var face = false                       // state face is drawn on top of this layer
}

struct AvatarSpec {
    fileprivate var shadow: Part?
    var ground: CGFloat                    // bottom y: anchor for squash / hop / wobble
    fileprivate var layers: [Layer]
    var eyeX: (CGFloat, CGFloat)           // eye centres (pixel: left edges)
    var eyeY: CGFloat
    var erx: CGFloat
    var ery: CGFloat
    var mouth: CGPoint
    var mouthHalf: CGFloat = 4.5
    var pixel = false
}

// MARK: - Part builders

private func P(_ d: String, _ fill: UInt32? = nil, _ op: Double = 1, stroke: UInt32? = nil, sw: CGFloat = 0) -> Part {
    Part(path: svgPath(d), fill: fill, op: op, stroke: stroke, sw: sw)
}
private func O(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ fill: UInt32?, _ op: Double = 1,
               stroke: UInt32? = nil, sw: CGFloat = 0) -> Part {
    Part(path: Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry)),
         fill: fill, op: op, stroke: stroke, sw: sw)
}
private func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ fill: UInt32, _ op: Double = 1) -> Part {
    Part(path: Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r), fill: fill, op: op)
}

/// Minimal SVG path parser: M L H V C Q A Z absolute, h v relative.
/// shortcut: arcs assume sweep=1 and large-arc=0 (all the avatars need); extend if a new SVG uses others.
private func svgPath(_ d: String) -> Path {
    var toks: [String] = [], num = ""
    func flush() { if !num.isEmpty { toks.append(num); num = "" } }
    for ch in d {
        if ch.isLetter { flush(); toks.append(String(ch)) }
        else if ch == " " || ch == "," { flush() }
        else if ch == "-" { flush(); num = "-" }
        else { num.append(ch) }
    }
    flush()
    var p = Path(), cur = CGPoint.zero, start = CGPoint.zero, i = 0, cmd = "M"
    func n() -> CGFloat { defer { i += 1 }; return CGFloat(Double(toks[i]) ?? 0) }
    func pt() -> CGPoint { let x = n(); let y = n(); return CGPoint(x: x, y: y) }
    while i < toks.count {
        if toks[i].first!.isLetter { cmd = toks[i]; i += 1 }
        switch cmd {
        case "M": cur = pt(); start = cur; p.move(to: cur); cmd = "L"
        case "L": cur = pt(); p.addLine(to: cur)
        case "H": cur.x = n(); p.addLine(to: cur)
        case "V": cur.y = n(); p.addLine(to: cur)
        case "h": cur.x += n(); p.addLine(to: cur)
        case "v": cur.y += n(); p.addLine(to: cur)
        case "C": let c1 = pt(), c2 = pt(), e = pt(); p.addCurve(to: e, control1: c1, control2: c2); cur = e
        case "Q": let c1 = pt(), e = pt(); p.addQuadCurve(to: e, control: c1); cur = e
        case "A":
            let r0 = n(); _ = n(); _ = n(); _ = n(); _ = n()
            let e = pt()
            let dx = e.x - cur.x, dy = e.y - cur.y, dd = hypot(dx, dy)
            let r = max(r0, dd / 2), h = sqrt(max(0, r * r - dd * dd / 4))
            let c = CGPoint(x: (cur.x + e.x) / 2 - h * dy / dd, y: (cur.y + e.y) / 2 + h * dx / dd)
            let a0 = atan2(cur.y - c.y, cur.x - c.x)
            var a1 = atan2(e.y - c.y, e.x - c.x)
            if a1 <= a0 { a1 += 2 * .pi }
            let segs = max(1, Int(ceil((a1 - a0) / (.pi / 2))))
            let step = (a1 - a0) / CGFloat(segs), k = 4 / 3 * tan(step / 4) * r
            for s in 0..<segs {
                let t0 = a0 + step * CGFloat(s), t1 = t0 + step
                p.addCurve(to: CGPoint(x: c.x + r * cos(t1), y: c.y + r * sin(t1)),
                           control1: CGPoint(x: c.x + r * cos(t0) - k * sin(t0), y: c.y + r * sin(t0) + k * cos(t0)),
                           control2: CGPoint(x: c.x + r * cos(t1) + k * sin(t1), y: c.y + r * sin(t1) - k * cos(t1)))
            }
            cur = e
        case "Z", "z": p.closeSubpath(); cur = start
        default: i += 1
        }
    }
    return p
}

// MARK: - The 11 avatars (geometry ported 1:1 from Avatar.dc.html, eyes/mouth removed)

extension AvatarSpec {
    private static let pinkC: UInt32 = 0xFF8FB1

    static let mochi = AvatarSpec(
        shadow: O(60, 113, 30, 4, 0x1B1B1F, 0.1), ground: 109,
        layers: [
            Layer(idle: [.sway], origin: CGPoint(x: 97, y: 100),
                  parts: [P("M90 100 Q114 94 104 68", stroke: 0xF7C3A3, sw: 9)]),
            Layer(idle: [.squash], parts: [
                P("M28 56 L34 20 L56 40 Z", 0xFFD6BD), P("M92 56 L86 20 L64 40 Z", 0xFFD6BD),
                P("M35 44 L38 29 L48 39 Z", 0xFF9EB5), P("M85 44 L82 29 L72 39 Z", 0xFF9EB5),
                O(60, 74, 40, 35, 0xFFD6BD), O(60, 90, 22, 14, 0xFFF3EA),
                P("M58 72 L62 72 L60 74.5 Z", 0xFF7A9A),
                P("M22 72 L33 74 M22 79 L33 78 M98 72 L87 74 M98 79 L87 78", stroke: 0xC98F6E, sw: 1.6),
                O(38, 76, 5, 3, pinkC, 0.8), O(82, 76, 5, 3, pinkC, 0.8),
            ], face: true),
        ],
        eyeX: (46, 74), eyeY: 66, erx: 5, ery: 6.5, mouth: CGPoint(x: 60, y: 78))

    static let goo = AvatarSpec(
        shadow: O(60, 110, 36, 4, 0x1B1B1F, 0.1), ground: 104,
        layers: [
            Layer(idle: [.squash], parts: [
                P("M20 102 C20 60 36 30 60 30 C84 30 100 60 100 102 Q90 110 80 102 Q70 112 60 102 Q50 112 40 102 Q30 110 20 102 Z", 0x5AB8FF),
                O(42, 48, 8, 5, 0xFFFFFF, 0.6), O(80, 44, 2.5, 2.5, 0xFFFFFF, 0.6),
                O(37, 79, 5, 3, pinkC, 0.9), O(83, 79, 5, 3, pinkC, 0.9),
            ], face: true),
        ],
        eyeX: (48, 72), eyeY: 68, erx: 5, ery: 6.5, mouth: CGPoint(x: 60, y: 81))

    static let boo = AvatarSpec(
        shadow: O(60, 114, 22, 3.5, 0x1B1B1F, 0.08), ground: 106,
        layers: [
            Layer(idle: [.float], parts: [
                P("M28 98 V56 A32 32 0 0 1 92 56 V98 Q84 90 76 98 Q68 106 60 98 Q52 90 44 98 Q36 106 28 98 Z",
                  0xFFFFFF, stroke: 0xCFC6F2, sw: 2)]),
            Layer(idle: [.float, .sway], origin: CGPoint(x: 24, y: 79),
                  parts: [O(24, 70, 6, 9, 0xFFFFFF, stroke: 0xCFC6F2, sw: 2)]),
            Layer(idle: [.float], parts: [O(38, 70, 5, 3, pinkC, 0.7), O(82, 70, 5, 3, pinkC, 0.7)], face: true),
        ],
        eyeX: (48, 72), eyeY: 60, erx: 5, ery: 6.5, mouth: CGPoint(x: 60, y: 74))

    static let tofu = AvatarSpec(
        shadow: O(60, 108, 34, 4, 0x1B1B1F, 0.1), ground: 104,
        layers: [
            Layer(idle: [.squash], parts: [
                R(24, 36, 72, 68, 20, 0xFFE58A), R(34, 43, 30, 7, 3.5, 0xFFFFFF, 0.6),
                P("M98 30 Q104 40 98 45 Q92 40 98 30 Z", 0x5AB8FF),
                O(36, 80, 5, 3, pinkC, 0.8), O(84, 80, 5, 3, pinkC, 0.8),
            ], face: true),
        ],
        eyeX: (47, 73), eyeY: 68, erx: 5, ery: 6.5, mouth: CGPoint(x: 60, y: 82))

    static let sprout = AvatarSpec(
        shadow: O(60, 110, 26, 4, 0x1B1B1F, 0.1), ground: 106,
        layers: [
            Layer(idle: [.sway], origin: CGPoint(x: 60, y: 68), parts: [
                P("M60 68 V42", stroke: 0x3F9E45, sw: 4),
                P("M60 50 C46 50 36 38 38 26 C51 26 60 36 60 50 Z", 0x6DD36A),
                P("M60 44 C73 44 84 33 82 20 C69 20 60 30 60 44 Z", 0x4CC24A),
            ]),
            Layer(parts: [
                P("M34 74 H86 L80 106 H40 Z", 0xE8875A), R(30, 66, 60, 12, 6, 0xF29C6F),
                O(42, 96, 4, 2.5, pinkC, 0.9), O(78, 96, 4, 2.5, pinkC, 0.9),
            ], face: true),
        ],
        eyeX: (50, 70), eyeY: 88, erx: 4.5, ery: 6, mouth: CGPoint(x: 60, y: 98), mouthHalf: 4)

    static let ember = AvatarSpec(
        shadow: O(60, 112, 26, 4, 0x1B1B1F, 0.1), ground: 106,
        layers: [
            Layer(idle: [.flicker], parts: [
                P("M60 16 C70 34 92 46 90 74 C88 96 74 106 60 106 C46 106 32 96 30 76 C29 60 40 52 44 40 C48 50 52 54 56 54 C54 40 54 30 60 16 Z", 0xFF7A45),
                P("M60 52 C66 62 77 68 76 82 C75 94 67 101 60 101 C53 101 45 94 44 84 C44 74 54 68 60 52 Z", 0xFFC145),
                // cheeks added: the SVG has none, but they must always show
                O(46, 90, 3.5, 2.2, pinkC, 0.9), O(74, 90, 3.5, 2.2, pinkC, 0.9),
            ], face: true),
        ],
        eyeX: (51, 69), eyeY: 80, erx: 4.5, ery: 6, mouth: CGPoint(x: 60, y: 91.5), mouthHalf: 4)

    static let nimbus = AvatarSpec(
        shadow: nil, ground: 96,
        layers: [
            Layer(idle: [.float], parts: [
                P("M30 86 A16 16 0 0 1 32 54 A22 22 0 0 1 72 44 A18 18 0 0 1 98 64 A12 12 0 0 1 92 86 Z",
                  0xFFFFFF, stroke: 0xBFDDED, sw: 2),
                O(43, 76, 4.5, 2.6, pinkC, 0.8), O(81, 76, 4.5, 2.6, pinkC, 0.8),
            ], face: true),
            Layer(parts: [
                P("M48 96 Q52 104 48 108 Q44 104 48 96 Z", 0x5AB8FF),
                P("M74 98 Q78 106 74 110 Q70 106 74 98 Z", 0x5AB8FF),
            ]),
        ],
        eyeX: (52, 72), eyeY: 68, erx: 4.5, ery: 6, mouth: CGPoint(x: 62, y: 78.5), mouthHalf: 4)

    static let inky = AvatarSpec(
        shadow: O(60, 113, 30, 4, 0x1B1B1F, 0.1), ground: 108,
        layers: [
            Layer(idle: [.sway], origin: CGPoint(x: 60, y: 78), parts: [
                P("M36 78 Q30 98 40 106", stroke: 0xA78BFA, sw: 9), P("M52 82 Q48 102 56 108", stroke: 0xA78BFA, sw: 9),
                P("M68 82 Q72 102 64 108", stroke: 0xA78BFA, sw: 9), P("M84 78 Q90 98 80 106", stroke: 0xA78BFA, sw: 9),
            ]),
            Layer(idle: [.float], parts: [
                O(60, 58, 34, 32, 0xA78BFA), O(44, 40, 4, 4, 0xC4B1FF), O(77, 36, 3, 3, 0xC4B1FF),
                O(37, 70, 5, 3, pinkC, 0.9), O(83, 70, 5, 3, pinkC, 0.9),
            ], face: true),
        ],
        eyeX: (48, 72), eyeY: 60, erx: 5, ery: 6.5, mouth: CGPoint(x: 60, y: 73))

    static let bun = AvatarSpec(
        shadow: O(60, 112, 30, 4, 0x1B1B1F, 0.1), ground: 110,
        layers: [
            Layer(idle: [.squash], parts: [
                O(46, 32, 9, 24, 0xFFFFFF, stroke: 0xF4C7D6, sw: 2), O(46, 34, 4, 16, 0xFFB8CC)]),
            Layer(idle: [.squash, .sway], origin: CGPoint(x: 76, y: 56), parts: [
                O(76, 32, 9, 24, 0xFFFFFF, stroke: 0xF4C7D6, sw: 2), O(76, 34, 4, 16, 0xFFB8CC)]),
            Layer(idle: [.squash], parts: [
                O(60, 80, 36, 30, 0xFFFFFF, stroke: 0xF4C7D6, sw: 2), O(60, 84, 3, 2, 0xFF7A9A),
                O(38, 86, 5, 3, pinkC, 0.8), O(82, 86, 5, 3, pinkC, 0.8),
            ], face: true),
        ],
        eyeX: (48, 72), eyeY: 76, erx: 5, ery: 6.5, mouth: CGPoint(x: 60, y: 89), mouthHalf: 4)

    static let byte = AvatarSpec(
        shadow: R(36, 106, 48, 4, 0, 0x1B1B1F, 0.1), ground: 94,
        layers: [
            Layer(idle: [.float], parts: [
                P("M32 30h8v8h-8z M80 30h8v8h-8z M40 38h8v8h-8z M72 38h8v8h-8z M32 46h56v8h-56z M24 54h16v8h-16z M48 54h24v8h-24z M80 54h16v8h-16z M16 62h88v8h-88z M16 70h8v8h-8z M32 70h56v8h-56z M96 70h8v8h-8z M16 78h8v8h-8z M32 78h8v8h-8z M80 78h8v8h-8z M96 78h8v8h-8z M40 86h16v8h-16z M64 86h16v8h-16z",
                  0x5B6CFF),
                // fill the eye sockets so smaller state eyes do not leave holes
                R(40, 54, 8, 8, 0, 0x5B6CFF), R(72, 54, 8, 8, 0, 0x5B6CFF),
                R(32, 70, 8, 8, 0, pinkC), R(80, 70, 8, 8, 0, pinkC),
            ], face: true),
        ],
        eyeX: (40, 72), eyeY: 54, erx: 4, ery: 4, mouth: CGPoint(x: 60, y: 74), pixel: true)

    static let quack = AvatarSpec(
        shadow: O(62, 110, 34, 4, 0x1B1B1F, 0.1), ground: 107,
        layers: [
            Layer(idle: [.squash], parts: [
                P("M94 72 L110 58 L104 84 Z", 0xFFD84D), O(62, 82, 38, 25, 0xFFD84D), O(50, 50, 24, 24, 0xFFD84D)]),
            Layer(idle: [.squash, .sway], origin: CGPoint(x: 74, y: 92), parts: [O(74, 82, 16, 10, 0xF5C21B)]),
            Layer(idle: [.squash], parts: [
                P("M14 54 Q24 45 33 51 Q24 60 14 54 Z", 0xFF9A3C),
                O(38, 57, 4.5, 2.6, pinkC, 0.9), O(64, 57, 4.5, 2.6, pinkC, 0.9),
            ], face: true),
        ],
        eyeX: (42, 58), eyeY: 46, erx: 4.5, ery: 6, mouth: CGPoint(x: 50, y: 59), mouthHalf: 4)

    static let all: [AvatarKind: AvatarSpec] = [
        .mochi: mochi, .goo: goo, .boo: boo, .tofu: tofu, .sprout: sprout, .ember: ember,
        .nimbus: nimbus, .inky: inky, .bun: bun, .byte: byte, .quack: quack,
    ]
}

// MARK: - Painter

private extension GraphicsContext {
    /// CSS-style transform about `o`: translate, then rotate and scale around the pivot.
    mutating func pivot(_ o: CGPoint, dx: CGFloat = 0, dy: CGFloat = 0, rot: Double = 0, sx: CGFloat = 1, sy: CGFloat = 1) {
        translateBy(x: o.x + dx, y: o.y + dy)
        rotate(by: .degrees(rot))
        scaleBy(x: sx, y: sy)
        translateBy(x: -o.x, y: -o.y)
    }
    func oval(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ col: Color) {
        fill(Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry)), with: .color(col))
    }
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ col: Color) {
        fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(col))
    }
    func ink(_ p: Path, _ col: Color, _ w: CGFloat) {
        stroke(p, with: .color(col), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
    }
}

private struct Painter {
    let a: AvatarSpec
    let state: AgentState
    let time: Double
    let reduce: Bool

    private let ink = Color(hex: 0x1B1B1F)
    private let mouthPink = Color(hex: 0xFF6B8F)

    func paint(_ ctx: inout GraphicsContext) {
        if let s = a.shadow { draw(s, ctx) }
        var body = ctx
        stateTransform(&body)
        for layer in a.layers {
            var l = body
            for i in layer.idle { idle(i, layer, &l) }
            for p in layer.parts { draw(p, l) }
            if layer.face { a.pixel ? pixelFace(l) : roundFace(l) }
        }
        overlays(ctx)
    }

    private func draw(_ p: Part, _ c: GraphicsContext) {
        if let f = p.fill { c.fill(p.path, with: .color(Color(hex: f, opacity: p.op))) }
        if let s = p.stroke { c.ink(p.path, Color(hex: s), p.sw) }
    }

    // MARK: Timing helpers

    private func wave(_ period: Double) -> Double { 0.5 - 0.5 * cos(2 * .pi * time / period) }
    private func cycle(_ period: Double, _ delay: Double = 0) -> Double {
        let r = (time - delay).truncatingRemainder(dividingBy: period)
        return (r < 0 ? r + period : r) / period
    }
    private func keys(_ p: Double, _ ks: [(Double, [Double])]) -> [Double] {
        for i in 1..<ks.count where p <= ks[i].0 {
            let (p0, v0) = ks[i - 1], (p1, v1) = ks[i]
            let t = (p - p0) / (p1 - p0)
            return zip(v0, v1).map { $0 + ($1 - $0) * t }
        }
        return ks.last!.1
    }

    // MARK: Motion

    /// State motion on the whole character; it dominates the idle personality.
    private func stateTransform(_ c: inout GraphicsContext) {
        guard !reduce else { return }
        let o = CGPoint(x: 60, y: a.ground)
        switch state {
        case .sleeping:   // 4 s breathing
            let w = wave(4)
            c.pivot(o, sx: 1 + 0.02 * w, sy: 1 + 0.04 * w)
        case .thinking:   // personality idle only
            break
        case .working:    // 0.5 s bob
            c.pivot(o, dy: -3 * wave(0.5))
        case .needsYou:   // 0.9 s hop
            let v = keys(cycle(0.9), [(0, [0, 0]), (0.3, [-10, -4]), (0.6, [0, 4]), (1, [0, 0])])
            c.pivot(o, dy: v[0], rot: v[1])
        case .done:       // 1 s squash-and-stretch jump
            let v = keys(cycle(1), [(0, [0, 1.08, 0.92]), (0.4, [-12, 0.94, 1.08]), (0.6, [-12, 1, 1]), (1, [0, 1.08, 0.92])])
            c.pivot(o, dy: v[0], sx: v[1], sy: v[2])
        case .error:      // wobble +-6 deg, 1.2 s
            c.pivot(o, rot: -6 + 12 * wave(1.2))
        }
    }

    private func idle(_ i: Idle, _ l: Layer, _ c: inout GraphicsContext) {
        guard !reduce else { return }
        let big = state == .thinking ? 1.0 : 0.0                                  // float / squash only while thinking
        let small = state == .sleeping ? 0.0 : (state == .thinking ? 1.0 : 0.5)  // sway / flicker are quieter
        let g = CGPoint(x: 60, y: a.ground)
        switch i {
        case .float: c.pivot(g, dy: -5 * wave(2.6) * big)
        case .squash:
            let w = wave(1.8) * big
            c.pivot(g, sx: 1 + 0.06 * w, sy: 1 - 0.06 * w)
        case .sway: c.pivot(l.origin, rot: 7 * sin(2 * .pi * time / 2.2) * small)
        case .flicker:
            let w = wave(0.9) * small
            c.pivot(g, sx: 1 - 0.03 * w, sy: 1 + 0.06 * w)
        }
    }

    private func blink() -> CGFloat {
        guard !reduce, state == .thinking || state == .working || state == .needsYou else { return 1 }
        let jitter = (sin(floor(time / 4) * 12.9898) + 1) * 0.5
        let period = 3.2 + 1.6 * jitter
        return time.truncatingRemainder(dividingBy: period) < 0.12 ? 0.1 : 1
    }

    // MARK: Faces

    private func roundFace(_ c: GraphicsContext) {
        let xs = [a.eyeX.0, a.eyeX.1], y = a.eyeY, rx = a.erx, ry = a.ery, m = a.mouth, hw = a.mouthHalf
        var e = c
        e.pivot(CGPoint(x: 60, y: y), sy: blink())
        switch state {
        case .sleeping:
            for x in xs {
                var p = Path(); p.move(to: CGPoint(x: x - rx - 1, y: y))
                p.addQuadCurve(to: CGPoint(x: x + rx + 1, y: y), control: CGPoint(x: x, y: y + 6))
                c.ink(p, ink, 3)
            }
            c.oval(m.x, m.y, 2.4, 1.8, ink)
        case .thinking:
            for x in xs { e.oval(x, y - 2.5, rx, ry, ink); e.oval(x + 1.8, y - 6, 1.7, 1.7, .white) }
            var p = Path(); p.move(to: CGPoint(x: m.x - hw + 1, y: m.y)); p.addLine(to: CGPoint(x: m.x + hw - 1, y: m.y))
            c.ink(p, ink, 2.6)
        case .working:
            for x in xs { e.oval(x, y + 1.5, rx, ry * 0.85, ink); e.oval(x + 1.6, y - 0.8, 1.3, 1.3, .white) }
            var p = Path(); p.move(to: CGPoint(x: m.x - 3.5, y: m.y))
            p.addQuadCurve(to: CGPoint(x: m.x + 3.5, y: m.y), control: CGPoint(x: m.x, y: m.y + 2.5))
            c.ink(p, ink, 2.6)
        case .needsYou:
            let r = max(rx, ry) + 2.5
            for x in xs { e.oval(x, y - 0.5, r, r, ink); e.oval(x + 2.4, y - 3.5, 2.3, 2.3, .white) }
            c.oval(m.x, m.y + 1, 3.2, 4.2, ink)
        case .done:
            for x in xs {
                var p = Path(); p.move(to: CGPoint(x: x - rx - 0.5, y: y + 2.5))
                p.addQuadCurve(to: CGPoint(x: x + rx + 0.5, y: y + 2.5), control: CGPoint(x: x, y: y - 6.5))
                c.ink(p, ink, 3.2)
            }
            var p = Path(); p.move(to: CGPoint(x: m.x - hw - 1, y: m.y - 0.5))
            p.addQuadCurve(to: CGPoint(x: m.x + hw + 1, y: m.y - 0.5), control: CGPoint(x: m.x, y: m.y + 10))
            p.closeSubpath()
            c.fill(p, with: .color(mouthPink)); c.ink(p, ink, 1.4)
        case .error:
            let spin = reduce ? 0 : time.truncatingRemainder(dividingBy: 1) * 360
            for x in xs {
                var s = c
                s.pivot(CGPoint(x: x, y: y), rot: spin)
                let r = max(rx, ry) - 0.8
                s.stroke(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(ink),
                         style: StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [7, 3.5]))
                c.oval(x, y, 1.2, 1.2, ink)
            }
            var p = Path(); p.move(to: CGPoint(x: m.x - 6, y: m.y))
            p.addQuadCurve(to: m, control: CGPoint(x: m.x - 3, y: m.y - 3.5))
            p.addQuadCurve(to: CGPoint(x: m.x + 6, y: m.y), control: CGPoint(x: m.x + 3, y: m.y + 3.5))
            c.ink(p, ink, 2.6)
        }
    }

    /// Byte: square pixel eyes and mouth, crisp rects only.
    private func pixelFace(_ c: GraphicsContext) {
        let xs = [a.eyeX.0, a.eyeX.1], y = a.eyeY, m = a.mouth
        var e = c
        e.pivot(CGPoint(x: 60, y: y + 4), sy: blink())
        switch state {
        case .sleeping:
            for x in xs { c.rect(x, y + 5, 8, 3, ink) }
            c.rect(m.x - 2, m.y - 1, 4, 3, ink)
        case .thinking:
            for x in xs { e.rect(x, y - 2, 8, 8, ink); e.rect(x + 4, y - 1, 3, 3, .white) }
            c.rect(m.x - 6, m.y - 1, 12, 3, ink)
        case .working:
            for x in xs { e.rect(x, y + 2, 8, 6, ink) }
            c.rect(m.x - 4, m.y - 1, 8, 3, ink)
        case .needsYou:
            for x in xs { e.rect(x - 2, y - 2, 12, 12, ink); e.rect(x + 4.5, y, 4, 4, .white) }
            c.rect(m.x - 3, m.y - 3, 6, 7, ink)
        case .done:
            for x in xs {
                c.rect(x, y + 5, 2.7, 3, ink); c.rect(x + 2.7, y + 2, 2.6, 3, ink); c.rect(x + 5.3, y + 5, 2.7, 3, ink)
            }
            c.rect(m.x - 7, m.y - 2, 14, 7, ink)
            c.rect(m.x - 6, m.y - 1, 12, 5, mouthPink)
        case .error:
            let plus = !reduce && cycle(0.6) >= 0.5
            let dots: [(CGFloat, CGFloat)] = plus
                ? [(2.5, 0), (0, 2.5), (2.5, 2.5), (5, 2.5), (2.5, 5)]
                : [(0, 0), (5, 0), (2.5, 2.5), (0, 5), (5, 5)]
            for x in xs { for d in dots { c.rect(x + d.0, y + d.1 + 1, 3, 3, ink) } }
            for (i, dy) in [3, 0, 3, 0].enumerated() { c.rect(m.x - 8 + CGFloat(i) * 4, m.y - 2 + CGFloat(dy), 4, 3, ink) }
        }
    }

    // MARK: Overlays (not affected by body motion)

    private func overlays(_ ctx: GraphicsContext) {
        let ring = Color(hex: 0xD9CFFF)
        switch state {
        case .sleeping where !reduce:
            for (x, y, fs, d, t) in [(92.0, 30.0, 12.0, 0.0, "z"), (98, 22, 14, 0.9, "z"), (104, 14, 16, 1.8, "Z")] {
                let p = cycle(2.7, d)
                var c = ctx
                c.opacity = p < 0.25 ? p / 0.25 : max(0, 1 - (p - 0.25) / 0.75)
                c.draw(Text(t).font(.system(size: fs, weight: .bold, design: .rounded)).foregroundColor(Color(hex: 0x7C7690)),
                       at: CGPoint(x: x + 6 * p, y: y - 16 * p))
            }
        case .thinking:
            ctx.oval(94, 26, 2.5, 2.5, .white)
            ctx.ink(Path(ellipseIn: CGRect(x: 91.5, y: 23.5, width: 5, height: 5)), ring, 1.5)
            let bubble = Path(roundedRect: CGRect(x: 84, y: 2, width: 34, height: 18), cornerRadius: 9)
            ctx.fill(bubble, with: .color(.white)); ctx.ink(bubble, ring, 1.5)
            for (i, x) in [93.0, 101, 109].enumerated() {
                var c = ctx
                c.opacity = reduce ? 1 : 0.25 + 0.75 * (0.5 - 0.5 * cos(2 * .pi * cycle(1.2, 0.2 * Double(i))))
                c.oval(x, 11, 2.5, 2.5, Color(hex: 0xA78BFA))
            }
        case .needsYou:
            var c = ctx
            let s = reduce ? 1 : 1 + 0.2 * wave(0.9)
            c.pivot(CGPoint(x: 102, y: 20), sx: s, sy: s)
            c.oval(102, 20, 12, 12, Color(hex: 0xFFB020))
            c.draw(Text("!").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundColor(Color(hex: 0x3D2600)),
                   at: CGPoint(x: 102, y: 20))
        case .done where !reduce:
            let bits: [(CGFloat, CGFloat, CGFloat, CGFloat, UInt32, Double)] = [
                (18, 36, -12, -22, 0xFFB020, 0), (98, 34, 12, -24, 0xFF8FB1, 0), (28, 16, -8, -20, 0x5AB8FF, 0.2),
                (88, 14, 8, -22, 0x3DDC97, 0.2), (74, 4, 4, -18, 0xA78BFA, 0.4),
            ]
            for b in bits {
                let p = CGFloat(cycle(1, b.5))
                var c = ctx
                c.opacity = Double(1 - p)
                c.translateBy(x: b.0 + b.2 * p, y: b.1 + b.3 * p)
                c.rotate(by: .degrees(Double(180 * p)))
                c.fill(Path(roundedRect: CGRect(x: -2.5, y: -4, width: 5, height: 8), cornerRadius: 1), with: .color(Color(hex: b.4)))
            }
        case .error where !reduce:
            for (x, y, r, d) in [(86.0, 20.0, 5.0, 0.0), (94, 14, 4, 0.7), (80, 12, 3.5, 1.4)] {
                let p = cycle(2.7, d)
                var c = ctx
                c.opacity = p < 0.25 ? p / 0.25 : max(0, 1 - (p - 0.25) / 0.75)
                c.oval(x + 6 * p, y - 16 * p, r, r, Color(hex: 0xB4B2A9))
            }
        default:
            break
        }
    }
}

// MARK: - Preview

#Preview("Avatars x States") {
    VStack(alignment: .leading, spacing: 6) {
        ForEach(AvatarKind.allCases) { kind in
            HStack(spacing: 14) {
                Text(kind.displayName).font(.caption).foregroundColor(.white).frame(width: 52, alignment: .leading)
                ForEach(AgentState.allCases, id: \.self) { s in
                    AvatarView(kind: kind, state: s, size: 56)
                }
                AvatarView(kind: kind, state: .working, size: 30)
            }
        }
    }
    .padding(20)
    .background(Color(hex: 0x1B1B1F))
}
