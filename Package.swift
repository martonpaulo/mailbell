// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "mailbell",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "mailbell",
            path: "Sources/Mailbell"
        ),
        .testTarget(
            name: "MailbellTests",
            dependencies: ["mailbell"],
            path: "Tests/MailbellTests"
        )
    ]
)
