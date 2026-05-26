import XCTest
@testable import MyClashCore

final class ResourceMonitorTests: XCTestCase {
    func testResourceMonitorProducesSnapshot() async {
        let monitor = ResourceMonitor()
        let first = await monitor.sample()
        let second = await monitor.sample()

        XCTAssertGreaterThan(first.processIdentifier, 0)
        XCTAssertGreaterThanOrEqual(second.userCPUTimeSeconds, first.userCPUTimeSeconds)
        XCTAssertGreaterThanOrEqual(second.systemCPUTimeSeconds, first.systemCPUTimeSeconds)
        XCTAssertNotNil(second.cpuPercentSincePreviousSample)
    }
}
