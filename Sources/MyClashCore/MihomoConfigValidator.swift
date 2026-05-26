import Foundation

public enum MihomoConfigValidationError: Error, LocalizedError, Sendable, Equatable {
    case invalidConfig(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidConfig(message):
            return "mihomo 配置校验失败：\(message)"
        }
    }
}

public struct MihomoConfigValidator: Sendable {
    public let coreBinaryURL: URL
    public let runtimeDirectory: URL
    private let runner: ProcessRunner

    public init(coreBinaryURL: URL, runtimeDirectory: URL, runner: ProcessRunner = ProcessRunner()) {
        self.coreBinaryURL = coreBinaryURL
        self.runtimeDirectory = runtimeDirectory
        self.runner = runner
    }

    public var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: coreBinaryURL.path)
    }

    public func validateIfAvailable(_ configURL: URL) async throws {
        guard isAvailable else {
            return
        }

        try FileManager.default.createDirectory(
            at: runtimeDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let result = try await runner.run(
            coreBinaryURL,
            arguments: ["-t", "-d", runtimeDirectory.path, "-f", configURL.path]
        )
        guard result.terminationStatus == 0 else {
            let message = [result.stderr, result.stdout]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw MihomoConfigValidationError.invalidConfig(message.isEmpty ? "mihomo exited with \(result.terminationStatus)" : message)
        }
    }
}
