import Carbon
import Foundation

// Prints, for each virtual key code 0-127, the character the layout produces
// with no modifier, with Shift, with Option, and with Option+Shift.
// Reads the installed layout data only; does not switch the input source.

func layoutData(_ id: String) -> Data? {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
          let src = list.first,
          let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else {
        return nil
    }
    let cf = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue()
    return cf as Data
}

func translate(_ layout: UnsafePointer<UCKeyboardLayout>, _ keycode: UInt16, _ modifierState: UInt32) -> String {
    var deadKeyState: UInt32 = 0
    var chars = [UniChar](repeating: 0, count: 8)
    var length = 0
    let status = UCKeyTranslate(
        layout,
        keycode,
        UInt16(kUCKeyActionDown),
        modifierState,
        40, // ANSI keyboard type
        OptionBits(kUCKeyTranslateNoDeadKeysBit),
        &deadKeyState,
        8,
        &length,
        &chars
    )
    if status != noErr || length == 0 { return "-" }
    return String(utf16CodeUnits: chars, count: length)
}

let ids = CommandLine.arguments.dropFirst()
for id in ids {
    guard let data = layoutData(id) else {
        print("## \(id): not installed")
        continue
    }
    print("## \(id)")
    print("keycode\tplain\tshift\toption\toption+shift")
    data.withUnsafeBytes { raw in
        let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!
        for code in 0...127 {
            let k = UInt16(code)
            let plain = translate(layout, k, 0)
            let shift = translate(layout, k, UInt32((shiftKey >> 8) & 0xFF))
            let opt = translate(layout, k, UInt32((optionKey >> 8) & 0xFF))
            let optShift = translate(layout, k, UInt32(((shiftKey | optionKey) >> 8) & 0xFF))
            print("\(code)\t\(plain)\t\(shift)\t\(opt)\t\(optShift)")
        }
    }
}
