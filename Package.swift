// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "mailbell",
    platforms: [
        .macOS(.v26)
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
