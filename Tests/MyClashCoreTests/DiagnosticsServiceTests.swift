import XCTest
@testable import MyClashCore

final class DiagnosticsServiceTests: XCTestCase {
    func testRedactMasksSecretsAndURLCredentials() {
        let input = """
        secret: "controller-secret"
        password: super-secret
        Authorization: Bearer abc.def.ghi
        url: https://user:pass@example.com/sub?token=subscription-token&keep=true
        """

        let redacted = DiagnosticsService.redact(input)

        XCTAssertFalse(redacted.contains("controller-secret"))
        XCTAssertFalse(redacted.contains("super-secret"))
        XCTAssertFalse(redacted.contains("abc.def.ghi"))
        XCTAssertFalse(redacted.contains("user:pass"))
        XCTAssertFalse(redacted.contains("subscription-token"))
        XCTAssertTrue(redacted.contains("<redacted>"))
        XCTAssertTrue(redacted.contains("keep=true"))
    }

    func testExportPackageWritesRedactedFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("myclash-diagnostics-tests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let paths = try AppPaths(baseDirectory: root)
        try paths.createDirectories()
        try """
        secret: "runtime-secret"
        proxies:
          - name: test
            password: proxy-password
        subscription: https://example.com/list?token=runtime-token
        """.write(to: paths.runtimeConfigURL, atomically: true, encoding: .utf8)
        try "Authorization: Bearer log-token\n".write(to: paths.coreLogURL, atomically: true, encoding: .utf8)

        let profileDirectory = paths.profilesDirectory.appendingPathComponent("default", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        try "password: raw-profile-password\n".write(
            to: profileDirectory.appendingPathComponent("raw.yaml"),
            atomically: true,
            encoding: .utf8
        )

        let service = DiagnosticsService(paths: paths)
        let result = try service.exportPackage(snapshot: service.snapshot(coreStateDescription: "running"))
        let exported = try readAllTextFiles(in: result.directory)

        XCTAssertTrue(result.files.contains("manifest.json"))
        XCTAssertFalse(exported.contains("runtime-secret"))
        XCTAssertFalse(exported.contains("proxy-password"))
        XCTAssertFalse(exported.contains("runtime-token"))
        XCTAssertFalse(exported.contains("log-token"))
        XCTAssertFalse(exported.contains("raw-profile-password"))
        XCTAssertTrue(exported.contains("<redacted>"))
    }

    private func readAllTextFiles(in directory: URL) throws -> String {
        let urls = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? []
        return try urls
            .filter { !$0.hasDirectoryPath }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }
}
