import XCTest
@testable import MyClashCore

final class ProfileManagerTests: XCTestCase {
    func testGeneratedConfigOverridesManagedKeys() {
        let raw = """
        mixed-port: 1234
        allow-lan: true
        geodata-mode: false
        geo-auto-update: true
        geox-url:
          geoip: "https://example.com/old-geoip.dat"
          geosite: "https://example.com/old-geosite.dat"
          mmdb: "https://example.com/old.mmdb"
          asn: "https://example.com/old-asn.mmdb"
        tun:
          enable: true
          stack: mixed
        external-ui: dashboard
        profile:
          store-selected: false
        proxies: []
        rules:
          - MATCH,DIRECT
        """

        let generated = ProfileManager.makeGeneratedConfig(
            rawConfig: raw,
            secret: "secret",
            options: RuntimeConfigOptions(controllerPort: 9090)
        )

        XCTAssertFalse(generated.contains("mixed-port: 1234"))
        XCTAssertFalse(generated.contains("allow-lan: true"))
        XCTAssertFalse(generated.contains("https://example.com/old-geoip.dat"))
        XCTAssertFalse(generated.contains("https://example.com/old-geosite.dat"))
        XCTAssertFalse(generated.contains("https://example.com/old.mmdb"))
        XCTAssertFalse(generated.contains("https://example.com/old-asn.mmdb"))
        XCTAssertFalse(generated.contains("tun:"))
        XCTAssertFalse(generated.contains("external-ui: dashboard"))
        XCTAssertTrue(generated.contains("external-ui: \"\""))
        XCTAssertTrue(generated.contains("mixed-port: 9809"))
        XCTAssertTrue(generated.contains("external-controller: 127.0.0.1:9090"))
        XCTAssertTrue(generated.contains("secret: \"secret\""))
        XCTAssertTrue(generated.contains("geodata-mode: true"))
        XCTAssertTrue(generated.contains("geodata-loader: memconservative"))
        XCTAssertTrue(generated.contains("geosite-matcher: succinct"))
        XCTAssertTrue(generated.contains("geo-auto-update: false"))
        XCTAssertTrue(generated.contains("geo-update-interval: 24"))
        XCTAssertTrue(generated.contains("geox-url:"))
        XCTAssertTrue(generated.contains("geoip: \"https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat\""))
        XCTAssertTrue(generated.contains("geosite: \"https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat\""))
        XCTAssertTrue(generated.contains("mmdb: \"https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb\""))
        XCTAssertTrue(generated.contains("asn: \"https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/GeoLite2-ASN.mmdb\""))
        XCTAssertTrue(generated.contains("proxies: []"))
    }

    func testGeneratedConfigUsesCustomGeoResourceURLs() {
        let raw = """
        proxies: []
        rules:
          - MATCH,DIRECT
        """

        let generated = ProfileManager.makeGeneratedConfig(
            rawConfig: raw,
            secret: "secret",
            options: RuntimeConfigOptions(
                geoResourceURLs: [
                    .geoIP: URL(string: "https://mirror.example/geoip.dat")!,
                    .geoSite: URL(string: "https://mirror.example/geosite.dat")!,
                    .mmdb: URL(string: "https://mirror.example/geoip.metadb")!,
                    .asn: URL(string: "https://mirror.example/asn.mmdb")!
                ]
            )
        )

        XCTAssertTrue(generated.contains("geoip: \"https://mirror.example/geoip.dat\""))
        XCTAssertTrue(generated.contains("geosite: \"https://mirror.example/geosite.dat\""))
        XCTAssertTrue(generated.contains("mmdb: \"https://mirror.example/geoip.metadb\""))
        XCTAssertTrue(generated.contains("asn: \"https://mirror.example/asn.mmdb\""))
    }

