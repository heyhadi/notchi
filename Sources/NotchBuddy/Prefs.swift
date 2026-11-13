import Foundation
import NotchBuddyCore

/// UserDefaults keys and defaults. Views use `@AppStorage(Prefs.x)`; non-view code reads `Prefs.bool/string/double`.
enum Prefs {
    static let language = "language"            // "en" | "id"
    static let avatar = "avatar"                // "bolt" (others in a later phase)
    static let openOnHover = "openOnHover"      // Bool, default true
    static let holdForReply = "holdForReply"    // Bool, default false: hold every finished turn so you can reply from the notch
    static let glow = "glow"                    // Bool, default true: moving light around the notch edge while agents are active
    static let soundsOn = "soundsOn"            // Bool, default false (sounds are opt-in)
    static let volume = "volume"                // Double 0...1, default 0.6
    static let soundPack = "soundPack"          // "soft" | "retro" | "chirpy" | "robot"
    static let dailyTokenLimitM = "dailyTokenLimitM" // Int, millions of tokens per day, 0 = off (Claude Code only)
    static let limitAlertDay = "limitAlertDay"  // "yyyy-MM-dd" of the last limit alert, so it fires once a day
    static let roam = "roam"                    // Bool, default false: the avatar also walks along the bottom of the screen while an agent is busy
    static let avatarPerAgent = "avatarPerAgent" // Bool, default false: the avatar follows the agent that is driving the notch
    static func avatarKey(for a: AgentKind) -> String { "avatar.\(a.rawValue)" }
    static let greetDay = "greetDay"            // "yyyy-MM-dd" of the last good-morning sound
    static let reactionSounds = "reactionSounds" // Bool, default true: little noises for the roaming avatar and chat (still needs sounds on)
    static let muteWhenBusy = "muteWhenBusy"    // Bool, default true: mute while the mic is in use (calls, meetings)
    static let hotkeys = "hotkeys"              // Bool, default true: ⌃⌥N / ⌃⌥A / ⌃⌥D global shortcuts
    static let autoUpdate = "autoUpdate"        // Bool, default true: check GitHub Releases and install new versions when no agent is busy
    static let loginItemSet = "loginItemSet"    // Bool: the released app has added itself as a login item once (the user can turn it off after)
    static func sound(for s: AgentState) -> String { "sound.\(s.rawValue)" } // SoundName raw value

    static func register() {
        var d: [String: Any] = [language: "en", avatar: "bolt", openOnHover: true, holdForReply: false, glow: true, soundsOn: false,
                                volume: 0.6, soundPack: "robot", muteWhenBusy: true, dailyTokenLimitM: 0, roam: false, avatarPerAgent: false, reactionSounds: true, autoUpdate: true, hotkeys: true]
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
