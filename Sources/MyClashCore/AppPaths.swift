import Foundation

public struct AppPaths: Sendable {
    public let appName: String
    public let baseDirectory: URL
    public let coreDirectory: URL
    public let profilesDirectory: URL
    public let runtimeDirectory: URL
    public let logsDirectory: URL
    public let downloadsDirectory: URL

    public init(appName: String = "MyClash", baseDirectory: URL? = nil) throws {
        self.appName = appName

        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let applicationSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.baseDirectory = applicationSupport.appendingPathComponent(appName, isDirectory: true)
        }

        self.coreDirectory = self.baseDirectory.appendingPathComponent("core", isDirectory: true)
        self.profilesDirectory = self.baseDirectory.appendingPathComponent("profiles", isDirectory: true)
        self.runtimeDirectory = self.baseDirectory.appendingPathComponent("runtime", isDirectory: true)
        self.logsDirectory = self.baseDirectory.appendingPathComponent("logs", isDirectory: true)
        self.downloadsDirectory = self.baseDirectory.appendingPathComponent("downloads", isDirectory: true)
    }

    public func createDirectories() throws {
        let directories = [
            baseDirectory,
            coreDirectory,
            profilesDirectory,
            runtimeDirectory,
            logsDirectory,
            downloadsDirectory
        ]

        for directory in directories {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }

    public func coreBinaryURL(for architecture: String = RuntimeArchitecture.current.rawValue) -> URL {
        coreDirectory.appendingPathComponent("mihomo-darwin-\(architecture)")
    }

    public var runtimeConfigURL: URL {
        runtimeDirectory.appendingPathComponent("config.yaml")
    }

    public var pidFileURL: URL {
        runtimeDirectory.appendingPathComponent("mihomo.pid")
    }

    public var coreLogURL: URL {
        logsDirectory.appendingPathComponent("core.log")
    }
}

public enum RuntimeArchitecture: String, Sendable {
    case arm64
    case amd64

    public static var current: RuntimeArchitecture {
        #if arch(arm64)
        return .arm64
        #else
        return .amd64
        #endif
    }
}
