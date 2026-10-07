import Carbon

private var hotkeyCallback: (() -> Void)?

private func fourCharCode(_ string: String) -> FourCharCode {
    var code: FourCharCode = 0
    let chars = Array(string.utf8)
    for i in 0..<min(4, chars.count) {
        code = (code << 8) + FourCharCode(chars[i])
    }
    return code
}

private func hotkeyHandler(
    _: EventHandlerCallRef?,
    _: EventRef?,
    _: UnsafeMutableRawPointer?
) -> OSStatus {
    DispatchQueue.main.async { hotkeyCallback?() }
    return noErr
}

final class GlobalHotkey {
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    func register(
        keyCode: UInt32 = UInt32(kVK_Space),
        modifiers: UInt32 = UInt32(optionKey),
        callback: @escaping () -> Void
    ) -> Bool {
        hotkeyCallback = callback

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        var handler: EventHandlerRef?
        guard InstallEventHandler(
            GetEventDispatcherTarget(),
            hotkeyHandler,
            1,
            &eventType,
            nil,
            &handler
        ) == noErr else { return false }
        eventHandler = handler

        var hotKey: EventHotKeyRef?
        let id = EventHotKeyID(signature: fourCharCode("sunn"), id: 1)

        guard RegisterEventHotKey(
            keyCode,
            modifiers,
            id,
            GetEventDispatcherTarget(),
            0,
            &hotKey
        ) == noErr else { return false }
        hotKeyRef = hotKey
        return true
    }

    deinit {
        if let hotKeyRef = hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler = eventHandler { RemoveEventHandler(eventHandler) }
    }
}
