import XCTest
@testable import MyClashCore

final class EnergyPolicyTests: XCTestCase {
    func testTrafficIntervalUsesIdleWhenInvisible() {
        let policy = EnergyPolicy.default
        XCTAssertEqual(
            policy.trafficInterval(upBytesPerSecond: 10_000, downBytesPerSecond: 10_000, isVisible: false),
            policy.idleTrafficInterval
        )
    }

    func testTrafficIntervalUsesActiveWhenVisibleAndBusy() {
        let policy = EnergyPolicy.default
        XCTAssertEqual(
            policy.trafficInterval(upBytesPerSecond: 2_000, downBytesPerSecond: 1_000, isVisible: true),
            policy.activeTrafficInterval
        )
    }

    func testReconnectDelayIsCapped() {
        XCTAssertEqual(
            EnergyPolicy.default.reconnectDelay(afterFailureCount: 20),
            EnergyPolicy.default.websocketReconnectMaximumDelay
        )
    }
}
