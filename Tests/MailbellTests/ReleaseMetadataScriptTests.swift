import XCTest

final class ReleaseMetadataScriptTests: XCTestCase {
    private struct CommandResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    func testResolvesVersionAndFallbackBuildNumberFromExactTag() throws {
        let repo = try makeTemporaryGitRepository(lightweightTag: "v1.2.3")
        defer { try? FileManager.default.removeItem(at: repo) }

        let result = runReleaseMetadataScript(currentDirectory: repo)

        XCTAssertEqual(result.status, 0, result.stderr)
        let values = parseAssignments(result.stdout)
        XCTAssertEqual(values["VERSION"], "1.2.3")
        XCTAssertEqual(values["BUILD_NUMBER"], "1")
        XCTAssertEqual(values["DMG_NAME"], "Mailbell-1.2.3.dmg")
        XCTAssertEqual(values["DMG_VOLUME_NAME"], "Install Mailbell")
    }

    func testResolvesVersionFromAnnotatedTag() throws {
        let repo = try makeTemporaryGitRepository(annotatedTag: "v1.2.4")
        defer { try? FileManager.default.removeItem(at: repo) }

        let result = runReleaseMetadataScript(currentDirectory: repo)

        XCTAssertEqual(result.status, 0, result.stderr)
        let values = parseAssignments(result.stdout)
        XCTAssertEqual(values["VERSION"], "1.2.4")
        XCTAssertEqual(values["BUILD_NUMBER"], "1")
        XCTAssertEqual(values["DMG_NAME"], "Mailbell-1.2.4.dmg")
    }

    func testUsesCIBuildNumberWhenPresent() throws {
        let repo = try makeTemporaryGitRepository(lightweightTag: "v2.0.0")
        defer { try? FileManager.default.removeItem(at: repo) }

        let result = runReleaseMetadataScript(
            currentDirectory: repo,
            environment: ["GITHUB_RUN_NUMBER": "987"]
        )

        XCTAssertEqual(result.status, 0, result.stderr)
        let values = parseAssignments(result.stdout)
        XCTAssertEqual(values["VERSION"], "2.0.0")
        XCTAssertEqual(values["BUILD_NUMBER"], "987")
    }

    func testFailsWhenHeadIsNotOnReleaseTag() throws {
        let repo = try makeTemporaryGitRepository()
        defer { try? FileManager.default.removeItem(at: repo) }

        let result = runReleaseMetadataScript(currentDirectory: repo)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("HEAD must be exactly on a release tag"), result.stderr)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func makeTemporaryGitRepository(
        lightweightTag: String? = nil,
        annotatedTag: String? = nil
    ) throws -> URL {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailbellReleaseMetadata.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        XCTAssertEqual(run(["git", "init"], currentDirectory: repo).status, 0)

        let marker = repo.appendingPathComponent("README.md")
        try "release metadata fixture\n".write(to: marker, atomically: true, encoding: .utf8)
        XCTAssertEqual(run(["git", "add", "README.md"], currentDirectory: repo).status, 0)
        let commit = run(
            [
                "git",
                "-c", "user.name=Mailbell Tests",
                "-c", "user.email=mailbell-tests@example.invalid",
                "-c", "commit.gpgsign=false",
                "commit",
                "-m", "Initial commit"
            ],
            currentDirectory: repo
        )
        XCTAssertEqual(commit.status, 0, commit.stderr)

        if let lightweightTag {
            let tagResult = run(["git", "tag", lightweightTag], currentDirectory: repo)
            XCTAssertEqual(tagResult.status, 0, tagResult.stderr)
        }

        if let annotatedTag {
            let tagResult = run(
                ["git", "tag", "-a", annotatedTag, "-m", "Release \(annotatedTag)"],
                currentDirectory: repo
            )
            XCTAssertEqual(tagResult.status, 0, tagResult.stderr)
        }

        return repo
    }

    private func runReleaseMetadataScript(
        currentDirectory: URL,
        environment: [String: String] = [:]
    ) -> CommandResult {
        run(
            [repositoryRoot().appendingPathComponent("Scripts/resolve_release_metadata.sh").path],
            currentDirectory: currentDirectory,
            environment: environment
        )
    }

    private func run(
        _ arguments: [String],
        currentDirectory: URL,
        environment: [String: String] = [:]
    ) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        var processEnvironment = ProcessInfo.processInfo.environment
        [
            "GITHUB_RUN_NUMBER",
            "CI_PIPELINE_IID",
            "CI_PIPELINE_ID",
            "BUILD_NUMBER",
            "BUILDKITE_BUILD_NUMBER",
            "CIRCLE_BUILD_NUM",
            "TRAVIS_BUILD_NUMBER",
            "BITRISE_BUILD_NUMBER"
        ].forEach { processEnvironment.removeValue(forKey: $0) }
        environment.forEach { processEnvironment[$0.key] = $0.value }
        process.environment = processEnvironment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return CommandResult(status: -1, stdout: "", stderr: error.localizedDescription)
        }

        return CommandResult(
            status: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    private func parseAssignments(_ output: String) -> [String: String] {
        output
            .split(whereSeparator: \.isNewline)
            .reduce(into: [String: String]()) { values, line in
                let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { return }
                values[String(parts[0])] = String(parts[1])
            }
    }
}
