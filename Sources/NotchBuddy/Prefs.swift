import Foundation
import NotchBuddyCore

/// UserDefaults keys and defaults. Views use `@AppStorage(Prefs.x)`; non-view code reads `Prefs.bool/string/double`.
enum Prefs {
    static let language = "language"            // "en" | "id"
    static let avatar = "avatar"                // "bolt" (others in a later phase)
    static let openOnHover = "openOnHover"      // Bool, default true
    static let holdForReply = "holdForReply"    // Bool, default false: hold every finished turn so you can reply from the notch
    static let soundsOn = "soundsOn"            // Bool, default false (sounds are opt-in)
    static let volume = "volume"                // Double 0...1, default 0.6
    static let soundPack = "soundPack"          // "soft" | "retro" | "chirpy"
    static let muteWhenBusy = "muteWhenBusy"    // Bool, default true: mute while the mic is in use (calls, meetings)
    static func sound(for s: AgentState) -> String { "sound.\(s.rawValue)" } // SoundName raw value

    static func register() {
        var d: [String: Any] = [language: "en", avatar: "bolt", openOnHover: true, holdForReply: false, soundsOn: false,
                                volume: 0.6, soundPack: "soft", muteWhenBusy: true]
        for s in AgentState.allCases { d[sound(for: s)] = SoundName.default(for: s).rawValue }
        UserDefaults.standard.register(defaults: d)
    }
}

/// The sound a state plays. Raw values are stored in UserDefaults.
enum SoundName: String, CaseIterable, Identifiable {
    case off, softTick, beepBeep, ding, bwomp
    var id: String { rawValue }

    static func `default`(for s: AgentState) -> SoundName {
        switch s {
        case .sleeping, .thinking: .off
        case .working: .softTick
        case .needsYou: .beepBeep
        case .done: .ding
        case .error: .bwomp
        }
    }

    var title: String {
        switch self {
        case .off: L("Off")
        case .softTick: L("Soft tick")
        case .beepBeep: L("Beep-beep")
        case .ding: L("Ding")
        case .bwomp: L("Bwomp")
        }
    }
}
