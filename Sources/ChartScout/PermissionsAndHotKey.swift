import AppKit
import ApplicationServices
import Carbon.HIToolbox

struct PermissionState {
    let screenRecording: Bool
    let accessibility: Bool
    static func current() -> PermissionState {
        .init(screenRecording: CGPreflightScreenCaptureAccess(), accessibility: AXIsProcessTrusted())
    }
    static func requestScreenRecording() { _ = CGRequestScreenCaptureAccess() }
    static func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

final class GlobalHotKey {
    var onPress: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    deinit { if let ref { UnregisterEventHotKey(ref) }; if let handler { RemoveEventHandler(handler) } }

    func register(shortcut: ShortcutChoice = .commandShiftSpace) {
        if let ref { UnregisterEventHotKey(ref) }
        let eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        if handler == nil {
            InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
                let object = Unmanaged<GlobalHotKey>.fromOpaque(userData!).takeUnretainedValue()
                object.onPress?()
                return noErr
            }, 1, [eventType], Unmanaged.passUnretained(self).toOpaque(), &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x43534354), id: 1) // CSCT
        RegisterEventHotKey(UInt32(kVK_Space), shortcut.carbonModifiers, id, GetEventDispatcherTarget(), 0, &ref)
    }
}
