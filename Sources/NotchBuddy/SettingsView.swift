import SwiftUI
import NotchBuddyCore
import ServiceManagement

@MainActor
struct SettingsView: View {
    @AppStorage(Prefs.language) private var language = "en"
    @AppStorage(Prefs.avatar) private var avatar = "bolt"
    @AppStorage(Prefs.openOnHover) private var openOnHover = true
    @AppStorage(Prefs.holdForReply) private var holdForReply = false
    @AppStorage(Prefs.glow) private var glow = true
    @AppStorage(Prefs.soundsOn) private var soundsOn = false
    @AppStorage(Prefs.volume) private var volume = 0.6
    @AppStorage(Prefs.soundPack) private var soundPack = "robot"
    @AppStorage(Prefs.dailyTokenLimitM) private var dailyTokenLimitM = 0
    @AppStorage(Prefs.roam) private var roam = false
    @AppStorage(Prefs.avatarPerAgent) private var avatarPerAgent = false
    @AppStorage(Prefs.muteWhenBusy) private var muteWhenBusy = true
    @AppStorage(Prefs.reactionSounds) private var reactionSounds = true
    @AppStorage(Prefs.autoUpdate) private var autoUpdate = true
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @ObservedObject private var updater = Updater.shared

    @State var selectedTab: SettingsTab = .avatar

