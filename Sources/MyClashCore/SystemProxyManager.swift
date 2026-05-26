import Darwin
import Foundation

public struct NetworkServiceProxyState: Sendable, Equatable, Codable {
    public var serviceName: String
    public var httpEnabled: Bool
    public var httpsEnabled: Bool
    public var socksEnabled: Bool
    public var httpServer: String?
    public var httpPort: Int?
    public var httpsServer: String?
    public var httpsPort: Int?
    public var socksServer: String?
    public var socksPort: Int?
    public var bypassDomains: [String]

    public init(
        serviceName: String,
        httpEnabled: Bool,
        httpsEnabled: Bool,
        socksEnabled: Bool,
        httpServer: String? = nil,
        httpPort: Int? = nil,
        httpsServer: String? = nil,
        httpsPort: Int? = nil,
        socksServer: String? = nil,
        socksPort: Int? = nil,
        bypassDomains: [String] = []
    ) {
        self.serviceName = serviceName
        self.httpEnabled = httpEnabled
        self.httpsEnabled = httpsEnabled
        self.socksEnabled = socksEnabled
        self.httpServer = httpServer
        self.httpPort = httpPort
        self.httpsServer = httpsServer
        self.httpsPort = httpsPort
        self.socksServer = socksServer
        self.socksPort = socksPort
        self.bypassDomains = bypassDomains
    }
}

public enum SystemProxyManagerError: Error, LocalizedError {
    case networkSetupFailed(String)
    case invalidNetworkSetupOutput(String)
    case noConfigurableNetworkServices
    case proxyEndpointUnavailable(host: String, port: Int)

    public var errorDescription: String? {
        switch self {
        case let .networkSetupFailed(message):
            return "系统代理设置失败：\(message)"
        case let .invalidNetworkSetupOutput(message):
            return "无法读取 macOS 网络服务列表：\(message)"
        case .noConfigurableNetworkServices:
            return "未检测到可配置的 macOS 网络服务。"
        case let .proxyEndpointUnavailable(host, port):
            return "MyClash 代理端口不可用：\(host):\(port)。请先启动 mihomo core 后再开启系统代理。"
        }
    }
}

public struct SystemProxyManager: Sendable {
    public typealias CommandRunner = @Sendable (URL, [String]) async throws -> ProcessResult
    public typealias EndpointProbe = @Sendable (String, Int) async -> Bool

    private let runCommand: CommandRunner
    private let endpointProbe: EndpointProbe
    private let networksetupURL = URL(fileURLWithPath: "/usr/sbin/networksetup")

    public init(
        runner: ProcessRunner = ProcessRunner(),
        endpointProbe: @escaping EndpointProbe = Self.isTCPPortOpen(host:port:)
    ) {
        self.runCommand = { executableURL, arguments in
            try await runner.run(executableURL, arguments: arguments)
        }
        self.endpointProbe = endpointProbe
    }

    public init(
        runCommand: @escaping CommandRunner,
        endpointProbe: @escaping EndpointProbe = Self.isTCPPortOpen(host:port:)
    ) {
        self.runCommand = runCommand
        self.endpointProbe = endpointProbe
    }

