import XCTest
@testable import MyClashCore

final class SystemProxyManagerTests: XCTestCase {
    func testListNetworkServicesRejectsAuthorizationFailureEvenWithZeroExitCode() async throws {
        let mock = NetworkSetupMock(responses: [
            ["-listallnetworkservices"]: [
                ProcessResult(terminationStatus: 0, stdout: "AuthorizationCreate() failed: -60008\n", stderr: "")
            ]
        ])
        let manager = SystemProxyManager(runCommand: mock.run, endpointProbe: { _, _ in true })

        do {
            _ = try await manager.listNetworkServices()
            XCTFail("Expected AuthorizationCreate output to be rejected")
        } catch let error as SystemProxyManagerError {
            XCTAssertTrue(error.localizedDescription.contains("AuthorizationCreate() failed: -60008"))
        }
    }

    func testListNetworkServicesFiltersHeaderAndDisabledServices() async throws {
        let mock = NetworkSetupMock(responses: [
            ["-listallnetworkservices"]: [
                ProcessResult(
                    terminationStatus: 0,
                    stdout: """
                    An asterisk (*) denotes that a network service is disabled.
                    Wi-Fi
                    *Thunderbolt Bridge
                    USB 10/100/1000 LAN
                    """,
                    stderr: ""
                )
            ]
        ])
        let manager = SystemProxyManager(runCommand: mock.run, endpointProbe: { _, _ in true })

        let services = try await manager.listNetworkServices()

        XCTAssertEqual(services, ["Wi-Fi", "USB 10/100/1000 LAN"])
    }

    func testListConfigurableNetworkServicesSkipsUnrecognizedServices() async throws {
        let mock = NetworkSetupMock(
            responses: [
                ["-listallnetworkservices"]: [
                    ProcessResult(terminationStatus: 0, stdout: "Wi-Fi\nStale VPN\n", stderr: "")
                ],
                ["-getwebproxy", "Wi-Fi"]: [
                    Self.proxyResult(enabled: false, server: "", port: 0)
                ],
                ["-getwebproxy", "Stale VPN"]: [
                    ProcessResult(terminationStatus: 1, stdout: "Stale VPN is not a recognized network service.\n", stderr: "")
                ]
            ]
        )
        let manager = SystemProxyManager(runCommand: mock.run, endpointProbe: { _, _ in true })

        let services = try await manager.listConfigurableNetworkServices()

        XCTAssertEqual(services, ["Wi-Fi"])
    }

