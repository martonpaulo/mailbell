// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "mailbell",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(url: "https://github.com/swhitty/FlyingFox.git", .upToNextMinor(from: "0.26.2")),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", .upToNextMajor(from: "2.13.5"))
    ],
    targets: [
        .executableTarget(
            name: "mailbell",
            dependencies: [
                "FlyingFox",
                .product(name: "FlyingSocks", package: "FlyingFox"),
                "SwiftSoup"
            ],
            path: "Sources/Mailbell"
        ),
        .testTarget(
            name: "MailbellTests",
            dependencies: ["mailbell"],
            path: "Tests/MailbellTests"
        )
    ]
)
