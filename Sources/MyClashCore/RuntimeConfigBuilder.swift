import Foundation

public struct RuntimeConfigBuilder: Sendable {
    public static let managedTopLevelKeys: Set<String> = [
        "mixed-port",
        "allow-lan",
        "mode",
        "log-level",
        "external-controller",
        "external-ui",
        "external-ui-url",
        "interface-name",
        "secret",
        "profile",
        "geox-url",
        "geo-auto-update",
        "geo-update-interval",
        "geodata-mode",
        "geodata-loader",
        "geosite-matcher",
        // MyClash manages macOS system proxy mode only, so subscription TUN blocks
        // are deliberately stripped from runtime config.
        "tun"
    ]

    public init() {}

    public func build(
        rawConfig: String,
        overrideConfig: String = "",
        secret: String,
        options: RuntimeConfigOptions = RuntimeConfigOptions()
    ) -> String {
        var sanitized = ClashConfigDocument(raw: rawConfig)
            .applyingTopLevelOverride(overrideConfig, managedKeys: Self.managedTopLevelKeys)
        sanitized = ClashConfigDocument(raw: sanitized)
            .prependingRules(ProxyBypassRules.ruleLines(for: options.bypassEntries))
        if !sanitized.hasSuffix("\n") {
            sanitized.append("\n")
        }

        let geoIPURL = yamlQuoted(options.geoResourceURLs[.geoIP]?.absoluteString ?? "")
        let geoSiteURL = yamlQuoted(options.geoResourceURLs[.geoSite]?.absoluteString ?? "")
        let mmdbURL = yamlQuoted(options.geoResourceURLs[.mmdb]?.absoluteString ?? "")
        let asnURL = yamlQuoted(options.geoResourceURLs[.asn]?.absoluteString ?? "")
        let managed = """

        # Managed by MyClash. User subscription content is preserved in raw.yaml,
        # and user overrides are preserved in override.yaml.
        mixed-port: \(options.mixedPort)
        allow-lan: \(options.allowLAN ? "true" : "false")
        mode: \(options.mode)
        log-level: \(options.logLevel)
        external-controller: \(options.externalController)
        external-ui: ""
        external-ui-url: ""
        interface-name: ""
        secret: "\(secret)"
        profile:
          store-selected: true
          store-fake-ip: true
        geodata-mode: \(options.geodataMode ? "true" : "false")
        geodata-loader: \(options.geodataLoader)
        geosite-matcher: \(options.geositeMatcher)
        geo-auto-update: \(options.geoAutoUpdate ? "true" : "false")
        geo-update-interval: \(options.geoUpdateInterval)
        geox-url:
          geoip: \(geoIPURL)
          geosite: \(geoSiteURL)
          mmdb: \(mmdbURL)
          asn: \(asnURL)
        """

        return sanitized + managed + "\n"
    }

    private func yamlQuoted(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
