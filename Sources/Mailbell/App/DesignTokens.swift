import SwiftUI

/// The single source of truth for every visual constant in Mailbell's own
/// views. Names are semantic so intent survives a redesign; no view hardcodes a
/// size, inset, radius, or font size.
enum Token {
    /// Spacing scale (points).
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    /// Fixed dimensions (points).
    enum Size {
        /// Stable content size shared by every Settings pane, so switching
        /// panes never resizes or re-centers the window.
        static let paneWidth: CGFloat = 620
        static let paneHeight: CGFloat = 560
        static let aboutIcon: CGFloat = 56
        /// Gap between the menu bar glyph and its count.
        static let menuBarCountSpacing: CGFloat = 3
    }

    enum Font {
        static let aboutTitle = SwiftUI.Font.title3
        static let footnote = SwiftUI.Font.footnote
        static let secondary = SwiftUI.Font.callout
    }
}

/// Every outward-facing Mailbell URL. One definition, reused by Settings, the
/// About pane, and support copy, so a moved page is a single-line change.
enum ProjectLinks {
    static let website = URL(string: "https://martonpaulo.github.io/mailbell/")!
    static let repository = URL(string: "https://github.com/martonpaulo/mailbell")!
    static let issues = URL(string: "https://github.com/martonpaulo/mailbell/issues")!
    static let latestRelease = URL(string: "https://github.com/martonpaulo/mailbell/releases/latest")!
    static let privacyPolicy = URL(string: "https://martonpaulo.github.io/mailbell/privacy.html")!
    static let termsOfService = URL(string: "https://martonpaulo.github.io/mailbell/terms.html")!
    static let googleAccountPermissions = URL(string: "https://myaccount.google.com/permissions")!
}