    func testEnableSystemProxyRefusesWhenProxyPortIsUnavailable() async throws {
        let mock = NetworkSetupMock()
        let manager = SystemProxyManager(runCommand: mock.run, endpointProbe: { _, _ in false })

        do {
            try await manager.enableSystemProxy(services: ["Wi-Fi"])
            XCTFail("Expected unavailable local proxy port to fail")
        } catch let error as SystemProxyManagerError {
            XCTAssertTrue(error.localizedDescription.contains("127.0.0.1:9809"))
        }

        let calls = await mock.recordedCalls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testEnableSystemProxyRestoresPreviousStateWhenLaterServiceFails() async throws {
        let failingCommand = ["-setwebproxy", "Broken VPN", "127.0.0.1", "9809"]
        let mock = NetworkSetupMock(
            responses: [
                failingCommand: [
                    ProcessResult(terminationStatus: 1, stdout: "", stderr: "The parameters were not valid.\n")
                ]
            ],
            defaultResponse: Self.proxyResult(enabled: true, server: "old.proxy.local", port: 8080)
        )
        let manager = SystemProxyManager(runCommand: mock.run, endpointProbe: { _, _ in true })

        do {
            try await manager.enableSystemProxy(services: ["Wi-Fi", "Broken VPN"])
            XCTFail("Expected failing service to trigger rollback")
        } catch let error as SystemProxyManagerError {
            XCTAssertTrue(error.localizedDescription.contains("parameters"))
        }

        let calls = await mock.recordedCalls()
        XCTAssertTrue(calls.contains(["-setwebproxy", "Wi-Fi", "old.proxy.local", "8080"]))
        XCTAssertTrue(calls.contains(["-setsecurewebproxystate", "Wi-Fi", "on"]))
        XCTAssertTrue(calls.contains(["-setsocksfirewallproxystate", "Wi-Fi", "on"]))
    }

    func testEnableSystemProxySetsBypassDomainsAndReturnsSnapshots() async throws {
        let mock = NetworkSetupMock(
            responses: [
                ["-getwebproxy", "Wi-Fi"]: [
                    Self.proxyResult(enabled: false, server: "old.proxy.local", port: 8080)
                ],
                ["-getsecurewebproxy", "Wi-Fi"]: [
                    Self.proxyResult(enabled: false, server: "old.proxy.local", port: 8080)
                ],
                ["-getsocksfirewallproxy", "Wi-Fi"]: [
                    Self.proxyResult(enabled: false, server: "old.proxy.local", port: 8080)
                ],
                ["-getproxybypassdomains", "Wi-Fi"]: [
                    ProcessResult(terminationStatus: 0, stdout: "localhost\n*.local\n", stderr: "")
                ]
            ]
        )
        let manager = SystemProxyManager(runCommand: mock.run, endpointProbe: { _, _ in true })

        let snapshots = try await manager.enableSystemProxy(
            services: ["Wi-Fi"],
            bypassDomains: ["localhost", "*.local", "192.168.0.0/16"]
        )

        let calls = await mock.recordedCalls()
        XCTAssertEqual(snapshots.first?.bypassDomains, ["localhost", "*.local"])
        XCTAssertTrue(calls.contains(["-setproxybypassdomains", "Wi-Fi", "localhost", "*.local", "192.168.0.0/16"]))
    }

    func testRestoreRestoresBypassDomains() async throws {
        let mock = NetworkSetupMock()
        let manager = SystemProxyManager(runCommand: mock.run, endpointProbe: { _, _ in true })

        try await manager.restore([
            NetworkServiceProxyState(
                serviceName: "Wi-Fi",
                httpEnabled: false,
                httpsEnabled: false,
                socksEnabled: false,
                bypassDomains: ["localhost", "*.local"]
            )
        ])

        let calls = await mock.recordedCalls()
        XCTAssertTrue(calls.contains(["-setproxybypassdomains", "Wi-Fi", "localhost", "*.local"]))
    }

    func testRestoreClearsEmptyBypassDomainsWithNetworksetupEmptySentinel() async throws {
        let mock = NetworkSetupMock()
        let manager = SystemProxyManager(runCommand: mock.run, endpointProbe: { _, _ in true })

        try await manager.restore([
            NetworkServiceProxyState(
                serviceName: "Wi-Fi",
                httpEnabled: false,
                httpsEnabled: false,
                socksEnabled: false,
                bypassDomains: []
            )
        ])

        let calls = await mock.recordedCalls()
        XCTAssertTrue(calls.contains(["-setproxybypassdomains", "Wi-Fi", "Empty"]))
        XCTAssertFalse(calls.contains(["-setproxybypassdomains", "Wi-Fi"]))
    }

    private static func proxyResult(enabled: Bool, server: String, port: Int) -> ProcessResult {
        ProcessResult(
            terminationStatus: 0,
            stdout: """
            Enabled: \(enabled ? "Yes" : "No")
            Server: \(server)
            Port: \(port)
            Authenticated Proxy Enabled: 0
            """,
            stderr: ""
        )
    }
}

private actor NetworkSetupMock {
    private var responses: [[String]: [ProcessResult]]
    private let defaultResponse: ProcessResult
    private var calls: [[String]] = []

    init(
        responses: [[String]: [ProcessResult]] = [:],
        defaultResponse: ProcessResult = ProcessResult(terminationStatus: 0, stdout: "", stderr: "")
    ) {
        self.responses = responses
        self.defaultResponse = defaultResponse
    }

    func run(_ executableURL: URL, _ arguments: [String]) async throws -> ProcessResult {
        calls.append(arguments)
        guard var queue = responses[arguments], !queue.isEmpty else {
            return defaultResponse
        }
        let response = queue.removeFirst()
        responses[arguments] = queue
        return response
    }

    func recordedCalls() -> [[String]] {
        calls
    }
}
