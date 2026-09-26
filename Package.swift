// swift-tools-version:6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .treatAllWarnings(as: .error)
]

let package = Package(
    name: "Mailbell",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(url: "https://github.com/swhitty/FlyingFox.git", .upToNextMinor(from: "0.27.1")),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", .upToNextMajor(from: "2.13.5")),
        // Automatic updates for the direct-download build. Update checks are the
        // only network activity Mailbell performs outside Gmail itself.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        // Pure logic: it imports only Foundation, Observation, Synchronization and
        // CoreGraphics (AGENTS.md, "Architecture"; scripts/validate.sh checks it).
        // It keeps the nonisolated default, so its callers decide isolation.
        .target(
            name: "MailbellKit",
            path: "Sources/MailbellKit",
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "Mailbell",
            dependencies: [
                "MailbellKit",
                "FlyingFox",
                .product(name: "FlyingSocks", package: "FlyingFox"),
                "SwiftSoup",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Mailbell",
            swiftSettings: swiftSettings + [.defaultIsolation(MainActor.self)],
            linkerSettings: [
                // The packaged .app embeds Sparkle.framework in Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        // Test-only: the one place a test makes a UserDefaults suite (#50).
        .target(
            name: "MailbellTestSupport",
            path: "Tests/MailbellTestSupport",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "MailbellKitTests",
            dependencies: ["MailbellKit", "MailbellTestSupport"],
            path: "Tests/MailbellKitTests",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "MailbellTests",
            dependencies: ["Mailbell", "MailbellKit", "MailbellTestSupport"],
            path: "Tests/MailbellTests",
            swiftSettings: swiftSettings
        )
    ]
)
