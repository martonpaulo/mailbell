import UserNotifications

enum NotificationSoundPolicy {
    static func sound(playNotificationSounds: Bool) -> UNNotificationSound? {
        playNotificationSounds ? .default : nil
    }
}
