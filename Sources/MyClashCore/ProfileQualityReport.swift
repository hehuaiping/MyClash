import Foundation

public struct ProfileQualityReport: Codable, Sendable, Equatable {
    public let proxyCount: Int
    public let groupCount: Int
    public let providerCount: Int
    public let groupNodeCount: Int
    public let containsClientHint: Bool

    public init(
        proxyCount: Int,
        groupCount: Int,
        providerCount: Int,
        groupNodeCount: Int,
        containsClientHint: Bool
    ) {
        self.proxyCount = proxyCount
        self.groupCount = groupCount
        self.providerCount = providerCount
        self.groupNodeCount = groupNodeCount
        self.containsClientHint = containsClientHint
    }

    public var isLikelyDegradedSubscription: Bool {
        containsClientHint && proxyCount <= 1 && groupNodeCount <= 5
    }

    public var displayText: String {
        "节点 \(proxyCount) · 策略组 \(groupCount) · Provider \(providerCount)"
    }
}
