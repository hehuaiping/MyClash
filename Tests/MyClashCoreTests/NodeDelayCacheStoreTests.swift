import XCTest
@testable import MyClashCore

final class NodeDelayCacheStoreTests: XCTestCase {
    func testPersistsAndReloadsDelayResults() async throws {
        let directory = temporaryDirectory()
        let fileURL = directory.appendingPathComponent("node-delays.json")
        let store = NodeDelayCacheStore(fileURL: fileURL)

        try await store.upsert(["Node A": 123, "Node B": -1], now: Date(timeIntervalSince1970: 100))

        let reloaded = NodeDelayCacheStore(fileURL: fileURL)
        let delays = await reloaded.delays(now: Date(timeIntervalSince1970: 120))

        XCTAssertEqual(delays["Node A"], 123)
        XCTAssertEqual(delays["Node B"], -1)
    }

    func testFiltersExpiredDelayResults() async throws {
        let directory = temporaryDirectory()
        let fileURL = directory.appendingPathComponent("node-delays.json")
        let store = NodeDelayCacheStore(fileURL: fileURL)

        try await store.upsert(["Node A": 123], now: Date(timeIntervalSince1970: 100))

        let fresh = await store.delays(maxAge: 60, now: Date(timeIntervalSince1970: 120))
        let expired = await store.delays(maxAge: 10, now: Date(timeIntervalSince1970: 120))

        XCTAssertEqual(fresh["Node A"], 123)
        XCTAssertNil(expired["Node A"])
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MyClashTests-\(UUID().uuidString)", isDirectory: true)
    }
}