    enum SettingsTab: String, CaseIterable, Identifiable {
        case avatar
        case agents
        case behavior
        case sound
        case history
        case privacy
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .avatar: return L("Avatar")
            case .agents: return L("Agents")
            case .behavior: return L("Behavior")
            case .sound: return L("Sound")
            case .history: return L("History")
            case .privacy: return L("Privacy")
            case .about: return L("About")
            }
        }

        var iconName: String {
            switch self {
            case .avatar: return "person.crop.circle"
            case .agents: return "network"
            case .behavior: return "slider.horizontal.3"
            case .sound: return "speaker.wave.2"
            case .history: return "clock.arrow.circlepath"
            case .privacy: return "lock.shield"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            sidebarView
                .frame(width: 170)
                .background(Color(hex: 0xF6F4EF))

            Divider()
                .overlay(Color(hex: 0xE8E5DE))

            // Detail Content
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case .avatar:
                        avatarPane
                    case .agents:
                        agentsPane
                    case .behavior:
                        behaviorPane
                    case .sound:
                        soundPane
                    case .history:
                        HistoryPane()
                    case .privacy:
                        privacyPane
                    case .about:
                        aboutPane
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color(hex: 0xF6F4EF))
        }
        .frame(width: 640, height: 560)
        .preferredColorScheme(.light)
        .id(language)
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                let isSelected = (selectedTab == tab)
                Button(action: {
                    selectedTab = tab
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 14))
                            .frame(width: 20)
                        Text(tab.title)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        Spacer()
                    }
                    .foregroundColor(isSelected ? .white : Color(hex: 0x1B1B1F))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? Color(hex: 0x1B1B1F) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    // MARK: - Avatar Tab

    private struct AvatarItem: Identifiable {
        let id: String
        let name: String
    }

    private let avatarList: [AvatarItem] = [
        AvatarItem(id: "bolt", name: "Bolt"),
        AvatarItem(id: "mochi", name: "Mochi"),
        AvatarItem(id: "goo", name: "Goo"),
        AvatarItem(id: "boo", name: "Boo"),
        AvatarItem(id: "tofu", name: "Tofu"),
        AvatarItem(id: "sprout", name: "Sprout"),
        AvatarItem(id: "ember", name: "Ember"),
        AvatarItem(id: "nimbus", name: "Nimbus"),
        AvatarItem(id: "inky", name: "Inky"),
        AvatarItem(id: "bun", name: "Bun"),
        AvatarItem(id: "byte", name: "Byte"),
        AvatarItem(id: "quack", name: "Quack"),
    ]

    private var avatarPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Pick your buddy"))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: 0x1B1B1F))
                Text(L("Every avatar has the same states. Switch anytime."))
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: 0x5E5D66))
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(avatarList) { item in
                    avatarTile(item)
                }
            }

            if avatarPerAgent {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Avatar per agent")).font(.system(size: 15, weight: .semibold)).foregroundColor(Color(hex: 0x1B1B1F))
                    ForEach(AgentKind.allCases, id: \.self) { AgentAvatarRow(agent: $0) }
                }
            }
        }
    }

    @ViewBuilder
    private func avatarTile(_ item: AvatarItem) -> some View {
        let isSelected = (avatar == item.id)
        Button(action: { avatar = item.id }) {
            VStack(spacing: 6) {
                AvatarView(kind: AvatarKind(rawValue: item.id) ?? .bolt, state: isSelected ? .done : .sleeping, size: 64)
                    .frame(width: 64, height: 64)
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: 0x1B1B1F))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 16).fill(isSelected ? Color(hex: 0xDDF7EC) : Color.white))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color(hex: 0x1E8E66) : Color(hex: 0xEAE7E0), lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Agents Tab

    private var agentsPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Connected agents"))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: 0x1B1B1F))
            }

            VStack(alignment: .leading, spacing: 16) {
                ConnectedAgentsSection()
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0xEAE7E0), lineWidth: 1))

            Text(L("All data stays on this Mac. The only network request is the update check to GitHub, which you can turn off in Behavior."))
                .font(.system(size: 12))
                .foregroundColor(Color(hex: 0x5E5D66))
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Behavior Tab

    private var behaviorPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Behavior"))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: 0x1B1B1F))
            }

            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $openAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Open at login"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: 0x1B1B1F))
                        if let loginError {
                            Text(loginError)
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: 0xD93636))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(Color(hex: 0x1E8E66))
                .onChange(of: openAtLogin) { _, on in setOpenAtLogin(on) }

                Divider().overlay(Color(hex: 0xF0ECE1))

                Toggle(isOn: $openOnHover) {
                    Text(L("Open panel on hover"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: 0x1B1B1F))
                }
                .toggleStyle(.switch)
                .tint(Color(hex: 0x1E8E66))

                Divider().overlay(Color(hex: 0xF0ECE1))

                Toggle(isOn: $glow) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Glow around the notch"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: 0x1B1B1F))
                        Text(L("A moving light runs around the notch while agents work, in the state color when one needs you."))
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: 0x5E5D66))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .tint(Color(hex: 0x1E8E66))

                Divider().overlay(Color(hex: 0xF0ECE1))

                Toggle(isOn: $holdForReply) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Wait for my reply after each turn"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: 0x1B1B1F))
                        Text(L("Finished agents wait up to 10 minutes so you can answer from the notch. Their window shows a running hook meanwhile; press Esc there to skip."))
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: 0x5E5D66))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .tint(Color(hex: 0x1E8E66))

                Divider().overlay(Color(hex: 0xF0ECE1))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Daily token limit"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: 0x1B1B1F))
                        Text(L("In millions of tokens, 0 = off. Today's Claude Code and OpenCode tokens turn amber and the notch bwomps once when you pass it."))
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: 0x5E5D66))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    TextField("0", value: $dailyTokenLimitM, format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 60).multilineTextAlignment(.trailing)
                    Text("M").font(.system(size: 13)).foregroundColor(Color(hex: 0x5E5D66))
                }

                Divider().overlay(Color(hex: 0xF0ECE1))

                Toggle(isOn: $roam) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Allowed to roam the desktop"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: 0x1B1B1F))
                        Text(L("Your avatar walks along the bottom of the screen while an agent is busy. Drag it, poke it, double-click to open the notch."))
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: 0x5E5D66))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .tint(Color(hex: 0x1E8E66))

                Divider().overlay(Color(hex: 0xF0ECE1))

                Toggle(isOn: $avatarPerAgent) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("One avatar per agent"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: 0x1B1B1F))
                        Text(L("The notch shows the avatar of the agent that is busiest right now. Pick each agent's avatar on the Avatar tab."))
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: 0x5E5D66))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .tint(Color(hex: 0x1E8E66))

                Divider().overlay(Color(hex: 0xF0ECE1))

                HStack {
                    Text(L("Language"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: 0x1B1B1F))
                    Spacer()
                    Picker(L("Language"), selection: $language) {
                        Text("English").tag("en")
                        Text("Bahasa Indonesia").tag("id")
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0xEAE7E0), lineWidth: 1))
        }
    }

    private func setOpenAtLogin(_ on: Bool) {
        let svc = SMAppService.mainApp
        guard on != (svc.status == .enabled) else { return }
        do {
            if on { try svc.register() } else { try svc.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            openAtLogin = svc.status == .enabled
        }
    }

    private var aboutPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("About"))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: 0x1B1B1F))

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notchi").font(.system(size: 18, weight: .semibold)).foregroundColor(Color(hex: 0x1B1B1F))
                        Text(updater.canUpdate ? String(format: L("Version %@"), updater.current)
                                               : String(format: L("Version %@ · development build"), updater.current))
                            .font(.system(size: 12)).foregroundColor(Color(hex: 0x5E5D66))
                            .textSelection(.enabled)
                    }
                }
                Text(L("Shows your AI coding agents in the MacBook notch."))
                    .font(.system(size: 13)).foregroundColor(Color(hex: 0x1B1B1F))
                HStack(spacing: 16) {
                    Link(L("GitHub"), destination: URL(string: "https://github.com/heyhadi/notchi")!)
                    Link(L("Release notes"), destination: URL(string: "https://github.com/heyhadi/notchi/releases")!)
                    Text(L("MIT License")).foregroundColor(Color(hex: 0x5E5D66))
                }
                .font(.system(size: 12))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0xEAE7E0), lineWidth: 1))

            updatesCard
        }
    }

    private var updatesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if updater.canUpdate {
                Toggle(isOn: $autoUpdate) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Install updates automatically"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: 0x1B1B1F))
                        Text(L("Checks GitHub every few hours and updates when no agent is busy. This is the only network request Notchi makes."))
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: 0x5E5D66))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .tint(Color(hex: 0x1E8E66))

                Divider().overlay(Color(hex: 0xF0ECE1))

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notchi \(updater.current)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: 0x1B1B1F))
                        Text(updateStatusText)
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: { if case .failed = updater.status { 0xD93636 } else { 0x5E5D66 } }()))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    switch updater.status {
                    case .available(let v):
                        Button(String(format: L("Update to %@ and relaunch"), v)) { Task { await updater.install() } }
                    case .failed:
                        Button(L("Open download page")) { NSWorkspace.shared.open(Updater.releasesPage) }
                        Button(L("Check now")) { Task { await updater.check() } }
                    case .checking, .installing:
                        ProgressView().controlSize(.small)
                    default:
                        Button(L("Check now")) { Task { await updater.check() } }
                    }
                }
            } else {
                Text(L("Updates are off for development builds."))
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: 0x5E5D66))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0xEAE7E0), lineWidth: 1))
    }

    private var updateStatusText: String {
        switch updater.status {
        case .idle: return L("Not checked yet")
        case .checking: return L("Checking…")
        case .upToDate: return L("You're up to date.")
        case .available(let v): return String(format: L("Notchi %@ is available"), v)
        case .installing: return L("Downloading and installing…")
        case .failed(let msg): return msg
        }
    }

    // MARK: - Sound Tab

    private var soundPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Sound"))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: 0x1B1B1F))
            }

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L("Sound effects"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: 0x1B1B1F))
                    Spacer()
                    Toggle(isOn: $soundsOn) {
                        Text(L("Sounds on"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: 0x1B1B1F))
                    }
                    .toggleStyle(.switch)
                    .tint(Color(hex: 0x1E8E66))
                }

                Divider().overlay(Color(hex: 0xF0ECE1))

                VStack(spacing: 10) {
                    ForEach(AgentState.allCases, id: \.self) { state in
                        SoundStateRow(state: state, soundsOn: soundsOn)
                    }
                }

                Divider().overlay(Color(hex: 0xF0ECE1))

                HStack(spacing: 14) {
                    Text(L("Volume"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: 0x1B1B1F))
                        .frame(width: 90, alignment: .leading)
                    Slider(value: $volume, in: 0...1)
                        .accessibilityLabel(L("Volume"))
                        .tint(Color(hex: 0x1E8E66))
                    Text("\(Int(volume * 100))%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Color(hex: 0x5E5D66))
                        .frame(width: 40, alignment: .trailing)
                }

                Divider().overlay(Color(hex: 0xF0ECE1))

                HStack {
                    Text(L("Sound pack"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: 0x1B1B1F))
                    Spacer()
                    Picker(L("Sound pack"), selection: $soundPack) {
                        Text(L("Soft")).tag("soft")
                        Text(L("Retro 8-bit")).tag("retro")
                        Text(L("Chirpy")).tag("chirpy")
                        Text(L("Robot")).tag("robot")
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }

                Divider().overlay(Color(hex: 0xF0ECE1))

                Toggle(isOn: $reactionSounds) {
                    Text(L("Avatar and chat reaction sounds"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: 0x1B1B1F))
                }
                .toggleStyle(.switch)
                .tint(Color(hex: 0x1E8E66))

                Divider().overlay(Color(hex: 0xF0ECE1))

                Toggle(isOn: $muteWhenBusy) {
                    Text(L("Mute during calls and meetings"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: 0x1B1B1F))
                }
                .toggleStyle(.switch)
                .tint(Color(hex: 0x1E8E66))
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0xEAE7E0), lineWidth: 1))

            Text(L("At most one sound per minute, so it never gets annoying."))
                .font(.system(size: 12))
                .foregroundColor(Color(hex: 0x5E5D66))
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Privacy Tab

    private var privacyPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Privacy"))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: 0x1B1B1F))
            }

            VStack(alignment: .leading, spacing: 16) {
                privacyRow(
                    icon: "lock.shield",
                    text: L("Everything stays on this Mac. No analytics, no transcript upload. The only network request is the update check to GitHub (About → Install updates automatically).")
                )

                Divider().overlay(Color(hex: 0xF0ECE1))

                privacyRow(
                    icon: "network.badge.shield.half.filled",
                    text: L("Claude Code events arrive through a local socket only you can open.")
                )

                Divider().overlay(Color(hex: 0xF0ECE1))

                privacyRow(
                    icon: "terminal",
                    text: L("Risky commands can only be approved in the terminal.")
                )
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0xEAE7E0), lineWidth: 1))
        }
    }

    private func privacyRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(Color(hex: 0x1E8E66))
                .frame(width: 24, height: 24)

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Color(hex: 0x1B1B1F))
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }
}

