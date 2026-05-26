import Foundation

public struct DiagnosticsSnapshot: Sendable, Equatable {
    public var appName: String
    public var baseDirectory: String
    public var runtimeDirectory: String
    public var coreDirectory: String
    public var generatedAt: Date
    public var energyPolicy: EnergyPolicy
    public var coreStateDescription: String
    public var resourceUsage: ResourceUsageSnapshot?

    public init(
        appName: String,
        baseDirectory: String,
        runtimeDirectory: String,
        coreDirectory: String,
        generatedAt: Date = Date(),
        energyPolicy: EnergyPolicy,
        coreStateDescription: String,
        resourceUsage: ResourceUsageSnapshot? = nil
    ) {
        self.appName = appName
        self.baseDirectory = baseDirectory
        self.runtimeDirectory = runtimeDirectory
        self.coreDirectory = coreDirectory
        self.generatedAt = generatedAt
        self.energyPolicy = energyPolicy
        self.coreStateDescription = coreStateDescription
        self.resourceUsage = resourceUsage
    }
}

public struct DiagnosticsExportResult: Sendable, Equatable {
    public let directory: URL
    public let files: [String]

    public init(directory: URL, files: [String]) {
        self.directory = directory
        self.files = files
    }
}

public struct DiagnosticsService: Sendable {
    private let paths: AppPaths
    private let energyPolicy: EnergyPolicy

    public init(paths: AppPaths, energyPolicy: EnergyPolicy = .default) {
        self.paths = paths
        self.energyPolicy = energyPolicy
    }

