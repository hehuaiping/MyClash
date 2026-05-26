import XCTest
@testable import MyClashCore

final class ProfileDownloadTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        ProfileDownloadMockURLProtocol.requestedUserAgents = []
    }

    func testDownloadProfileRetriesWithClientUserAgentWhenServerReturnsDegradedConfig() async throws {
        let baseURL = temporaryDirectory()
        let paths = try AppPaths(baseDirectory: baseURL.appendingPathComponent("app", isDirectory: true))
        let session = makeMockSession()
        let manager = ProfileManager(paths: paths, downloadSession: session)

        ProfileDownloadMockURLProtocol.handler = { request in
            let userAgent = request.value(forHTTPHeaderField: "User-Agent") ?? ""
            ProfileDownloadMockURLProtocol.requestedUserAgents.append(userAgent)
            let body: String
            if userAgent.contains("FlClash") {
                body = """
                proxies:
                  - {name: Node A, type: ss, server: example.com, port: 443}
                  - {name: Node B, type: ss, server: example.org, port: 443}
                proxy-groups:
                  - {name: Select, type: select, proxies: [Node A, Node B]}
                rules:
                  - MATCH,Select
                """
            } else {
                body = """
                proxies:
                  - {name: 请下载客户端 见教程, type: trojan, server: example.com, port: 443}
                proxy-groups:
                  - {name: OKZTWO, type: select, proxies: [请下载客户端 见教程]}
                rules:
                  - MATCH,OKZTWO
                """
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/yaml"]
            )!
            return (response, Data(body.utf8))
        }

        let profile = try await manager.downloadProfile(from: URL(string: "https://example.com/sub")!, name: "Remote")

        XCTAssertGreaterThanOrEqual(ProfileDownloadMockURLProtocol.requestedUserAgents.count, 2)
        XCTAssertTrue(ProfileDownloadMockURLProtocol.requestedUserAgents.contains { $0.contains("MyClash") })
        XCTAssertTrue(ProfileDownloadMockURLProtocol.requestedUserAgents.contains { $0.contains("FlClash") })
        XCTAssertEqual(profile.metadata.qualityReport?.proxyCount, 2)
        XCTAssertEqual(ProfileManager.makeProxyPreview(rawConfig: try String(contentsOf: profile.rawConfigURL)).first?.all, ["Node A", "Node B"])
    }

    func testQualityReportDetectsDegradedSubscriptionHint() {
        let report = ProfileManager.qualityReport(rawConfig: """
        proxies:
          - {name: 请下载客户端 见教程, type: trojan}
        proxy-groups:
          - {name: OKZTWO, type: select, proxies: [请下载客户端 见教程]}
        """)

        XCTAssertTrue(report.isLikelyDegradedSubscription)
    }

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileDownloadMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyClashProfileDownloadTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class ProfileDownloadMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestedUserAgents: [String] = []
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw URLError(.badServerResponse)
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
