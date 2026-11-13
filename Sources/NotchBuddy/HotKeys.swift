import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Global shortcuts through Carbon's RegisterEventHotKey, which needs no Accessibility permission:
/// ⌃⌥N opens or closes the panel, ⌃⌥A is Allow once on the top card, ⌃⌥D is Deny on it.
@MainActor
final class HotKeys {
    static let shared = HotKeys()
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private weak var model: NotchModel?
    private static let keys: [(code: Int, id: UInt32)] = [(kVK_ANSI_N, 1), (kVK_ANSI_A, 2), (kVK_ANSI_D, 3)]

    /// Registers or unregisters to match the Settings toggle.
    func update(model: NotchModel) {
        self.model = model
        let on = UserDefaults.standard.bool(forKey: Prefs.hotkeys)
        guard on != !refs.isEmpty else { return }
        if !on { refs.forEach { UnregisterEventHotKey($0) }; refs = []; return }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &id)
                MainActor.assumeIsolated { HotKeys.shared.fire(id.id) }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        for k in Self.keys {
            var ref: EventHotKeyRef?
            // Another app may already own the combo; then that one shortcut just doesn't work.
            if RegisterEventHotKey(UInt32(k.code), UInt32(controlKey | optionKey), EventHotKeyID(signature: OSType(0x4E4F5443), id: k.id),
                                   GetApplicationEventTarget(), 0, &ref) == noErr, let ref { refs.append(ref) }
        }
    }

    private func fire(_ id: UInt32) {
        guard let model else { return }
        switch id {
        case 1:
            withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) {
                if model.mode == .expanded { model.requestCollapse() } else { model.mode = .expanded }
            }
        case 2, 3:
            // Approval cards only (a question needs its answer picked); Allow never fires on a risky card.
            guard let req = model.pending.first, req.event.questions == nil else { return }
            if id == 2 { if !req.isRisky && req.respond != nil { model.decide(req.id, .allow) } }
            else { model.decide(req.id, req.isRisky ? nil : .deny(L("Denied from Notchi"))) }
        default: break
        }
    }
}
