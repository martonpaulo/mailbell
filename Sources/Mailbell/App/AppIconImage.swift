import AppKit
import SwiftUI

/// The application icon at `size` points. AppKit draws it, so it picks the icon
/// file's representation for that size and the display's scale; SwiftUI's
/// `resizable()` scales the 1024 px image down and leaves jagged edges.
struct AppIconImage: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: Self.icon(size: size))
            .frame(width: size, height: size)
    }

    private static func icon(size: CGFloat) -> NSImage {
        let source = NSApp.applicationIconImage ?? NSImage()
        // The handler runs at each drawing's backing scale, so the chosen
        // representation follows the display the window is on.
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
    }
}
