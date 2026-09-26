import UserNotifications

// Nonisolated: a pure helper of EmailNotificationContentBuilder.
nonisolated enum NotificationSoundPolicy {
    static func sound(playNotificationSounds: Bool) -> UNNotificationSound? {
        playNotificationSounds ? .default : nil
    }
}
