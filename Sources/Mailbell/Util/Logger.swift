import Foundation
import os

enum Log {
    private static let logger = os.Logger(subsystem: "com.samzong.mailbell", category: "app")

    static func info(_ message: @autoclosure () -> String) {
        let text = message()
        logger.info("\(text, privacy: .public)")
    }

    static func error(_ message: @autoclosure () -> String) {
        let text = message()
        logger.error("\(text, privacy: .public)")
    }
}