// MARK: - SoundStateRow

@MainActor
private struct SoundStateRow: View {
    let state: AgentState
    let soundsOn: Bool
    @AppStorage private var soundRaw: String

    init(state: AgentState, soundsOn: Bool) {
        self.state = state
        self.soundsOn = soundsOn
        self._soundRaw = AppStorage(wrappedValue: SoundName.default(for: state).rawValue, Prefs.sound(for: state))
    }

    private var selectedSound: SoundName {
        SoundName(rawValue: soundRaw) ?? SoundName.default(for: state)
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: state.colorHex))
                .frame(width: 8, height: 8)

            Text(stateName(state))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(hex: 0x1B1B1F))

            Spacer()

            Picker(String(format: L("%@ sound"), stateName(state)), selection: Binding<SoundName>(
                get: { selectedSound },
                set: { soundRaw = $0.rawValue }
            )) {
                ForEach(SoundName.allCases) { sound in
                    Text(sound.title).tag(sound)
                }
            }
            .labelsHidden()
            .frame(width: 130)

            Button(action: {
                SoundPlayer.shared.preview(selectedSound)
            }) {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 12))
                    .foregroundColor(selectedSound == .off ? Color(hex: 0xB9B4C9) : Color(hex: 0x1B1B1F))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(selectedSound == .off ? Color(hex: 0xF6F4EF) : Color(hex: 0xE8E5DE))
                    )
            }
            .buttonStyle(.plain)
            .disabled(selectedSound == .off)
            .accessibilityLabel(String(format: L("Preview %@ sound"), stateName(state)))
        }
        .opacity(soundsOn ? 1.0 : 0.45)
    }
}