    func testGeneratedConfigAppliesOverrideBeforeManagedKeys() {
        let raw = """
        mixed-port: 1234
        mode: global
        dns:
          enable: true
          enhanced-mode: fake-ip
        proxy-providers:
          Remote:
            type: http
            url: https://example.com/sub.yaml
            path: ./remote.yaml
        rule-providers:
          Reject:
            type: http
            behavior: domain
            url: https://example.com/reject.yaml
            path: ./reject.yaml
        proxies: []
        rules:
          - MATCH,DIRECT
        """
        let override = """
        mixed-port: 2222
        dns:
          enable: false
          enhanced-mode: redir-host
        rules:
          - DOMAIN-SUFFIX,example.com,DIRECT
          - MATCH,DIRECT
        """

        let generated = ProfileManager.makeGeneratedConfig(
            rawConfig: raw,
            overrideConfig: override,
            secret: "secret",
            options: RuntimeConfigOptions(mode: "rule")
        )

        XCTAssertFalse(generated.contains("mixed-port: 1234"))
        XCTAssertFalse(generated.contains("mixed-port: 2222"))
        XCTAssertTrue(generated.contains("mixed-port: 9809"))
        XCTAssertTrue(generated.contains("mode: rule"))
        XCTAssertTrue(generated.contains("proxy-providers:"))
        XCTAssertTrue(generated.contains("rule-providers:"))
        XCTAssertFalse(generated.contains("enhanced-mode: fake-ip"))
        XCTAssertTrue(generated.contains("enhanced-mode: redir-host"))
        XCTAssertTrue(generated.contains("DOMAIN-SUFFIX,example.com,DIRECT"))
    }

    func testGeneratedConfigPrependsProxyBypassRules() {
        let raw = """
        proxies: []
        rules:
          - MATCH,Proxy
        """

        let generated = ProfileManager.makeGeneratedConfig(
            rawConfig: raw,
            secret: "secret",
            options: RuntimeConfigOptions(
                bypassEntries: ["example.test", "*.corp", "192.168.50.0/24", "127.0.0.1", "::1"]
            )
        )

        XCTAssertTrue(generated.contains("  - DOMAIN-SUFFIX,example.test,DIRECT"))
        XCTAssertTrue(generated.contains("  - DOMAIN-SUFFIX,corp,DIRECT"))
        XCTAssertTrue(generated.contains("  - IP-CIDR,192.168.50.0/24,DIRECT,no-resolve"))
        XCTAssertTrue(generated.contains("  - IP-CIDR,127.0.0.1/32,DIRECT,no-resolve"))
        XCTAssertTrue(generated.contains("  - IP-CIDR6,::1/128,DIRECT,no-resolve"))
        XCTAssertTrue(generated.range(of: "DOMAIN-SUFFIX,example.test,DIRECT")!.lowerBound < generated.range(of: "MATCH,Proxy")!.lowerBound)
    }

    func testGeneratedConfigKeepsSubscriptionRuleIndentationWhenPrependingBypassRules() {
        let raw = """
        proxies: []
        rules:
            - 'DOMAIN-SUFFIX,google.com,OKZTWO'
            - 'MATCH,OKZTWO'
        """

        let generated = ProfileManager.makeGeneratedConfig(
            rawConfig: raw,
            secret: "secret",
            options: RuntimeConfigOptions(bypassEntries: ["localhost"])
        )

        let lines = generated.components(separatedBy: .newlines)
        XCTAssertTrue(generated.contains("    - DOMAIN,localhost,DIRECT"))
        XCTAssertTrue(generated.contains("    - 'DOMAIN-SUFFIX,google.com,OKZTWO'"))
        XCTAssertFalse(lines.contains("  - DOMAIN,localhost,DIRECT"))
        XCTAssertTrue(generated.range(of: "DOMAIN,localhost,DIRECT")!.lowerBound < generated.range(of: "DOMAIN-SUFFIX,google.com,OKZTWO")!.lowerBound)
    }

