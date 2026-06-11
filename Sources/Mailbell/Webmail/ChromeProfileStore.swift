import Foundation

enum ChromeProfileStore {
    private static let excludedProfileNames: Set<String> = [
        "Guest Profile",
        "System Profile"
    ]

    static func userDataDirectory(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
    }

    static func localStateURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        userDataDirectory(homeDirectory: homeDirectory).appendingPathComponent("Local State")
    }

    static func loadProfiles(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [ChromeProfileCandidate] {
        let localStateURL = localStateURL(homeDirectory: homeDirectory)
        guard let data = try? Data(contentsOf: localStateURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let infoCache = json["profile"] as? [String: Any],
              let profiles = infoCache["info_cache"] as? [String: [String: Any]] else {
            return []
        }

        return profiles.compactMap { directory, info in
            let displayName = info["name"] as? String ?? directory
            if excludedProfileNames.contains(displayName) || excludedProfileNames.contains(directory) {
                return nil
            }
            let userName = info["user_name"] as? String
            return ChromeProfileCandidate(directory: directory, displayName: displayName, userName: userName)
        }
        .sorted { left, right in
            if left.directory == "Default" { return true }
            if right.directory == "Default" { return false }
            return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
        }
    }

    static func loadProfilesAsync(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) async -> [ChromeProfileCandidate] {
        await Task.detached(priority: .userInitiated) {
            loadProfiles(homeDirectory: homeDirectory)
        }.value
    }

    static func profileExists(
        directory: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> Bool {
        var isDirectory: ObjCBool = false
        let path = userDataDirectory(homeDirectory: homeDirectory)
            .appendingPathComponent(directory, isDirectory: true).path
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