private struct HistoryPane: View {
    @State private var entries: [HistoryEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L("History")).font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundColor(Color(hex: 0x1B1B1F))
                Spacer()
                if !entries.isEmpty {
                    Button(L("Clear")) { try? FileManager.default.removeItem(at: NotchModel.historyFile); entries = [] }
                }
            }
            Text(L("Finished sessions, newest first. Stored only on this Mac."))
                .font(.system(size: 12)).foregroundColor(Color(hex: 0x5E5D66))
            if entries.isEmpty {
                Text(L("Nothing yet. Sessions show up here when they end."))
                    .font(.system(size: 13)).foregroundColor(Color(hex: 0x5E5D66))
            }
            ForEach(entries) { e in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(e.agentLabel) · \(e.project)").font(.system(size: 13, weight: .medium)).foregroundColor(Color(hex: 0x1B1B1F))
                        Text(detail(e)).font(.system(size: 11)).foregroundColor(Color(hex: 0x5E5D66))
                    }
                    Spacer()
                }
                Divider().overlay(Color(hex: 0xF0ECE1))
            }
        }
        .onAppear { entries = SessionHistory.load(try? Data(contentsOf: NotchModel.historyFile)) }
    }

    private func detail(_ e: HistoryEntry) -> String {
        var parts = [e.ended.formatted(date: .abbreviated, time: .shortened)]
        if let d = e.duration { parts.append(d < 60 ? "<1 min" : "\(Int(d / 60)) min") }
        if let t = e.tokens, t > 0 { parts.append(String(format: L("%@ tokens"), TokenCount.short(t))) }
        return parts.joined(separator: " · ")
    }
}


private struct AgentAvatarRow: View {
    let agent: AgentKind
    @AppStorage private var pick: String

    init(agent: AgentKind) {
        self.agent = agent
        _pick = AppStorage(wrappedValue: AvatarKind.defaultFor(agent).rawValue, Prefs.avatarKey(for: agent))
    }

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(kind: AvatarKind(rawValue: pick) ?? .bolt, state: .done, size: 32).frame(width: 32, height: 32)
            Text(agent.displayName).font(.system(size: 13)).foregroundColor(Color(hex: 0x1B1B1F))
            Spacer()
            Picker(agent.displayName, selection: $pick) {
                ForEach(AvatarKind.allCases) { Text($0.displayName).tag($0.rawValue) }
            }
            .labelsHidden().frame(width: 120)
        }
    }
}