    func testImportProfileCreatesOverrideFile() async throws {
        let baseURL = temporaryDirectory()
        let sourceURL = baseURL.appendingPathComponent("Work Config.yaml")
        try """
        proxies: []
        rules:
          - MATCH,DIRECT
        """.write(to: sourceURL, atomically: true, encoding: .utf8)

        let paths = try AppPaths(baseDirectory: baseURL.appendingPathComponent("app", isDirectory: true))
        let manager = ProfileManager(paths: paths)
        let profile = try await manager.importProfile(from: sourceURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: profile.overrideConfigURL.path))
        XCTAssertEqual(try String(contentsOf: profile.overrideConfigURL, encoding: .utf8), "")
    }

    func testStableIdentifierSanitizesName() {
        XCTAssertEqual(ProfileManager.stableIdentifier(for: "My Default Profile"), "my-default-profile")
        XCTAssertFalse(ProfileManager.stableIdentifier(for: "默认配置").isEmpty)
    }

    func testImportProfileFromLocalFile() async throws {
        let baseURL = temporaryDirectory()
        let sourceURL = baseURL.appendingPathComponent("Work Config.yaml")
        try """
        proxies: []
        proxy-groups: []
        rules:
          - MATCH,DIRECT
        """.write(to: sourceURL, atomically: true, encoding: .utf8)

        let paths = try AppPaths(baseDirectory: baseURL.appendingPathComponent("app", isDirectory: true))
        let manager = ProfileManager(paths: paths)
        let profile = try await manager.importProfile(from: sourceURL)

        XCTAssertEqual(profile.id, "work-config")
        XCTAssertTrue(FileManager.default.fileExists(atPath: profile.rawConfigURL.path))
        XCTAssertEqual(
            try String(contentsOf: profile.rawConfigURL, encoding: .utf8),
            try String(contentsOf: sourceURL, encoding: .utf8)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: profile.metadataURL.path))
        XCTAssertEqual(profile.metadata.source, .file)
        XCTAssertEqual(profile.metadata.sourceURL, sourceURL.path)
    }

    func testImportProfileRunsMihomoValidationWhenValidatorIsAvailable() async throws {
        let baseURL = temporaryDirectory()
        let coreURL = baseURL.appendingPathComponent("fake-mihomo")
        let markerURL = baseURL.appendingPathComponent("validator-args.txt")
        try """
        #!/bin/sh
        echo "$@" > "\(markerURL.path)"
        exit 0
        """.write(to: coreURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: coreURL.path)

        let sourceURL = baseURL.appendingPathComponent("Valid.yaml")
        try "proxies: []\nproxy-groups: []\nrules:\n  - MATCH,DIRECT\n"
            .write(to: sourceURL, atomically: true, encoding: .utf8)

        let paths = try AppPaths(baseDirectory: baseURL.appendingPathComponent("app", isDirectory: true))
        let validator = MihomoConfigValidator(coreBinaryURL: coreURL, runtimeDirectory: paths.runtimeDirectory)
        let manager = ProfileManager(paths: paths, validator: validator)
        _ = try await manager.importProfile(from: sourceURL)

        let arguments = try String(contentsOf: markerURL, encoding: .utf8)
        XCTAssertTrue(arguments.contains("-t"))
        XCTAssertTrue(arguments.contains("-f"))
    }

    func testImportProfileRejectsInvalidConfigWhenValidatorFails() async throws {
        let baseURL = temporaryDirectory()
        let coreURL = baseURL.appendingPathComponent("fake-mihomo")
        try """
        #!/bin/sh
        echo "invalid config" >&2
        exit 1
        """.write(to: coreURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: coreURL.path)

        let sourceURL = baseURL.appendingPathComponent("Invalid.yaml")
        try "not: valid enough for fake validator\n"
            .write(to: sourceURL, atomically: true, encoding: .utf8)

        let paths = try AppPaths(baseDirectory: baseURL.appendingPathComponent("app", isDirectory: true))
        let validator = MihomoConfigValidator(coreBinaryURL: coreURL, runtimeDirectory: paths.runtimeDirectory)
        let manager = ProfileManager(paths: paths, validator: validator)

        do {
            _ = try await manager.importProfile(from: sourceURL)
            XCTFail("Expected validation failure")
        } catch let error as MihomoConfigValidationError {
            XCTAssertEqual(error, .invalidConfig("invalid config"))
        }
    }

    func testSaveOverrideConfigRegeneratesRuntimeConfigWithOverride() async throws {
        let baseURL = temporaryDirectory()
        let paths = try AppPaths(baseDirectory: baseURL.appendingPathComponent("app", isDirectory: true))
        let manager = ProfileManager(paths: paths)
        let raw = """
        dns:
          enable: true
        proxies: []
        rules:
          - MATCH,DIRECT
        """
        let profile = try await manager.createLocalProfile(name: "Override", rawConfig: raw)

        _ = try await manager.saveOverrideConfig(
            profileID: profile.id,
            overrideConfig: """
            dns:
              enable: false
            """
        )
        let generatedURL = try await manager.generateRuntimeConfig(for: profile, secret: "secret")
        let generated = try String(contentsOf: generatedURL, encoding: .utf8)

        XCTAssertFalse(generated.contains("enable: true"))
        XCTAssertTrue(generated.contains("enable: false"))
    }

    func testSelectedProxyIsPersistedAndAppliedToPreview() async throws {
        let baseURL = temporaryDirectory()
        let paths = try AppPaths(baseDirectory: baseURL.appendingPathComponent("app", isDirectory: true))
        let manager = ProfileManager(paths: paths)
        let raw = """
        proxies:
          - {name: Node A, type: ss}
          - {name: Node B, type: ss}
        proxy-groups:
          - {name: Select, type: select, proxies: [Node A, Node B]}
        rules:
          - MATCH,Select
        """
        let profile = try await manager.createLocalProfile(name: "Persisted", rawConfig: raw)
        _ = try await manager.saveSelectedProxy(profileID: profile.id, groupName: "Select", proxyName: "Node B")

        let reloaded = try await manager.profile(id: profile.id)
        let preview = try await manager.proxyPreview(for: reloaded)

        XCTAssertEqual(reloaded.metadata.selectedMap["Select"], "Node B")
        XCTAssertEqual(preview.first?.now, "Node B")
    }

    func testProxyPreviewParsesGroupsAndNodes() {
        let raw = """
        proxies:
          - {name: Auto, type: ss, server: example.com, port: 443}
          - name: Manual
            type: vmess
            server: example.org
        proxy-groups:
          - name: Select
            type: select
            proxies:
              - Auto
              - Manual
              - DIRECT
          - {name: Inline, type: fallback, proxies: [Auto, DIRECT]}
        rules:
          - MATCH,Select
        """

        let preview = ProfileManager.makeProxyPreview(rawConfig: raw)

        XCTAssertEqual(preview.count, 2)
        XCTAssertEqual(preview[0].name, "Select")
        XCTAssertEqual(preview[0].type, "select")
        XCTAssertEqual(preview[0].now, "Auto")
        XCTAssertEqual(preview[0].all, ["Auto", "Manual", "DIRECT"])
        XCTAssertEqual(preview[1].name, "Inline")
        XCTAssertEqual(preview[1].all, ["Auto", "DIRECT"])
    }

    func testProxyPreviewFallsBackToProxyListWhenGroupsAreMissing() {
        let raw = """
        proxies:
          - name: Node A
            type: ss
          - {name: Node B, type: ss}
        rules:
          - MATCH,DIRECT
        """

        let preview = ProfileManager.makeProxyPreview(rawConfig: raw)

        XCTAssertEqual(preview.count, 1)
        XCTAssertEqual(preview[0].name, "节点")
        XCTAssertEqual(preview[0].all, ["Node A", "Node B"])
    }

    func testProxyProvidersParsesProviderMetadata() {
        let raw = """
        proxy-providers:
          RemoteNodes:
            type: http
            url: https://example.com/sub.yaml
            path: ./providers/remote.yaml
            interval: 3600
            health-check:
              enable: true
              url: https://www.gstatic.com/generate_204
          InlineNodes: {type: file, path: ./providers/local.yaml}
        proxies: []
        rules:
          - MATCH,DIRECT
        """

        let providers = ProfileManager.makeProxyProviders(rawConfig: raw)

        XCTAssertEqual(providers.count, 2)
        XCTAssertEqual(providers[0].name, "RemoteNodes")
        XCTAssertEqual(providers[0].type, "http")
        XCTAssertEqual(providers[0].url, "https://example.com/sub.yaml")
        XCTAssertEqual(providers[0].path, "./providers/remote.yaml")
        XCTAssertEqual(providers[0].interval, 3600)
        XCTAssertTrue(providers[0].healthCheckEnabled)
        XCTAssertEqual(providers[1].name, "InlineNodes")
        XCTAssertEqual(providers[1].type, "file")
    }

    func testProxyPreviewParsesOKZInlineSubscriptionFormat() {
        let raw = """
        mixed-port: 9809
        allow-lan: true
        bind-address: '*'
        mode: rule
        log-level: info
        external-controller: '127.0.0.1:9090'
        dns:
            enable: true
            default-nameserver: ['tls://223.5.5.5', 'tls://223.6.6.6']
        proxies:
            - { name: '请下载客户端 见教程', type: trojan, server: ru0195.lv1.zero1890.com, port: 60194, password: 9db79adf-18ff-4bbd-b515-d4505870b375, udp: true, sni: russia.okzdns.com, skip-cert-verify: true }
        proxy-groups:
            - { name: OKZTWO, type: select, proxies: [自动选择, 故障转移, '请下载客户端 见教程'] }
            - { name: 自动选择, type: url-test, proxies: ['请下载客户端 见教程'], url: 'http://www.gstatic.com/generate_204', interval: 86400 }
            - { name: 故障转移, type: fallback, proxies: ['请下载客户端 见教程'], url: 'http://www.gstatic.com/generate_204', interval: 7200 }
        rules:
            - 'IP-CIDR,1.1.1.1/32,OKZTWO,no-resolve'
        """

        let preview = ProfileManager.makeProxyPreview(rawConfig: raw)

        XCTAssertEqual(preview.count, 3)
        XCTAssertEqual(preview[0].name, "OKZTWO")
        XCTAssertEqual(preview[0].type, "select")
        XCTAssertEqual(preview[0].now, "自动选择")
        XCTAssertEqual(preview[0].all, ["自动选择", "故障转移", "请下载客户端 见教程"])
        XCTAssertEqual(preview[1].name, "自动选择")
        XCTAssertEqual(preview[1].all, ["请下载客户端 见教程"])
        XCTAssertEqual(preview[2].name, "故障转移")
        XCTAssertEqual(preview[2].all, ["请下载客户端 见教程"])
    }

    func testProxyPreviewKeepsHashInsideQuotedScalar() {
        let raw = """
        proxies:
          - {name: 'Node #1', type: ss}
        proxy-groups:
          - {name: Select, type: select, proxies: ['Node #1', DIRECT]}
        rules:
          - MATCH,Select
        """

        let preview = ProfileManager.makeProxyPreview(rawConfig: raw)

        XCTAssertEqual(preview.first?.all, ["Node #1", "DIRECT"])
    }

    func testNodeCatalogBuildsRuntimeGroupsWithNodeTypes() {
        let collection = ProxyCollection(proxies: [
            "Select": ProxyItem(name: "Select", type: "Selector", now: "Node A", all: ["Node A", "DIRECT"], history: nil),
            "Node A": ProxyItem(name: "Node A", type: "ss", now: nil, all: nil, history: nil),
            "DIRECT": ProxyItem(name: "DIRECT", type: "Direct", now: nil, all: nil, history: nil)
        ])

        let catalog = NodeCatalogBuilder().runtimeCatalog(collection: collection)

        XCTAssertEqual(catalog.source, .runtime)
        XCTAssertEqual(catalog.groups.count, 1)
        XCTAssertEqual(catalog.groups[0].nodes[0], NodeItem(name: "Node A", type: "ss", isSelected: true))
        XCTAssertEqual(catalog.groups[0].nodes[1], NodeItem(name: "DIRECT", type: "Direct", isSelected: false))
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyClashProfileTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
