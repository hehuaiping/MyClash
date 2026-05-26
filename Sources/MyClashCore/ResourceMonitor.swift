import Darwin
import Foundation

public struct ResourceUsageSnapshot: Sendable, Equatable {
    public let processIdentifier: Int32
    public let sampledAt: Date
    public let userCPUTimeSeconds: Double
    public let systemCPUTimeSeconds: Double
    public let maximumResidentSetSizeBytes: UInt64
    public let cpuPercentSincePreviousSample: Double?

    public var totalCPUTimeSeconds: Double {
        userCPUTimeSeconds + systemCPUTimeSeconds
    }
}

public actor ResourceMonitor {
    private var previousSnapshot: ResourceUsageSnapshot?

    public init() {}

    public func sample() -> ResourceUsageSnapshot {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)

        let now = Date()
        let userSeconds = Self.seconds(from: usage.ru_utime)
        let systemSeconds = Self.seconds(from: usage.ru_stime)
        #if os(macOS)
        let residentBytes = UInt64(max(0, usage.ru_maxrss))
        #else
        let residentBytes = UInt64(max(0, usage.ru_maxrss)) * 1024
        #endif

        var cpuPercent: Double?
        if let previousSnapshot {
            let wallDelta = now.timeIntervalSince(previousSnapshot.sampledAt)
            let cpuDelta = (userSeconds + systemSeconds) - previousSnapshot.totalCPUTimeSeconds
            if wallDelta > 0, cpuDelta >= 0 {
                cpuPercent = min(999, (cpuDelta / wallDelta) * 100)
            }
        }

        let snapshot = ResourceUsageSnapshot(
            processIdentifier: getpid(),
            sampledAt: now,
            userCPUTimeSeconds: userSeconds,
            systemCPUTimeSeconds: systemSeconds,
            maximumResidentSetSizeBytes: residentBytes,
            cpuPercentSincePreviousSample: cpuPercent
        )
        previousSnapshot = snapshot
        return snapshot
    }

    private static func seconds(from time: timeval) -> Double {
        Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000
    }
}