    public func listNetworkServices() async throws -> [String] {
        let result = try await runCommand(networksetupURL, ["-listallnetworkservices"])
        try validate(result, context: .listServices)
        let services = result.stdout
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty
                    && !line.hasPrefix("*")
                    && !line.localizedCaseInsensitiveContains("asterisk")
                    && !Self.looksLikeNetworkSetupError(line)
            }
        guard !services.isEmpty else {
            throw SystemProxyManagerError.noConfigurableNetworkServices
        }
        return services
    }

    public func listConfigurableNetworkServices() async throws -> [String] {
        let services = try await listNetworkServices()
        var configurable: [String] = []
        var lastFailure: Error?

        for service in services {
            do {
                _ = try await getProxyEndpoint(service: service, kind: .http)
                configurable.append(service)
            } catch let error as SystemProxyManagerError {
                if Self.isSkippableServiceProbeError(error) {
                    continue
                }
                lastFailure = error
            } catch {
                lastFailure = error
            }
        }

        if configurable.isEmpty {
            if let lastFailure {
                throw lastFailure
            }
            throw SystemProxyManagerError.noConfigurableNetworkServices
        }
        return configurable
    }

    @discardableResult
    public func enableSystemProxy(
        host: String = "127.0.0.1",
        port: Int = 9809,
        services: [String],
        bypassDomains: [String] = []
    ) async throws -> [NetworkServiceProxyState] {
        guard await endpointProbe(host, port) else {
            throw SystemProxyManagerError.proxyEndpointUnavailable(host: host, port: port)
        }

        let targetServices = try await configurableServices(from: services)
        var snapshots: [NetworkServiceProxyState] = []

        for service in targetServices {
            do {
                snapshots.append(try await proxyState(for: service))
                try await runNetworkSetup(["-setwebproxy", service, host, "\(port)"])
                try await runNetworkSetup(["-setsecurewebproxy", service, host, "\(port)"])
                try await runNetworkSetup(["-setsocksfirewallproxy", service, host, "\(port)"])
                let normalizedBypassDomains = ProxyBypassRules.normalize(bypassDomains)
                if !normalizedBypassDomains.isEmpty {
                    try await setProxyBypassDomains(service: service, domains: normalizedBypassDomains)
                }
                try await runNetworkSetup(["-setwebproxystate", service, "on"])
                try await runNetworkSetup(["-setsecurewebproxystate", service, "on"])
                try await runNetworkSetup(["-setsocksfirewallproxystate", service, "on"])
            } catch {
                try? await restore(snapshots)
                throw error
            }
        }
        return snapshots
    }

    public func disableSystemProxy(services: [String]) async throws {
        for service in try await configurableServices(from: services) {
            try await runNetworkSetup(["-setwebproxystate", service, "off"])
            try await runNetworkSetup(["-setsecurewebproxystate", service, "off"])
            try await runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
        }
    }

    public func restore(_ snapshots: [NetworkServiceProxyState]) async throws {
        for snapshot in snapshots {
            if let server = snapshot.httpServer, let port = snapshot.httpPort {
                try await runNetworkSetup(["-setwebproxy", snapshot.serviceName, server, "\(port)"])
            }
            if let server = snapshot.httpsServer, let port = snapshot.httpsPort {
                try await runNetworkSetup(["-setsecurewebproxy", snapshot.serviceName, server, "\(port)"])
            }
            if let server = snapshot.socksServer, let port = snapshot.socksPort {
                try await runNetworkSetup(["-setsocksfirewallproxy", snapshot.serviceName, server, "\(port)"])
            }
            try await setProxyBypassDomains(service: snapshot.serviceName, domains: snapshot.bypassDomains)
            try await runNetworkSetup(["-setwebproxystate", snapshot.serviceName, snapshot.httpEnabled ? "on" : "off"])
            try await runNetworkSetup(["-setsecurewebproxystate", snapshot.serviceName, snapshot.httpsEnabled ? "on" : "off"])
            try await runNetworkSetup(["-setsocksfirewallproxystate", snapshot.serviceName, snapshot.socksEnabled ? "on" : "off"])
        }
    }

    public func proxyState(for service: String) async throws -> NetworkServiceProxyState {
        let http = try await getProxyEndpoint(service: service, kind: .http)
        let https = try await getProxyEndpoint(service: service, kind: .https)
        let socks = try await getProxyEndpoint(service: service, kind: .socks)
        let bypassDomains = try await getProxyBypassDomains(service: service)
        return NetworkServiceProxyState(
            serviceName: service,
            httpEnabled: http.enabled,
            httpsEnabled: https.enabled,
            socksEnabled: socks.enabled,
            httpServer: http.server,
            httpPort: http.port,
            httpsServer: https.server,
            httpsPort: https.port,
            socksServer: socks.server,
            socksPort: socks.port,
            bypassDomains: bypassDomains
        )
    }

    private func runNetworkSetup(_ arguments: [String]) async throws {
        let result = try await runCommand(networksetupURL, arguments)
        try validate(result, context: .setting)
    }

    private func setProxyBypassDomains(service: String, domains: [String]) async throws {
        let normalizedDomains = ProxyBypassRules.normalize(domains)
        let arguments = ["-setproxybypassdomains", service] + (normalizedDomains.isEmpty ? ["Empty"] : normalizedDomains)
        try await runNetworkSetup(arguments)
    }

    private func validate(_ result: ProcessResult, context: NetworkSetupContext) throws {
        let output = [result.stderr, result.stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        if Self.looksLikeNetworkSetupError(output) {
            if context == .listServices || output.localizedCaseInsensitiveContains("AuthorizationCreate() failed") {
                throw SystemProxyManagerError.invalidNetworkSetupOutput(output)
            }
            throw SystemProxyManagerError.networkSetupFailed(output)
        }

        guard result.terminationStatus == 0 else {
            throw SystemProxyManagerError.networkSetupFailed(output.isEmpty ? "networksetup exited with \(result.terminationStatus)." : output)
        }
    }

    private func configurableServices(from services: [String]) async throws -> [String] {
        if services.isEmpty {
            return try await listConfigurableNetworkServices()
        }

        var configurable: [String] = []
        for service in services {
            do {
                _ = try await getProxyEndpoint(service: service, kind: .http)
                configurable.append(service)
            } catch let error as SystemProxyManagerError where Self.isSkippableServiceProbeError(error) {
                continue
            }
        }
        guard !configurable.isEmpty else {
            throw SystemProxyManagerError.noConfigurableNetworkServices
        }
        return configurable
    }

    private func getProxyEndpoint(service: String, kind: ProxyKind) async throws -> ProxyEndpoint {
        let result = try await runCommand(networksetupURL, [kind.readCommand, service])
        try validate(result, context: .probe)
        return ProxyEndpoint.parse(result.stdout)
    }

    private func getProxyBypassDomains(service: String) async throws -> [String] {
        let result = try await runCommand(networksetupURL, ["-getproxybypassdomains", service])
        try validate(result, context: .probe)
        return result.stdout
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.localizedCaseInsensitiveContains("there aren't any bypass domains") }
    }

    private static func isSkippableServiceProbeError(_ error: SystemProxyManagerError) -> Bool {
        switch error {
        case let .invalidNetworkSetupOutput(message), let .networkSetupFailed(message):
            return message.localizedCaseInsensitiveContains("not a recognized network service")
                || message.localizedCaseInsensitiveContains("is disabled")
        case .noConfigurableNetworkServices, .proxyEndpointUnavailable:
            return false
        }
    }

    private static func looksLikeNetworkSetupError(_ output: String) -> Bool {
        let lowercased = output.lowercased()
        return lowercased.contains("authorizationcreate() failed")
            || lowercased.contains("the parameters were not valid")
            || lowercased.contains("not a recognized network service")
            || lowercased.contains("you cannot make changes to network settings")
    }

    public static func isTCPPortOpen(host: String, port: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let socketFD = socket(AF_INET, SOCK_STREAM, 0)
                guard socketFD >= 0 else {
                    continuation.resume(returning: false)
                    return
                }
                defer { close(socketFD) }

                var timeout = timeval(tv_sec: 1, tv_usec: 0)
                setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

                var address = sockaddr_in()
                address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                address.sin_family = sa_family_t(AF_INET)
                address.sin_port = in_port_t(port).bigEndian
                guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
                    continuation.resume(returning: false)
                    return
                }

                let connected = withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                        connect(socketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                    }
                }
                continuation.resume(returning: connected)
            }
        }
    }
}

private enum NetworkSetupContext {
    case listServices
    case probe
    case setting
}

private enum ProxyKind {
    case http
    case https
    case socks

    var readCommand: String {
        switch self {
        case .http:
            return "-getwebproxy"
        case .https:
            return "-getsecurewebproxy"
        case .socks:
            return "-getsocksfirewallproxy"
        }
    }
}

private struct ProxyEndpoint: Sendable, Equatable {
    var enabled: Bool
    var server: String?
    var port: Int?

    static func parse(_ output: String) -> ProxyEndpoint {
        var enabled = false
        var server: String?
        var port: Int?

        for line in output.split(separator: "\n").map(String.init) {
            let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 2 else {
                continue
            }

            switch parts[0].lowercased() {
            case "enabled":
                enabled = parts[1].localizedCaseInsensitiveContains("yes")
                    || parts[1] == "1"
            case "server":
                server = parts[1].isEmpty ? nil : parts[1]
            case "port":
                port = Int(parts[1])
            default:
                continue
            }
        }

        return ProxyEndpoint(enabled: enabled, server: server, port: port)
    }
}
