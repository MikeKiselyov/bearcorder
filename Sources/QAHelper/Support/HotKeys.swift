import Carbon.HIToolbox
import Foundation

/// Global hotkeys via Carbon `RegisterEventHotKey` (no Accessibility permission needed).
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    struct Binding {
        var keyCode: UInt32
        var modifiers: UInt32
        var display: String
        var action: () -> Void
    }

    private var bindings: [UInt32: Binding] = [:]
    private var references: [EventHotKeyRef] = []
    private var handlerInstalled = false

    func register(_ list: [Binding]) {
        unregisterAll()
        installHandler()
        for (offset, binding) in list.enumerated() {
            let identifier = UInt32(offset + 1)
            let hotKeyId = EventHotKeyID(signature: OSType(0x5141_4850), id: identifier) // "QAHP"
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(binding.keyCode, binding.modifiers, hotKeyId, GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference = reference {
                references.append(reference)
                bindings[identifier] = binding
            }
        }
    }

    func unregisterAll() {
        for reference in references {
            UnregisterEventHotKey(reference)
        }
        references.removeAll()
        bindings.removeAll()
    }

    fileprivate func fire(_ identifier: UInt32) {
        bindings[identifier]?.action()
    }

    private func installHandler() {
        if handlerInstalled { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyId = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyId)
            let identifier = hotKeyId.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    HotKeyCenter.shared.fire(identifier)
                }
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }

    static let optionShift = UInt32(optionKey | shiftKey)
}

enum HotKeyCodes {
    static let one = UInt32(kVK_ANSI_1)
    static let two = UInt32(kVK_ANSI_2)
    static let three = UInt32(kVK_ANSI_3)
    static let four = UInt32(kVK_ANSI_4)
    static let five = UInt32(kVK_ANSI_5)
    static let six = UInt32(kVK_ANSI_6)
    static let seven = UInt32(kVK_ANSI_7)
    static let letterA = UInt32(kVK_ANSI_A)
    static let letterC = UInt32(kVK_ANSI_C)
    static let letterD = UInt32(kVK_ANSI_D)
    static let letterM = UInt32(kVK_ANSI_M)
    static let letterO = UInt32(kVK_ANSI_O)
}
