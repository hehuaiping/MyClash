import Foundation
import MyClashCore

@main
struct MyClashCLI {
    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func run() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let command = arguments.first ?? "help"

        switch command {
        case "paths":
            let paths = try makePaths()
            try paths.createDirectories()
            print(paths.baseDirectory.path)

        case "init-config":
            let paths = try makePaths()
            try paths.createDirectories()
            let profileManager = ProfileManager(paths: paths)
            let secret = try loadControllerSecret()
            let raw = """
            proxies: []
            proxy-groups: []
            rules:
              - MATCH,DIRECT
            """
            let profile = try await profileManager.createLocalProfile(name: "default", rawConfig: raw)
            let generated = try await profileManager.generateRuntimeConfig(for: profile, secret: secret)
            try await profileManager.installRuntimeConfig(from: generated)
            print(paths.runtimeConfigURL.path)

        case "energy-policy":
            let policy = EnergyPolicy.default
            print("activeTrafficInterval=\(policy.activeTrafficInterval)")
            print("idleTrafficInterval=\(policy.idleTrafficInterval)")
            print("healthCheck=\(policy.minimumHealthCheckInterval)...\(policy.maximumHealthCheckInterval)")
            print("maxConcurrentDelayTests=\(policy.maximumConcurrentDelayTests)")

        case "core-info":
            let manager = try CoreBinaryManager(paths: makePaths())
            let info = await manager.installedInfo()
            print("path=\(info.url.path)")
            print("exists=\(info.exists)")
            print("executable=\(info.isExecutable)")
            print("sha256=\(info.sha256 ?? "-")")
            print("version=\(info.versionDescription ?? "-")")

        case "prepare-runtime":
            let paths = try makePaths()
            try paths.createDirectories()
            try await CoreManager(paths: paths).prepareRuntimeResources()
            print(paths.runtimeDirectory.path)

        case "core-url":
            let version = arguments.dropFirst().first ?? "v1.19.24"
            let manager = try CoreBinaryManager(paths: makePaths())
            print(try manager.releaseDownloadURL(version: version).absoluteString)

        case "install-core":
            guard let path = arguments.dropFirst().first else {
                throw SelfTestError("install-core requires a local executable or .gz path")
            }
            let manager = try CoreBinaryManager(paths: makePaths())
            let installed = try await manager.installCore(from: URL(fileURLWithPath: path))
            print(installed.path)

        case "download-core":
            guard let version = arguments.dropFirst().first else {
                throw SelfTestError("download-core requires a version, for example v1.19.24")
            }
            let manager = try CoreBinaryManager(paths: makePaths())
            let installed = try await manager.downloadAndInstall(version: version)
            print(installed.path)

        case "diagnostics":
            let paths = try makePaths()
            let service = DiagnosticsService(paths: paths)
            let snapshot = service.snapshot(coreStateDescription: "CLI diagnostics")
            let result = try service.exportPackage(snapshot: snapshot)
            print(result.directory.path)

        case "self-test":
            try runSelfTest()
            print("self-test passed")

        default:
            print("""
            MyClash development CLI

            Commands:
              paths          Create and print the Application Support directory.
              init-config    Create a minimal generated mihomo runtime config.
              energy-policy  Print low-energy runtime defaults.
              core-info      Print installed mihomo core information.
              prepare-runtime Copy local Geo data resources into mihomo runtime directory.
              core-url       Print a MetaCubeX/mihomo release asset URL.
              install-core   Install a local mihomo executable or .gz file.
              download-core  Download and install a mihomo release version.
              diagnostics    Export a redacted diagnostics package.
              self-test      Run dependency-free core assertions.
            """)
        }
    }

    private static func makePaths() throws -> AppPaths {
        if let home = ProcessInfo.processInfo.environment["MYCLASH_HOME"], !home.isEmpty {
            return try AppPaths(baseDirectory: URL(fileURLWithPath: home, isDirectory: true))
        }
        return try AppPaths()
    }

    private static func loadControllerSecret() throws -> String {
        if let devSecret = ProcessInfo.processInfo.environment["MYCLASH_DEV_SECRET"], !devSecret.isEmpty {
            return devSecret
        }
        return try KeychainSecretStore().loadOrCreateSecret(account: "controller")
    }

    private static func runSelfTest() throws {
        let raw = """
        mixed-port: 1234
        allow-lan: true
        profile:
          store-selected: false
        proxies: []
        rules:
          - MATCH,DIRECT
        """

        let generated = ProfileManager.makeGeneratedConfig(
            rawConfig: raw,
            secret: "secret",
            options: RuntimeConfigOptions(controllerPort: 9090)
        )

        try assert(!generated.contains("mixed-port: 1234"), "managed mixed-port should be replaced")
        try assert(!generated.contains("allow-lan: true"), "managed allow-lan should be replaced")
        try assert(generated.contains("mixed-port: 9809"), "generated mixed-port missing")
        try assert(generated.contains("external-controller: 127.0.0.1:9090"), "controller missing")
        try assert(generated.contains("secret: \"secret\""), "secret missing")
        try assert(generated.contains("proxies: []"), "raw proxy section should be preserved")

        let policy = EnergyPolicy.default
        try assert(
            policy.trafficInterval(upBytesPerSecond: 10_000, downBytesPerSecond: 10_000, isVisible: false)
                == policy.idleTrafficInterval,
            "invisible traffic should use idle interval"
        )
        try assert(
            policy.trafficInterval(upBytesPerSecond: 2_000, downBytesPerSecond: 1_000, isVisible: true)
                == policy.activeTrafficInterval,
            "visible busy traffic should use active interval"
        )
        try assert(
            policy.reconnectDelay(afterFailureCount: 20) == policy.websocketReconnectMaximumDelay,
            "reconnect delay should be capped"
        )
    }

    private static func assert(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw SelfTestError(message)
        }
    }
}

private struct SelfTestError: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
