import AppKit

/// Makes Settings capturable without guessing.
///
/// A screenshot has to be taken of the real on-screen window: rendering the
/// view offscreen loses the drop shadow, the corner radius, the material and
/// the elevation, and raising the scale factor does not bring them back. That
/// means `screencapture -l<windowid>`, which needs the window id — and Mailbell
/// is an accessory app, so nothing else on the system can reliably tell you
/// which window is its. So the app reports its own.
///
/// Geometry is fixed here rather than inherited from the developer's screen or
/// a saved window frame, so the same command produces the same image on another
/// machine.
enum ScreenshotMode {
    static let launchArgument = "--screenshot-mode"

    /// Settings at a size chosen for capture: wide enough that no pane wraps,
    /// short enough to stay legible when published at half its pixel width.
    static let windowSize = NSSize(width: 720, height: 560)

    /// Printed once the window is on screen, sized, and active. A capture taken
    /// before this draws an inactive window: grey traffic lights and dimmed
    /// controls.
    static let readyMarker = "MAILBELL_SCREENSHOT_READY"
    static let windowIDPrefix = "MAILBELL_SCREENSHOT_WINDOW_ID="

    /// SwiftUI restores the last selected Settings tab and the last window
    /// frame from UserDefaults, so a capture would otherwise depend on whatever
    /// the developer last had open.
    static let selectedTabDefaultsKey = "com_apple_SwiftUI_Settings_selectedTabIndex"
    static let windowFrameDefaultsKey = "NSWindow Frame com_apple_SwiftUI_Settings_window"
    static let paneArgument = "--screenshot-pane"

    static var isEnabled: Bool {
        isEnabled(arguments: CommandLine.arguments)
    }

    static func requestedPane(arguments: [String] = CommandLine.arguments) -> Int {
        guard let index = arguments.firstIndex(of: paneArgument),
              arguments.count > index + 1,
              let pane = Int(arguments[index + 1])
        else {
            return 0
        }
        return pane
    }

    /// Pins the environment-dependent state before the scene reads it.
    static func pinEnvironment(defaults: UserDefaults = .standard, pane: Int = requestedPane()) {
        defaults.removeObject(forKey: windowFrameDefaultsKey)
        defaults.set(pane, forKey: selectedTabDefaultsKey)
    }

    static func isEnabled(arguments: [String]) -> Bool {
        arguments.contains(launchArgument)
    }

    static func windowIDLine(_ windowNumber: Int) -> String {
        "\(windowIDPrefix)\(windowNumber)"
    }

    static func parseWindowID(_ line: String) -> Int? {
        guard line.hasPrefix(windowIDPrefix) else { return nil }
        return Int(line.dropFirst(windowIDPrefix.count).trimmingCharacters(in: .whitespaces))
    }

    /// Finds Settings, pins its size, brings it forward, and reports it.
    ///
    /// Activation is re-applied after the first turns of the run loop because a
    /// window that has just appeared is not reliably key yet, and announcing
    /// readiness before that produces an inactive capture.
    /// Polls for the Settings window rather than assuming it exists after a
    /// fixed number of run-loop turns: SwiftUI opens it asynchronously, and how
    /// long that takes is not ours to predict.
    @MainActor
    static func prepareWhenReady(attemptsRemaining: Int = 60, emit: @escaping (String) -> Void = emitLine) {
        // Re-sent on every attempt: the Settings scene is installed
        // asynchronously, and the action is a no-op until it exists.
        guard let window = settingsWindow(in: NSApp.windows) else {
            guard attemptsRemaining > 0 else {
                let seen = NSApp.windows.map { window in
                    "\(type(of: window)) titled=\(window.styleMask.contains(.titled)) visible=\(window.isVisible)"
                }
                emit("MAILBELL_SCREENSHOT_ERROR=settings window never appeared; saw \(seen)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                prepareWhenReady(attemptsRemaining: attemptsRemaining - 1, emit: emit)
            }
            return
        }
        prepare(window: window, emit: emit)
    }

    /// stdout is a pipe when a script drives this, so it is block-buffered and
    /// the readiness marker would not arrive until exit.
    static func emitLine(_ line: String) {
        print(line)
        fflush(stdout)
    }

    @MainActor
    static func prepare(window: NSWindow, emit: @escaping (String) -> Void = emitLine) {
        window.setContentSize(windowSize)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async {
                emit(windowIDLine(Int(window.windowNumber)))
                emit(readyMarker)
            }
        }
    }

    /// The Settings window, identified by the content it holds rather than by
    /// its title, which is localized and changes with the selected pane.
    @MainActor
    static func settingsWindow(in windows: [NSWindow]) -> NSWindow? {
        windows.first { window in
            window.isVisible && window.contentView != nil && window.styleMask.contains(.titled)
        }
    }
}
