import XCTest
@testable import MyClashCore

final class CoreBinaryManagerTests: XCTestCase {
    func testReleaseDownloadURLUsesArchitectureAssetName() throws {
        let paths = try AppPaths(baseDirectory: temporaryDirectory())
        let manager = CoreBinaryManager(paths: paths, architecture: .arm64)

        XCTAssertEqual(
            try manager.releaseAssetName(version: "v1.19.24"),
            "mihomo-darwin-arm64-v1.19.24.gz"
        )
        XCTAssertEqual(
            try manager.releaseDownloadURL(version: "1.19.24").absoluteString,
            "https://github.com/MetaCubeX/mihomo/releases/download/v1.19.24/mihomo-darwin-arm64-v1.19.24.gz"
        )
    }

    func testNormalizesAndValidatesReleaseVersion() throws {
        XCTAssertEqual(try CoreBinaryManager.normalizedReleaseVersion(" 1.19.24 "), "v1.19.24")
        XCTAssertEqual(try CoreBinaryManager.normalizedReleaseVersion("v1.19.24"), "v1.19.24")
        XCTAssertThrowsError(try CoreBinaryManager.normalizedReleaseVersion("../v1.19.24"))
        XCTAssertThrowsError(try CoreBinaryManager.normalizedReleaseVersion(""))
    }

    func testSHA256() throws {
        let url = temporaryDirectory().appendingPathComponent("hash.txt")
        try "abc".write(to: url, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            try CoreBinaryManager.sha256(of: url),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testInstallLocalExecutableAndReadVersion() async throws {
        let baseURL = temporaryDirectory()
        let sourceURL = baseURL.appendingPathComponent("fake-mihomo")
        try """
        #!/bin/sh
        echo "Mihomo Meta fake-version"
        """.write(to: sourceURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sourceURL.path)

        let paths = try AppPaths(baseDirectory: baseURL.appendingPathComponent("app", isDirectory: true))
        let manager = CoreBinaryManager(paths: paths, architecture: .arm64)
        let installedURL = try await manager.installCore(from: sourceURL)
        let info = await manager.installedInfo()

        XCTAssertEqual(installedURL, paths.coreBinaryURL(for: "arm64"))
        XCTAssertTrue(info.exists)
        XCTAssertTrue(info.isExecutable)
        XCTAssertEqual(info.versionDescription, "Mihomo Meta fake-version")
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyClashTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
