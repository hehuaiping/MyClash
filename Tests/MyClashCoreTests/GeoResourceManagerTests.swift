import XCTest
@testable import MyClashCore

final class GeoResourceManagerTests: XCTestCase {
    func testEnsureBundledResourcesCopiesGeoFilesIncludingASN() throws {
        let baseURL = temporaryDirectory()
        let sourceURL = baseURL.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try "geoip".write(to: sourceURL.appendingPathComponent("GEOIP.dat"), atomically: true, encoding: .utf8)
        try "geosite".write(to: sourceURL.appendingPathComponent("GEOSITE.dat"), atomically: true, encoding: .utf8)
        try "mmdb".write(to: sourceURL.appendingPathComponent("GEOIP.metadb"), atomically: true, encoding: .utf8)
        try "asn".write(to: sourceURL.appendingPathComponent("ASN.mmdb"), atomically: true, encoding: .utf8)

        let paths = try AppPaths(baseDirectory: baseURL.appendingPathComponent("app", isDirectory: true))
        try paths.createDirectories()
        let manager = GeoResourceManager(paths: paths, searchDirectories: [sourceURL])

        try manager.ensureBundledResources()

        XCTAssertEqual(try String(contentsOf: paths.runtimeDirectory.appendingPathComponent("GeoIP.dat")), "geoip")
        XCTAssertEqual(try String(contentsOf: paths.runtimeDirectory.appendingPathComponent("GeoSite.dat")), "geosite")
        XCTAssertEqual(try String(contentsOf: paths.runtimeDirectory.appendingPathComponent("GeoIP.metadb")), "mmdb")
        XCTAssertEqual(try String(contentsOf: paths.runtimeDirectory.appendingPathComponent("ASN.mmdb")), "asn")
    }

    func testStatusesReportSizeDateAndOverrideURL() throws {
        let baseURL = temporaryDirectory()
        let paths = try AppPaths(baseDirectory: baseURL.appendingPathComponent("app", isDirectory: true))
        try paths.createDirectories()
        let geoIPURL = paths.runtimeDirectory.appendingPathComponent("GeoIP.dat")
        try "geoip".write(to: geoIPURL, atomically: true, encoding: .utf8)
        let overrideURL = URL(string: "https://example.com/geoip.dat")!

        let statuses = GeoResourceManager(paths: paths).statuses(urlOverrides: [.geoIP: overrideURL])
        let geoIP = try XCTUnwrap(statuses.first { $0.definition.kind == .geoIP })
        let asn = try XCTUnwrap(statuses.first { $0.definition.kind == .asn })

        XCTAssertTrue(geoIP.exists)
        XCTAssertEqual(geoIP.size, 5)
        XCTAssertNotNil(geoIP.lastModified)
        XCTAssertEqual(geoIP.sourceURL, overrideURL)
        XCTAssertFalse(asn.exists)
    }

    func testSyncDownloadsToTemporaryFileAndReplacesResource() async throws {
        let baseURL = temporaryDirectory()
        let paths = try AppPaths(baseDirectory: baseURL.appendingPathComponent("app", isDirectory: true))
        try paths.createDirectories()
        let downloadURL = URL(string: "https://example.com/geosite.dat")!
        let manager = GeoResourceManager(
            paths: paths,
            downloader: { url in
                XCTAssertEqual(url, downloadURL)
                return Data("new-geosite".utf8)
            }
        )

        let status = try await manager.sync(kind: .geoSite, url: downloadURL)

        XCTAssertTrue(status.exists)
        XCTAssertEqual(status.size, UInt64("new-geosite".utf8.count))
        XCTAssertEqual(try String(contentsOf: paths.runtimeDirectory.appendingPathComponent("GeoSite.dat")), "new-geosite")
    }

    func testSyncRejectsEmptyDownloads() async throws {
        let baseURL = temporaryDirectory()
        let paths = try AppPaths(baseDirectory: baseURL.appendingPathComponent("app", isDirectory: true))
        try paths.createDirectories()
        let manager = GeoResourceManager(paths: paths, downloader: { _ in Data() })

        do {
            _ = try await manager.sync(kind: .asn)
            XCTFail("Expected empty download to fail")
        } catch let error as GeoResourceManagerError {
            XCTAssertTrue(error.localizedDescription.contains("ASN"))
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MyClashGeoResourceManagerTests-\(UUID().uuidString)", isDirectory: true)
    }
}
