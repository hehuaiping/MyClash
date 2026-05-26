import XCTest
@testable import MyClashCore

final class ProxyBypassRulesTests: XCTestCase {
    func testNormalizeTrimsDeduplicatesAndIgnoresComments() {
        let entries = ProxyBypassRules.normalize("""
        # local bypasses
        localhost
        LOCALHOST
        *.local, 192.168.0.0/16 # private lan
        "example.internal"
        '10.0.0.0/8'
        """)

        XCTAssertEqual(entries, [
            "localhost",
            "*.local",
            "192.168.0.0/16",
            "example.internal",
            "10.0.0.0/8"
        ])
    }

    func testRuleLinesMapDomainsIPsAndCIDRsToDirectRules() {
        let rules = ProxyBypassRules.ruleLines(for: [
            "localhost",
            "*.local",
            "example.internal",
            "127.0.0.1",
            "192.168.0.0/16",
            "::1",
            "fc00::/7"
        ])

        XCTAssertEqual(rules, [
            "  - DOMAIN,localhost,DIRECT",
            "  - DOMAIN-SUFFIX,local,DIRECT",
            "  - DOMAIN-SUFFIX,example.internal,DIRECT",
            "  - IP-CIDR,127.0.0.1/32,DIRECT,no-resolve",
            "  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve",
            "  - IP-CIDR6,::1/128,DIRECT,no-resolve",
            "  - IP-CIDR6,fc00::/7,DIRECT,no-resolve"
        ])
    }

    func testDefaultEntriesIncludePrivateAndLinkLocalNetworks() {
        XCTAssertTrue(ProxyBypassRules.defaultEntries.contains("10.0.0.0/8"))
        XCTAssertTrue(ProxyBypassRules.defaultEntries.contains("172.16.0.0/12"))
        XCTAssertTrue(ProxyBypassRules.defaultEntries.contains("192.168.0.0/16"))
        XCTAssertTrue(ProxyBypassRules.defaultEntries.contains("169.254.0.0/16"))
        XCTAssertTrue(ProxyBypassRules.defaultEntries.contains("fc00::/7"))
        XCTAssertTrue(ProxyBypassRules.defaultEntries.contains("fe80::/10"))
    }
}
