import CryptoKit
import Foundation

public struct CoreBinaryInfo: Sendable, Equatable {
    public let url: URL
    public let exists: Bool
    public let isExecutable: Bool
    public let sha256: String?
    public let versionDescription: String?

    public init(
        url: URL,
        exists: Bool,
        isExecutable: Bool,
        sha256: String?,
        versionDescription: String?
    ) {
        self.url = url
        self.exists = exists
        self.isExecutable = isExecutable
        self.sha256 = sha256
        self.versionDescription = versionDescription
    }
}

public enum CoreBinaryManagerError: Error, LocalizedError {
    case unsupportedArchitecture(String)
    case invalidVersion(String)
    case missingDownloadedFile
    case checksumMismatch(expected: String, actual: String)
    case decompressionFailed(String)
    case installFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedArchitecture(architecture):
            return "Unsupported mihomo architecture: \(architecture)."
        case let .invalidVersion(version):
            return "Invalid mihomo release version: \(version)."
        case .missingDownloadedFile:
            return "Downloaded core file does not exist."
        case let .checksumMismatch(expected, actual):
            return "Core checksum mismatch. Expected \(expected), got \(actual)."
        case let .decompressionFailed(message):
            return "Failed to decompress mihomo core: \(message)"
        case let .installFailed(message):
            return "Failed to install mihomo core: \(message)"
        }
    }
}

public struct CoreBinaryManager: Sendable {
    public let paths: AppPaths
    public let architecture: RuntimeArchitecture
    private let runner: ProcessRunner

    public init(
        paths: AppPaths,
        architecture: RuntimeArchitecture = .current,
        runner: ProcessRunner = ProcessRunner()
    ) {
        self.paths = paths
        self.architecture = architecture
        self.runner = runner
    }

    public var installedCoreURL: URL {
        paths.coreBinaryURL(for: architecture.rawValue)
    }

    public static func normalizedReleaseVersion(_ version: String) throws -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CoreBinaryManagerError.invalidVersion(version)
        }

        let normalized = trimmed.hasPrefix("v") ? trimmed : "v\(trimmed)"
        let pattern = #"^v[0-9]+(\.[0-9]+){1,3}([.+-][A-Za-z0-9._-]+)?$"#
        guard normalized.range(of: pattern, options: .regularExpression) != nil else {
            throw CoreBinaryManagerError.invalidVersion(version)
        }
        return normalized
    }

    public func releaseAssetName(version: String) throws -> String {
        let normalizedVersion = try Self.normalizedReleaseVersion(version)
        switch architecture {
        case .arm64:
            return "mihomo-darwin-arm64-\(normalizedVersion).gz"
        case .amd64:
            return "mihomo-darwin-amd64-compatible-\(normalizedVersion).gz"
        }
    }

    public func releaseDownloadURL(version: String) throws -> URL {
        let normalizedVersion = try Self.normalizedReleaseVersion(version)
        let assetName = try releaseAssetName(version: normalizedVersion)
        return URL(string: "https://github.com/MetaCubeX/mihomo/releases/download/\(normalizedVersion)/\(assetName)")!
    }

    public func installedInfo() async -> CoreBinaryInfo {
        let exists = FileManager.default.fileExists(atPath: installedCoreURL.path)
        let isExecutable = FileManager.default.isExecutableFile(atPath: installedCoreURL.path)
        let sha256 = exists ? (try? Self.sha256(of: installedCoreURL)) : nil
        let version = isExecutable ? (try? await versionDescription(binaryURL: installedCoreURL)) : nil
        return CoreBinaryInfo(
            url: installedCoreURL,
            exists: exists,
            isExecutable: isExecutable,
            sha256: sha256,
            versionDescription: version
        )
    }

    public func downloadAndInstall(version: String, expectedSHA256: String? = nil) async throws -> URL {
        try paths.createDirectories()
        let downloadURL = try releaseDownloadURL(version: version)
        let (temporaryURL, _) = try await URLSession.shared.download(from: downloadURL)
        let downloadedURL = paths.downloadsDirectory.appendingPathComponent(try releaseAssetName(version: version))

        if FileManager.default.fileExists(atPath: downloadedURL.path) {
            try FileManager.default.removeItem(at: downloadedURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: downloadedURL)
        return try await installCore(from: downloadedURL, expectedSHA256: expectedSHA256)
    }

    public func installCore(from sourceURL: URL, expectedSHA256: String? = nil) async throws -> URL {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw CoreBinaryManagerError.missingDownloadedFile
        }

        if let expectedSHA256 {
            let actualSHA256 = try Self.sha256(of: sourceURL)
            guard actualSHA256.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
                throw CoreBinaryManagerError.checksumMismatch(expected: expectedSHA256, actual: actualSHA256)
            }
        }

        try paths.createDirectories()
        let stagingURL = paths.coreDirectory.appendingPathComponent(".mihomo-install-\(UUID().uuidString)")
        let executableSourceURL: URL

        if sourceURL.pathExtension == "gz" {
            try await decompressGzip(sourceURL: sourceURL, destinationURL: stagingURL)
            executableSourceURL = stagingURL
        } else {
            try FileManager.default.copyItem(at: sourceURL, to: stagingURL)
            executableSourceURL = stagingURL
        }

        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableSourceURL.path)
            if FileManager.default.fileExists(atPath: installedCoreURL.path) {
                try FileManager.default.removeItem(at: installedCoreURL)
            }
            try FileManager.default.moveItem(at: executableSourceURL, to: installedCoreURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedCoreURL.path)
            return installedCoreURL
        } catch {
            try? FileManager.default.removeItem(at: stagingURL)
            throw CoreBinaryManagerError.installFailed(error.localizedDescription)
        }
    }

    public func versionDescription(binaryURL: URL? = nil) async throws -> String {
        let url = binaryURL ?? installedCoreURL
        let result = try await runner.run(url, arguments: ["-v"])
        let output = [result.stdout, result.stderr]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? "unknown" : output
    }

    public static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func decompressGzip(sourceURL: URL, destinationURL: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-dc", sourceURL.path]

        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        let stdout = try FileHandle(forWritingTo: destinationURL)
        defer {
            try? stdout.close()
        }

        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw CoreBinaryManagerError.decompressionFailed(error.localizedDescription)
        }

        let status = await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
        }
        guard status == 0 else {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8) ?? "gzip exited with \(status)"
            throw CoreBinaryManagerError.decompressionFailed(message)
        }
    }
}