    public func snapshot(coreStateDescription: String, resourceUsage: ResourceUsageSnapshot? = nil) -> DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            appName: paths.appName,
            baseDirectory: paths.baseDirectory.path,
            runtimeDirectory: paths.runtimeDirectory.path,
            coreDirectory: paths.coreDirectory.path,
            energyPolicy: energyPolicy,
            coreStateDescription: coreStateDescription,
            resourceUsage: resourceUsage
        )
    }

    public func writeSnapshot(_ snapshot: DiagnosticsSnapshot) throws -> URL {
        try paths.createDirectories()
        let url = paths.logsDirectory.appendingPathComponent("diagnostics.txt")
        try makeSnapshotText(snapshot).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public func exportPackage(snapshot: DiagnosticsSnapshot, logTailLimitBytes: UInt64 = 384 * 1024) throws -> DiagnosticsExportResult {
        try paths.createDirectories()

        let directory = paths.logsDirectory
            .appendingPathComponent("diagnostics-\(Self.timestamp(for: snapshot.generatedAt)).myclashdiagnostics", isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        var files: [String] = []
        try write(Self.redact(makeSnapshotText(snapshot)), to: directory.appendingPathComponent("diagnostics.txt"), files: &files)

        try copyRedactedFileIfExists(
            from: paths.runtimeConfigURL,
            to: directory.appendingPathComponent("runtime-config.redacted.yaml"),
            files: &files
        )

        try copyRedactedTailIfExists(
            from: paths.coreLogURL,
            to: directory.appendingPathComponent("core-log-tail.redacted.log"),
            limitBytes: logTailLimitBytes,
            files: &files
        )

        try exportProfiles(to: directory.appendingPathComponent("profiles", isDirectory: true), files: &files)
        try writeManifest(to: directory, snapshot: snapshot, files: &files)

        return DiagnosticsExportResult(directory: directory, files: files.sorted())
    }

    public static func redact(_ contents: String) -> String {
        var redacted = contents

        let sensitiveKeys = [
            "secret",
            "token",
            "access-token",
            "refresh-token",
            "authorization",
            "proxy-authorization",
            "password",
            "passwd",
            "pwd",
            "credential",
            "credentials",
            "private-key"
        ]
        let keyPattern = "(?im)^([\\t -]*)(\(sensitiveKeys.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")))([\\t -]*:[\\t -]*).*$"
        redacted = redacted.replacingOccurrences(
            of: keyPattern,
            with: "$1$2$3\"<redacted>\"",
            options: .regularExpression
        )

        let queryPattern = "(?i)([?&](?:token|access_token|refresh_token|secret|key|password|passwd|pwd|auth|subscription|sub)=)[^\\s&#]+"
        redacted = redacted.replacingOccurrences(
            of: queryPattern,
            with: "$1<redacted>",
            options: .regularExpression
        )

        let userInfoPattern = "(?i)([a-z][a-z0-9+.-]*://)([^/@\\s:]+)(?::([^/@\\s]+))?@"
        redacted = redacted.replacingOccurrences(
            of: userInfoPattern,
            with: "$1<redacted>@",
            options: .regularExpression
        )

        let bearerPattern = "(?i)(bearer|basic)[\\t ]+[A-Za-z0-9._~+/-]+=*"
        redacted = redacted.replacingOccurrences(
            of: bearerPattern,
            with: "$1 <redacted>",
            options: .regularExpression
        )

        return redacted
    }

    private func makeSnapshotText(_ snapshot: DiagnosticsSnapshot) -> String {
        """
        app: \(snapshot.appName)
        generatedAt: \(snapshot.generatedAt)
        baseDirectory: \(snapshot.baseDirectory)
        runtimeDirectory: \(snapshot.runtimeDirectory)
        coreDirectory: \(snapshot.coreDirectory)
        coreState: \(snapshot.coreStateDescription)
        activeTrafficInterval: \(snapshot.energyPolicy.activeTrafficInterval)
        idleTrafficInterval: \(snapshot.energyPolicy.idleTrafficInterval)
        minimumHealthCheckInterval: \(snapshot.energyPolicy.minimumHealthCheckInterval)
        maximumHealthCheckInterval: \(snapshot.energyPolicy.maximumHealthCheckInterval)
        maximumConcurrentDelayTests: \(snapshot.energyPolicy.maximumConcurrentDelayTests)
        cpuPercent: \(snapshot.resourceUsage?.cpuPercentSincePreviousSample.map { String(format: "%.2f", $0) } ?? "n/a")
        userCPUTimeSeconds: \(snapshot.resourceUsage.map { String(format: "%.3f", $0.userCPUTimeSeconds) } ?? "n/a")
        systemCPUTimeSeconds: \(snapshot.resourceUsage.map { String(format: "%.3f", $0.systemCPUTimeSeconds) } ?? "n/a")
        maximumResidentSetSizeBytes: \(snapshot.resourceUsage.map { "\($0.maximumResidentSetSizeBytes)" } ?? "n/a")
        """
    }

    private func exportProfiles(to directory: URL, files: inout [String]) throws {
        guard FileManager.default.fileExists(atPath: paths.profilesDirectory.path) else {
            return
        }

        let profiles = try FileManager.default
            .contentsOfDirectory(at: paths.profilesDirectory, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for profileDirectory in profiles {
            let profileName = profileDirectory.lastPathComponent
            try copyRedactedFileIfExists(
                from: profileDirectory.appendingPathComponent("raw.yaml"),
                to: directory.appendingPathComponent("\(profileName)-raw.redacted.yaml"),
                files: &files
            )
            try copyRedactedFileIfExists(
                from: profileDirectory.appendingPathComponent("generated.yaml"),
                to: directory.appendingPathComponent("\(profileName)-generated.redacted.yaml"),
                files: &files
            )
        }
    }

    private func copyRedactedFileIfExists(from source: URL, to destination: URL, files: inout [String]) throws {
        guard FileManager.default.fileExists(atPath: source.path) else {
            return
        }
        let contents = try String(contentsOf: source, encoding: .utf8)
        try write(Self.redact(contents), to: destination, files: &files)
    }

    private func copyRedactedTailIfExists(from source: URL, to destination: URL, limitBytes: UInt64, files: inout [String]) throws {
        guard FileManager.default.fileExists(atPath: source.path) else {
            return
        }

        let handle = try FileHandle(forReadingFrom: source)
        defer {
            try? handle.close()
        }

        let fileSize = try handle.seekToEnd()
        let startOffset = fileSize > limitBytes ? fileSize - limitBytes : 0
        try handle.seek(toOffset: startOffset)
        let data = try handle.readToEnd() ?? Data()
        let contents = String(decoding: data, as: UTF8.self)
        let prefix = startOffset > 0 ? "[truncated to last \(limitBytes) bytes]\n" : ""
        try write(Self.redact(prefix + contents), to: destination, files: &files)
    }

    private func write(_ contents: String, to url: URL, files: inout [String]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        files.append(url.lastPathComponent)
    }

    private func writeManifest(to directory: URL, snapshot: DiagnosticsSnapshot, files: inout [String]) throws {
        let includedFiles = files.sorted()
        let manifest = """
        {
          "app": "\(snapshot.appName)",
          "generatedAt": "\(snapshot.generatedAt)",
          "redaction": "Sensitive keys, authorization headers, URL user info, and sensitive query values are replaced with <redacted>.",
          "files": \(Self.jsonArray(includedFiles))
        }
        """
        try write(manifest, to: directory.appendingPathComponent("manifest.json"), files: &files)
    }

    private static func jsonArray(_ values: [String]) -> String {
        let encoded = values.map { value in
            "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        return "[\(encoded.joined(separator: ", "))]"
    }

    private static func timestamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
