// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "mailbell",
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
        .executableTarget(
            name: "mailbell",
            dependencies: [
                "FlyingFox",
                .product(name: "FlyingSocks", package: "FlyingFox"),
                "SwiftSoup",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Mailbell",
            linkerSettings: [
                // The packaged .app embeds Sparkle.framework in Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "MailbellTests",
            dependencies: ["mailbell"],
            path: "Tests/MailbellTests"
        )
    ]
)
