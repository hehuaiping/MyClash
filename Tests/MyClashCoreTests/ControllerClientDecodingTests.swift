import XCTest
@testable import MyClashCore

final class ControllerClientDecodingTests: XCTestCase {
    func testProxyCollectionDecodesLossyMihomoResponses() throws {
        let json = """
        {
          "proxies": {
            "OKZTWO": {
              "name": "OKZTWO",
              "type": "Selector",
              "now": "HK-1",
              "all": ["HK-1", 2, null, true],
              "history": [{"time": 1710000000, "delay": "23"}, {"delay": null}]
            },
            "DIRECT": {
              "name": "DIRECT",
              "type": "Direct",
              "now": null,
              "all": null,
              "history": null
            },
            "BROKEN": null
          }
        }
        """.data(using: .utf8)!

        let collection = try JSONDecoder().decode(ProxyCollection.self, from: json)

        XCTAssertEqual(collection.proxies["OKZTWO"]?.all, ["HK-1", "2", "true"])
        XCTAssertEqual(collection.proxies["OKZTWO"]?.history?.first?.time, "1710000000")
        XCTAssertEqual(collection.proxies["OKZTWO"]?.history?.first?.delay, 23)
        XCTAssertEqual(collection.proxies["DIRECT"]?.type, "Direct")
        XCTAssertNil(collection.proxies["BROKEN"])
    }

    func testConnectionCollectionDefaultsMissingFields() throws {
        let json = """
        {
          "uploadTotal": "1024",
          "downloadTotal": 2048,
          "connections": [
            {
              "upload": "64",
              "download": 128,
              "chains": ["OKZTWO", 100, null],
              "rule": null,
              "rulePayload": 12345
            },
            null
          ]
        }
        """.data(using: .utf8)!

        let collection = try JSONDecoder().decode(ConnectionCollection.self, from: json)

        XCTAssertEqual(collection.uploadTotal, 1024)
        XCTAssertEqual(collection.downloadTotal, 2048)
        XCTAssertEqual(collection.connections.count, 1)
        XCTAssertFalse(collection.connections[0].id.isEmpty)
        XCTAssertEqual(collection.connections[0].upload, 64)
        XCTAssertEqual(collection.connections[0].download, 128)
        XCTAssertEqual(collection.connections[0].chains, ["OKZTWO", "100"])
        XCTAssertEqual(collection.connections[0].rulePayload, "12345")
    }

    func testConnectionCollectionUsesEmptyListWhenConnectionsAreMissing() throws {
        let json = """
        {
          "uploadTotal": 0,
          "downloadTotal": 0
        }
        """.data(using: .utf8)!

        let collection = try JSONDecoder().decode(ConnectionCollection.self, from: json)

        XCTAssertEqual(collection.connections, [])
    }

    func testProxyProviderCollectionDecodesRuntimeProvidersLossily() throws {
        let json = """
        {
          "providers": {
            "RemoteNodes": {
              "name": "RemoteNodes",
              "type": "Proxy",
              "vehicleType": "HTTP",
              "updatedAt": 1710000000,
              "subscriptionInfo": "upload=1; download=2; total=3",
              "proxies": [
                {"name": "HK-1", "type": "Hysteria2"},
                null
              ]
            },
            "BROKEN": null
          }
        }
        """.data(using: .utf8)!

        let collection = try JSONDecoder().decode(ProxyProviderCollection.self, from: json)

        XCTAssertEqual(collection.providers.count, 1)
        XCTAssertEqual(collection.providers["RemoteNodes"]?.vehicleType, "HTTP")
        XCTAssertEqual(collection.providers["RemoteNodes"]?.updatedAt, "1710000000")
        XCTAssertEqual(collection.providers["RemoteNodes"]?.proxies?.first?.name, "HK-1")
    }
}
