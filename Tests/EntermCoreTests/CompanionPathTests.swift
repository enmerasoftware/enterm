@testable import EntermCore
import XCTest

/// A moved or deleted copy of the app must not stop the user's programs from starting.
final class CompanionPathTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Stands in for the official program: the real one never runs in tests.
        try script("bin/claude", "#!/bin/sh\necho \"program: $*\"\n")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func script(_ name: String, _ body: String) throws {
        let url = folder.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// Runs the shell with its own integration loaded, then types `claude a b`.
    private func runClaude(shell: String, arguments: [String], integration: String, setup: String, cli: String) throws -> (out: String, err: String, code: Int32) {
        let file = folder.appendingPathComponent("integration")
        try integration.write(to: file, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // PATH is set after loading: the system profile would otherwise put the real program first.
        process.arguments = arguments + ["-c", "source '\(file.path)'; \(setup) PATH='\(folder.path)/bin:/usr/bin:/bin'; claude a b"]
        process.environment = ["HOME": folder.path, "ENTERM_CLI": cli, "PATH": "/usr/bin:/bin"]
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(decoding: outData, as: UTF8.self), String(decoding: errData, as: UTF8.self), process.terminationStatus)
    }

    private func zsh(cli: String) throws -> (out: String, err: String, code: Int32) {
        try runClaude(shell: "/bin/zsh", arguments: ["-f"], integration: ShellIntegration.zshIntegration, setup: "_enterm_install;", cli: cli)
    }

    private func bash(cli: String) throws -> (out: String, err: String, code: Int32) {
        try runClaude(shell: "/bin/bash", arguments: ["--noprofile", "--norc"], integration: ShellIntegration.bashInit, setup: "", cli: cli)
    }

    private var movedCLI: String { folder.appendingPathComponent("moved/enterm").path }

    func testZshStartsTheProgramWhenTheCompanionIsGone() throws {
        let result = try zsh(cli: movedCLI)
        XCTAssertTrue(result.out.contains("program: a b"), result.out + result.err)
        XCTAssertFalse(result.err.contains("no such file"), result.err)
        XCTAssertEqual(result.code, 0)
    }

    func testBashStartsTheProgramWhenTheCompanionIsGone() throws {
        let result = try bash(cli: movedCLI)
        XCTAssertTrue(result.out.contains("program: a b"), result.out + result.err)
        XCTAssertFalse(result.err.contains("No such file"), result.err)
        XCTAssertEqual(result.code, 0)
    }

    func testShellsStillGoThroughAWorkingCompanion() throws {
        try script("enterm", "#!/bin/sh\n[ \"$1\" = wrap ] && echo \"companion: $*\"\nexit 0\n")
        let cli = folder.appendingPathComponent("enterm").path
        XCTAssertTrue(try zsh(cli: cli).out.contains("companion: wrap claude a b"))
        XCTAssertTrue(try bash(cli: cli).out.contains("companion: wrap claude a b"))
    }

    func testServiceKeepsItsOwnCompanionWhileItExists() {
        let chosen = CompanionPath.choose(own: "/a/enterm", reported: "/b/enterm", isExecutable: { _ in true })
        XCTAssertEqual(chosen, "/a/enterm")
    }

    func testServiceMovesToTheWindowsCompanionWhenItsOwnIsGone() {
        let chosen = CompanionPath.choose(own: "/a/enterm", reported: "/b/enterm", isExecutable: { $0 == "/b/enterm" })
        XCTAssertEqual(chosen, "/b/enterm")
    }

    func testServiceIgnoresAReportThatIsNotTheCompanion() {
        let chosen = CompanionPath.choose(own: "/a/enterm", reported: "/b/other", isExecutable: { $0 == "/b/other" })
        XCTAssertEqual(chosen, "/a/enterm")
    }

    func testServiceIgnoresAMissingReport() {
        XCTAssertEqual(CompanionPath.choose(own: "/a/enterm", reported: "/b/enterm", isExecutable: { _ in false }), "/a/enterm")
        XCTAssertEqual(CompanionPath.choose(own: "/a/enterm", reported: nil, isExecutable: { _ in false }), "/a/enterm")
    }
}
