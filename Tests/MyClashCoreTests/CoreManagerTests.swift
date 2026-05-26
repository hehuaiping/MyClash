import XCTest
@testable import MyClashCore

final class CoreManagerTests: XCTestCase {
    func testPrepareCoreLogForLaunchTruncatesOversizedLogAndRemovesLegacyArchives() async throws {
        let root = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let paths = try AppPaths(baseDirectory: root)
        try paths.createDirectories()
        try Data(repeating: 65, count: 2 * 1024 * 1024 + 1).write(to: paths.coreLogURL)
        try "archive-1".write(to: archiveURL(paths: paths, index: 1), atomically: true, encoding: .utf8)
        try "archive-2".write(to: archiveURL(paths: paths, index: 2), atomically: true, encoding: .utf8)
        try "archive-3".write(to: archiveURL(paths: paths, index: 3), atomically: true, encoding: .utf8)

        let manager = CoreManager(paths: paths)
        try await manager.prepareCoreLogForLaunch()

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.coreLogURL.path))
        XCTAssertEqual(try fileSize(paths.coreLogURL), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL(paths: paths, index: 1).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL(paths: paths, index: 2).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL(paths: paths, index: 3).path))
    }

    func testPrepareCoreLogForLaunchKeepsSmallLog() async throws {
        let root = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let paths = try AppPaths(baseDirectory: root)
        try paths.createDirectories()
        try "small-log".write(to: paths.coreLogURL, atomically: true, encoding: .utf8)

        let manager = CoreManager(paths: paths)
        try await manager.prepareCoreLogForLaunch()

        XCTAssertEqual(try String(contentsOf: paths.coreLogURL, encoding: .utf8), "small-log")
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL(paths: paths, index: 1).path))
    }

    private func archiveURL(paths: AppPaths, index: Int) -> URL {
        paths.logsDirectory.appendingPathComponent("core.log.\(index)")
    }

    private func fileSize(_ url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyClashCoreManagerTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
