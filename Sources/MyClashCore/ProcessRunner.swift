import Foundation

public struct ProcessResult: Sendable, Equatable {
    public let terminationStatus: Int32
    public let stdout: String
    public let stderr: String
}

public enum ProcessRunnerError: Error, LocalizedError {
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .launchFailed(message):
            return message
        }
    }
}

public struct ProcessRunner: Sendable {
    public init() {}

    public func run(_ executableURL: URL, arguments: [String]) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(
                    returning: ProcessResult(
                        terminationStatus: finished.terminationStatus,
                        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                        stderr: String(data: stderrData, encoding: .utf8) ?? ""
                    )
                )
            }
        }
    }
}
