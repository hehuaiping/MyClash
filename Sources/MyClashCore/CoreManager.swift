import Darwin
import Foundation

public enum CoreState: Sendable, Equatable {
    case stopped
    case starting
    case running(version: String?)
    case stopping
    case failed(String)
}

public enum CoreManagerError: Error, LocalizedError {
    case missingCoreBinary(URL)
    case alreadyRunning
    case launchFailed(String)
    case healthCheckFailed(String)
    case portInUse(Int)

    public var errorDescription: String? {
        switch self {
        case let .missingCoreBinary(url):
            return "未找到可执行的 mihomo core：\(url.path)。"
        case .alreadyRunning:
            return "mihomo core 已在运行。"
        case let .launchFailed(message):
            return "启动 mihomo 失败：\(message)"
        case let .healthCheckFailed(message):
            return "mihomo 健康检查失败：\(message)"
        case let .portInUse(port):
            return "127.0.0.1:\(port) 已被占用，请先停止已有代理进程后再启动。"
        }
    }
}

public actor CoreManager {
    public private(set) var state: CoreState = .stopped

    private static let maxCoreLogBytes: UInt64 = 2 * 1024 * 1024

    private let paths: AppPaths
    private let energyPolicy: EnergyPolicy
    private var process: Process?
    private var logPipe: Pipe?
    private var logTask: Task<Void, Never>?

    public init(paths: AppPaths, energyPolicy: EnergyPolicy = .default) {
        self.paths = paths
        self.energyPolicy = energyPolicy
    }

    public func start(
        coreBinaryURL: URL? = nil,
        configURL: URL? = nil,
        controller: ControllerClient
    ) async throws {
        if process?.isRunning == true {
            throw CoreManagerError.alreadyRunning
        }

        state = .starting

        let binaryURL = coreBinaryURL ?? paths.coreBinaryURL()
        let runtimeConfigURL = configURL ?? paths.runtimeConfigURL
        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
            state = .failed("Core binary missing or not executable.")
            throw CoreManagerError.missingCoreBinary(binaryURL)
        }
        try stopStaleProcessFromPreviousRun()
        try ensurePortAvailable(9090)
        try ensurePortAvailable(9809)
        try prepareRuntimeResources()

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["-d", paths.runtimeDirectory.path, "-f", runtimeConfigURL.path]
        process.currentDirectoryURL = paths.runtimeDirectory

        let logPipe = Pipe()
        let logTask = startCoreLogPump(readHandle: logPipe.fileHandleForReading)
        process.standardOutput = logPipe
        process.standardError = logPipe

        do {
            try process.run()
        } catch {
            logTask.cancel()
            try? logPipe.fileHandleForReading.close()
            state = .failed(error.localizedDescription)
            throw CoreManagerError.launchFailed(error.localizedDescription)
        }

        self.process = process
        self.logPipe = logPipe
        self.logTask = logTask
        try "\(process.processIdentifier)\n".write(to: paths.pidFileURL, atomically: true, encoding: .utf8)

        process.terminationHandler = { _ in
            try? logPipe.fileHandleForReading.close()
            Task { [weak self] in
                await self?.markStoppedIfCurrentProcessFinished()
            }
        }

        do {
            let version = try await waitUntilHealthy(controller: controller)
            state = .running(version: version.version)
        } catch {
            stopProcess(process)
            state = .failed(error.localizedDescription)
            throw CoreManagerError.healthCheckFailed(error.localizedDescription)
        }
    }

    public func stop() {
        guard let process else {
            logTask?.cancel()
            logTask = nil
            logPipe = nil
            state = .stopped
            return
        }

        state = .stopping
        stopProcess(process)
        self.process = nil
        try? FileManager.default.removeItem(at: paths.pidFileURL)
        state = .stopped
    }

    public func restart(
        coreBinaryURL: URL? = nil,
        configURL: URL? = nil,
        controller: ControllerClient
    ) async throws {
        stop()
        try await start(coreBinaryURL: coreBinaryURL, configURL: configURL, controller: controller)
    }

    public func prepareRuntimeResources() throws {
        try GeoResourceManager(paths: paths).ensureBundledResources()
    }

    func prepareCoreLogForLaunch() throws {
        try CoreLogFile.prepare(
            paths: paths,
            maxBytes: Self.maxCoreLogBytes
        )
    }

    private func waitUntilHealthy(controller: ControllerClient) async throws -> MihomoVersion {
        var lastError: Error?
        for _ in 0..<6 {
            do {
                return try await controller.version()
            } catch {
                lastError = error
                try await Task.sleep(for: .seconds(1))
            }
        }
        throw lastError ?? CoreManagerError.healthCheckFailed("Controller did not become ready.")
    }

    private func stopStaleProcessFromPreviousRun() throws {
        guard let pidText = try? String(contentsOf: paths.pidFileURL, encoding: .utf8),
              let pid = Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0,
              pid != getpid()
        else {
            return
        }

        guard isProcessAlive(pid) else {
            try? FileManager.default.removeItem(at: paths.pidFileURL)
            return
        }

        guard processPath(for: pid)?.hasPrefix(paths.coreDirectory.path) == true else {
            throw CoreManagerError.launchFailed("PID 文件指向非 MyClash 管理的进程（PID \(pid)）。")
        }

        Darwin.kill(pid, SIGTERM)
        for _ in 0..<20 {
            if !isProcessAlive(pid) {
                try? FileManager.default.removeItem(at: paths.pidFileURL)
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        throw CoreManagerError.launchFailed("上次残留的 mihomo 进程仍在运行（PID \(pid)）。")
    }

    private func isProcessAlive(_ pid: Int32) -> Bool {
        Darwin.kill(pid, 0) == 0 || errno == EPERM
    }

    private func processPath(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else {
            return nil
        }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func ensurePortAvailable(_ port: UInt16) throws {
        let socketFileDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFileDescriptor >= 0 else {
            return
        }
        defer {
            close(socketFileDescriptor)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebound in
                connect(socketFileDescriptor, rebound, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if result == 0 {
            throw CoreManagerError.portInUse(Int(port))
        }
    }

    private func markStoppedIfCurrentProcessFinished() {
        guard process?.isRunning != true else {
            return
        }
        logTask = nil
        logPipe = nil
        process = nil
        if case .stopping = state {
            state = .stopped
        } else if case .stopped = state {
            return
        } else {
            state = .failed("mihomo exited unexpectedly.")
        }
    }

    private nonisolated func startCoreLogPump(readHandle: FileHandle) -> Task<Void, Never> {
        let sendableReadHandle = UncheckedSendableFileHandle(value: readHandle)
        let paths = paths
        let maxBytes = Self.maxCoreLogBytes

        return Task.detached(priority: .utility) {
            var writer = try? TruncatingCoreLogWriter(
                paths: paths,
                maxBytes: maxBytes
            )
            defer {
                try? writer?.close()
                try? sendableReadHandle.value.close()
            }

            while !Task.isCancelled {
                guard let data = try? sendableReadHandle.value.read(upToCount: 16 * 1024),
                      !data.isEmpty
                else {
                    break
                }

                do {
                    try writer?.write(data)
                } catch {
                    writer = nil
                }
            }
        }
    }

    private nonisolated func stopProcess(_ process: Process) {
        guard process.isRunning else {
            return
        }
        process.terminate()

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
            if process.isRunning {
                process.interrupt()
            }
        }
    }
}

private struct UncheckedSendableFileHandle: @unchecked Sendable {
    let value: FileHandle
}

private struct TruncatingCoreLogWriter {
    private let paths: AppPaths
    private let maxBytes: UInt64
    private var handle: FileHandle
    private var currentSize: UInt64

    init(paths: AppPaths, maxBytes: UInt64) throws {
        self.paths = paths
        self.maxBytes = maxBytes
        try CoreLogFile.prepare(paths: paths, maxBytes: maxBytes)
        self.handle = try FileHandle(forWritingTo: paths.coreLogURL)
        self.currentSize = try handle.seekToEnd()
    }

    mutating func write(_ data: Data) throws {
        if currentSize > maxBytes || currentSize + UInt64(data.count) > maxBytes {
            try truncate()
        }
        try handle.write(contentsOf: data)
        currentSize += UInt64(data.count)
    }

    mutating func close() throws {
        try handle.close()
    }

    private mutating func truncate() throws {
        try handle.truncate(atOffset: 0)
        try handle.seek(toOffset: 0)
        currentSize = 0
    }
}

private enum CoreLogFile {
    static func prepare(paths: AppPaths, maxBytes: UInt64) throws {
        try FileManager.default.createDirectory(
            at: paths.logsDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try removeLegacyArchives(paths: paths)

        if !FileManager.default.fileExists(atPath: paths.coreLogURL.path) {
            FileManager.default.createFile(
                atPath: paths.coreLogURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            )
        }

        try truncateIfNeeded(paths: paths, maxBytes: maxBytes)
    }

    private static func truncateIfNeeded(paths: AppPaths, maxBytes: UInt64) throws {
        let fileManager = FileManager.default
        guard let sizeValue = try? fileManager
            .attributesOfItem(atPath: paths.coreLogURL.path)[.size] as? NSNumber,
            sizeValue.uint64Value > maxBytes
        else {
            return
        }

        let handle = try FileHandle(forWritingTo: paths.coreLogURL)
        try handle.truncate(atOffset: 0)
        try handle.close()
    }

    private static func removeLegacyArchives(paths: AppPaths) throws {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: paths.logsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for url in urls where url.lastPathComponent.range(of: #"^core\.log\.\d+$"#, options: .regularExpression) != nil {
            try fileManager.removeItem(at: url)
        }
    }
}
