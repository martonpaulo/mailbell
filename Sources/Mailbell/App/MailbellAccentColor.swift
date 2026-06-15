import AppKit
import SwiftUI

extension Color {
    static var mailbellAccent: Color {
        Color(nsColor: .mailbellAccent)
    }
}

extension NSColor {
    static var mailbellAccent: NSColor {
        NSColor(named: "AccentColor")
            ?? NSColor(
                srgbRed: 0.42745098,
                green: 0.24313725,
                blue: 0.94901961,
                alpha: 1.0
            )
    }
}
