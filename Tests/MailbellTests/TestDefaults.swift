import Foundation

/// A throwaway `UserDefaults` suite for one test, the only way a test makes one
/// (`scripts/validate.sh` enforces this).
///
/// The suite name is an absolute path under `$TMPDIR/mailbell-tests/`, so cfprefsd
/// writes the suite's plist there and never in `~/Library/Preferences`. A named
/// suite cannot be kept out of `~/Library/Preferences` by teardown:
/// `removePersistentDomain(forName:)` only empties the domain, and cfprefsd writes
/// the empty domain back to `<name>.plist` after the test process exits, even
/// when teardown deleted the file (#50). macOS purges what is left in `$TMPDIR`.
struct TestDefaults {
    static let directory = FileManager.default.temporaryDirectory
        .appending(path: "mailbell-tests", directoryHint: .isDirectory)

    let suiteName: String
    let defaults: UserDefaults

    init() {
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        } catch {
            preconditionFailure("TestDefaults cannot create \(Self.directory.path): \(error)")
        }
        suiteName = Self.directory
            .appending(path: "mailbell-tests-\(UUID().uuidString)")
            .path(percentEncoded: false)
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("TestDefaults cannot open the suite \(suiteName)")
        }
        self.defaults = defaults
    }

    /// What the suite stores itself, without the process-wide registration domain.
    var persistentDomain: [String: Any]? {
        defaults.persistentDomain(forName: suiteName)
    }

    static func make() -> UserDefaults {
        TestDefaults().defaults
    }
}
