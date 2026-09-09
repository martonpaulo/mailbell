@testable import mailbell
import XCTest

/// The appcast advertises a signature and length for an exact archive. Treating
/// a version string as proof the feed is current lets a rebuilt, unpublished
/// release ship one ZIP while the feed still describes the previous bytes.
final class AppcastScriptTests: XCTestCase {
    private let signatureA = #"sparkle:edSignature="AAA" length="111""#
    private let signatureB = #"sparkle:edSignature="BBB" length="222""#

    func testRepeatedIdenticalInputIsANoOp() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let first = run(in: workspace, version: "9.9.9", signature: signatureA)
        let second = run(in: workspace, version: "9.9.9", signature: signatureA)

        XCTAssertEqual(first.status, 0, first.output)
        XCTAssertEqual(second.status, 0, second.output)
        XCTAssertTrue(second.output.contains("leaving unchanged"), second.output)
        XCTAssertEqual(try itemCount(in: workspace), 1)
        XCTAssertTrue(try feed(in: workspace).contains(signatureA))
    }

    func testARebuiltArchiveReplacesTheStaleEntryInsteadOfReportingSuccess() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        _ = run(in: workspace, version: "9.9.9", signature: signatureA)
        let rebuilt = run(in: workspace, version: "9.9.9", signature: signatureB)

        XCTAssertEqual(rebuilt.status, 0, rebuilt.output)
        let contents = try feed(in: workspace)
        XCTAssertTrue(contents.contains(signatureB), "the new archive must be advertised")
        XCTAssertFalse(contents.contains(signatureA), "stale metadata must not survive")
        XCTAssertEqual(try itemCount(in: workspace), 1, "replacing, not duplicating")
    }

    func testADifferentArchiveURLAlsoReplacesTheEntry() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        _ = run(in: workspace, version: "9.9.9", archive: "Mailbell-9.9.9.zip", signature: signatureA)
        _ = run(in: workspace, version: "9.9.9", archive: "Mailbell-9.9.9-arm64.zip", signature: signatureA)

        let contents = try feed(in: workspace)
        XCTAssertTrue(contents.contains("Mailbell-9.9.9-arm64.zip"))
        XCTAssertFalse(contents.contains("/Mailbell-9.9.9.zip"))
        XCTAssertEqual(try itemCount(in: workspace), 1)
    }

    func testANewVersionIsPrependedAndLeavesEarlierEntriesAlone() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        _ = run(in: workspace, version: "9.9.9", signature: signatureA)
        _ = run(in: workspace, version: "9.9.10", signature: signatureB)

        XCTAssertEqual(try itemCount(in: workspace), 2)
        let titles = try feed(in: workspace)
            .components(separatedBy: "<title>")
            .dropFirst()
            .map { $0.components(separatedBy: "</title>")[0] }
        XCTAssertEqual(titles, ["Mailbell", "9.9.10", "9.9.9"], "newest first")
    }

    // MARK: - Helpers

    private struct ScriptResult {
        let status: Int32
        let output: String
    }

    private func makeWorkspace() throws -> URL {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailbellAppcast.\(UUID().uuidString)")
        let scripts = workspace.appendingPathComponent("Scripts")
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Scripts/make_appcast.sh"),
            to: scripts.appendingPathComponent("make_appcast.sh")
        )
        return workspace
    }

    private func run(
        in workspace: URL,
        version: String,
        archive: String = "Mailbell-9.9.9.zip",
        signature: String
    ) -> ScriptResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            workspace.appendingPathComponent("Scripts/make_appcast.sh").path,
            version,
            "999",
            "/tmp/\(archive)",
            signature
        ]
        process.currentDirectoryURL = workspace
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return ScriptResult(status: -1, output: "\(error)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ScriptResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    private func feed(in workspace: URL) throws -> String {
        try String(contentsOf: workspace.appendingPathComponent("appcast.xml"), encoding: .utf8)
    }

    private func itemCount(in workspace: URL) throws -> Int {
        try feed(in: workspace).components(separatedBy: "<item>").count - 1
    }
}
