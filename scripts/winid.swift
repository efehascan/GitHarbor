import CoreGraphics
import Foundation
// Kullanım: winid <pid>  → o sürecin pencereleri: id genişlik yükseklik katman başlık
let pid = Int(CommandLine.arguments[1]) ?? 0
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where (w[kCGWindowOwnerPID as String] as? Int) == pid {
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    print(w[kCGWindowNumber as String] ?? 0, b["Width"] ?? 0, b["Height"] ?? 0, w[kCGWindowLayer as String] ?? 0,
          w[kCGWindowIsOnscreen as String] ?? false, w[kCGWindowName as String] ?? "")
}
