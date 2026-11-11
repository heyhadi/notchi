import Foundation

/// The six shared avatar states. Raw order is display order; `priority` decides what the notch shows.
public enum AgentState: String, CaseIterable, Codable, Sendable {
    case sleeping, thinking, working, needsYou, done, error

    /// Higher wins: Needs you > Error > Done > Working > Thinking > Sleeping.
    public var priority: Int {
        switch self {
        case .sleeping: 0
        case .thinking: 1
        case .working: 2
        case .done: 3
        case .error: 4
        case .needsYou: 5
        }
    }

    /// State color as 0xRRGGBB (design tokens).
    public var colorHex: UInt32 {
        switch self {
        case .sleeping: 0xB9B4C9
        case .thinking: 0xA78BFA
        case .working: 0x3DDC97
        case .needsYou: 0xFFB020
        case .done: 0x5AB8FF
        case .error: 0xFF6B6B
        }
    }

    /// The state the notch shows for a set of sessions.
    public static func top(_ states: some Sequence<AgentState>) -> AgentState {
        states.max { $0.priority < $1.priority } ?? .sleeping
    }
}
