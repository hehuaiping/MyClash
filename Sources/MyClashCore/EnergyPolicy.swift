import Foundation

public struct EnergyPolicy: Sendable, Equatable {
    public var activeTrafficInterval: Duration
    public var idleTrafficInterval: Duration
    public var minimumHealthCheckInterval: Duration
    public var maximumHealthCheckInterval: Duration
    public var websocketReconnectBaseDelay: Duration
    public var websocketReconnectMaximumDelay: Duration
    public var maximumConcurrentDelayTests: Int
    public var idleBytesPerSecondThreshold: UInt64

    public init(
        activeTrafficInterval: Duration = .seconds(1),
        idleTrafficInterval: Duration = .seconds(5),
        minimumHealthCheckInterval: Duration = .seconds(10),
        maximumHealthCheckInterval: Duration = .seconds(60),
        websocketReconnectBaseDelay: Duration = .seconds(1),
        websocketReconnectMaximumDelay: Duration = .seconds(30),
        maximumConcurrentDelayTests: Int = 4,
        idleBytesPerSecondThreshold: UInt64 = 1024
    ) {
        self.activeTrafficInterval = activeTrafficInterval
        self.idleTrafficInterval = idleTrafficInterval
        self.minimumHealthCheckInterval = minimumHealthCheckInterval
        self.maximumHealthCheckInterval = maximumHealthCheckInterval
        self.websocketReconnectBaseDelay = websocketReconnectBaseDelay
        self.websocketReconnectMaximumDelay = websocketReconnectMaximumDelay
        self.maximumConcurrentDelayTests = Swift.max(1, maximumConcurrentDelayTests)
        self.idleBytesPerSecondThreshold = idleBytesPerSecondThreshold
    }

    public static let `default` = EnergyPolicy()

    public func trafficInterval(upBytesPerSecond: UInt64, downBytesPerSecond: UInt64, isVisible: Bool) -> Duration {
        guard isVisible else {
            return idleTrafficInterval
        }

        let total = upBytesPerSecond + downBytesPerSecond
        return total < idleBytesPerSecondThreshold ? idleTrafficInterval : activeTrafficInterval
    }

    public func reconnectDelay(afterFailureCount failureCount: Int) -> Duration {
        let clampedFailures = max(0, min(failureCount, 10))
        let baseNanoseconds = websocketReconnectBaseDelay.components.seconds * 1_000_000_000
            + Int64(websocketReconnectBaseDelay.components.attoseconds / 1_000_000_000)
        let maxNanoseconds = websocketReconnectMaximumDelay.components.seconds * 1_000_000_000
            + Int64(websocketReconnectMaximumDelay.components.attoseconds / 1_000_000_000)
        let multiplier = Int64(1 << clampedFailures)
        let delayed = min(baseNanoseconds * multiplier, maxNanoseconds)
        return .nanoseconds(delayed)
    }
}
