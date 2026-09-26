import Foundation

/// The single owner of the menu bar symbol. An account that needs the user to
/// act outranks unread mail, so the bell is replaced by an alert glyph instead
/// of silently looking idle while nothing is being monitored.
public enum MenuBarIcon {
    public static let idle = "bell"
    static let pending = "bell.fill"
    static let attention = "exclamationmark.triangle.fill"

    public static func systemImage(needsAttention: Bool, hasPendingItems: Bool) -> String {
        if needsAttention {
            return attention
        }
        return hasPendingItems ? pending : idle
    }
}
