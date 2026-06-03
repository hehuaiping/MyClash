import Foundation

public struct RuntimeConfigOptions: Sendable, Equatable {
    public var mixedPort: Int
    public var controllerHost: String
    public var controllerPort: Int
    public var allowLAN: Bool
    public var mode: String
    public var logLevel: String
    public var bypassEntries: [String]
    public var geoAutoUpdate: Bool
    public var geoUpdateInterval: Int
    public var geodataMode: Bool
    public var geodataLoader: String
    public var geositeMatcher: String
    public var geoResourceURLs: [GeoResourceKind: URL]

    public init(
        mixedPort: Int = 9809,
        controllerHost: String = "127.0.0.1",
        controllerPort: Int = 9090,
        allowLAN: Bool = false,
        mode: String = "rule",
        logLevel: String = "info",
        bypassEntries: [String] = ProxyBypassRules.defaultEntries,
        geoAutoUpdate: Bool = false,
        geoUpdateInterval: Int = 24,
        geodataMode: Bool = true,
        geodataLoader: String = "memconservative",
        geositeMatcher: String = "succinct",
        geoResourceURLs: [GeoResourceKind: URL] = [:]
    ) {
        self.mixedPort = mixedPort
        self.controllerHost = controllerHost
        self.controllerPort = controllerPort
        self.allowLAN = allowLAN
        self.mode = mode
        self.logLevel = logLevel
        self.bypassEntries = ProxyBypassRules.normalize(bypassEntries)
        self.geoAutoUpdate = geoAutoUpdate
        self.geoUpdateInterval = geoUpdateInterval
        self.geodataMode = geodataMode
        self.geodataLoader = geodataLoader
        self.geositeMatcher = geositeMatcher
        self.geoResourceURLs = GeoResourceManager.defaultURLsByKind().merging(geoResourceURLs) { _, new in new }
    }

    public var externalController: String {
        "\(controllerHost):\(controllerPort)"
    }
}

public struct Profile: Sendable, Equatable {
    public let id: String
    public let name: String
    public let directory: URL
    public let rawConfigURL: URL
    public let overrideConfigURL: URL
    public let generatedConfigURL: URL
    public let metadataURL: URL
    public let metadata: ProfileMetadata

    public init(id: String, name: String, directory: URL, metadata: ProfileMetadata? = nil) {
        self.id = id
        self.name = name
        self.directory = directory
        self.rawConfigURL = directory.appendingPathComponent("raw.yaml")
        self.overrideConfigURL = directory.appendingPathComponent("override.yaml")
        self.generatedConfigURL = directory.appendingPathComponent("generated.yaml")
        self.metadataURL = directory.appendingPathComponent("metadata.json")
        self.metadata = metadata ?? ProfileMetadata(id: id, name: name, source: .file)
    }
}

public enum ProfileSourceType: String, Codable, Sendable, Equatable {
    case file
    case url
}

public struct ProfileSubscriptionInfo: Codable, Sendable, Equatable {
    public var rawValue: String
    public var upload: Int
    public var download: Int
    public var total: Int
    public var expire: Int

    public init(rawValue: String, upload: Int = 0, download: Int = 0, total: Int = 0, expire: Int = 0) {
        self.rawValue = rawValue
        self.upload = upload
        self.download = download
        self.total = total
        self.expire = expire
    }

    enum CodingKeys: String, CodingKey {
        case rawValue
        case upload
        case download
        case total
        case expire
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.rawValue = try container.decode(String.self, forKey: .rawValue)
        self.upload = try container.decodeIfPresent(Int.self, forKey: .upload) ?? 0
        self.download = try container.decodeIfPresent(Int.self, forKey: .download) ?? 0
        self.total = try container.decodeIfPresent(Int.self, forKey: .total) ?? 0
        self.expire = try container.decodeIfPresent(Int.self, forKey: .expire) ?? 0
    }

    public static func parse(_ rawValue: String) -> ProfileSubscriptionInfo {
        let pairs = rawValue
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let values = pairs.reduce(into: [String: Int]()) { result, pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                return
            }
            result[parts[0]] = Int(parts[1])
        }
        return ProfileSubscriptionInfo(
            rawValue: rawValue,
            upload: values["upload"] ?? 0,
            download: values["download"] ?? 0,
            total: values["total"] ?? 0,
            expire: values["expire"] ?? 0
        )
    }
}

public struct ProfileMetadata: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var source: ProfileSourceType
    public var sourceURL: String?
    public var lastUpdateDate: Date?
    public var subscriptionInfo: ProfileSubscriptionInfo?
    public var selectedMap: [String: String]
    public var unfoldSet: Set<String>
    public var qualityReport: ProfileQualityReport?
    public var order: Int?

    public init(
        id: String,
        name: String,
        source: ProfileSourceType,
        sourceURL: String? = nil,
        lastUpdateDate: Date? = nil,
        subscriptionInfo: ProfileSubscriptionInfo? = nil,
        selectedMap: [String: String] = [:],
        unfoldSet: Set<String> = [],
        qualityReport: ProfileQualityReport? = nil,
        order: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.sourceURL = sourceURL
        self.lastUpdateDate = lastUpdateDate
        self.subscriptionInfo = subscriptionInfo
        self.selectedMap = selectedMap
        self.unfoldSet = unfoldSet
        self.qualityReport = qualityReport
        self.order = order
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case source
        case sourceURL
        case lastUpdateDate
        case subscriptionInfo
        case selectedMap
        case unfoldSet
        case qualityReport
        case order
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.source = try container.decode(ProfileSourceType.self, forKey: .source)
        self.sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        self.lastUpdateDate = try container.decodeIfPresent(Date.self, forKey: .lastUpdateDate)
        self.subscriptionInfo = try container.decodeIfPresent(ProfileSubscriptionInfo.self, forKey: .subscriptionInfo)
        self.selectedMap = try container.decodeIfPresent([String: String].self, forKey: .selectedMap) ?? [:]
        self.unfoldSet = try container.decodeIfPresent(Set<String>.self, forKey: .unfoldSet) ?? []
        self.qualityReport = try container.decodeIfPresent(ProfileQualityReport.self, forKey: .qualityReport)
        self.order = try container.decodeIfPresent(Int.self, forKey: .order)
    }
}

public struct ProfileProxyGroup: Sendable, Equatable {
    public let name: String
    public let type: String
    public let now: String
    public let all: [String]

    public init(name: String, type: String, now: String, all: [String]) {
        self.name = name
        self.type = type
        self.now = now
        self.all = all
    }
}

public struct ProfileProxyProvider: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let type: String
    public let path: String?
    public let url: String?
    public let interval: Int?
    public let healthCheckEnabled: Bool

    public init(
        name: String,
        type: String,
        path: String? = nil,
        url: String? = nil,
        interval: Int? = nil,
        healthCheckEnabled: Bool = false
    ) {
        self.name = name
        self.type = type
        self.path = path
        self.url = url
        self.interval = interval
        self.healthCheckEnabled = healthCheckEnabled
    }
}

public enum ProfileManagerError: Error, LocalizedError {
    case emptyProfile
    case profileNotFound(String)
    case invalidPort(Int)
    case invalidProfileData(URL)
    case profileDownloadFailed(String)
    case profileTooLarge
    case degradedDownloadedProfile(ProfileQualityReport)

    public var errorDescription: String? {
        switch self {
        case .emptyProfile:
            return "Profile config is empty."
        case let .profileNotFound(id):
            return "Profile not found: \(id)."
        case let .invalidPort(port):
            return "Invalid port: \(port)."
        case let .invalidProfileData(url):
            return "Profile file is not valid UTF-8 text: \(url.path)."
        case let .profileDownloadFailed(message):
            return "Profile download failed: \(message)."
        case .profileTooLarge:
            return "Profile file exceeds the 16 MB limit."
        case let .degradedDownloadedProfile(report):
            return "订阅服务端返回了客户端不兼容的降级配置（\(report.displayText)）。请检查订阅链接或稍后重试。"
        }
    }
}

public actor ProfileManager {
    public let paths: AppPaths
    private let validator: MihomoConfigValidator
    private let runtimeConfigBuilder: RuntimeConfigBuilder
    private let downloadSession: URLSession

    public init(
        paths: AppPaths,
        validator: MihomoConfigValidator? = nil,
        runtimeConfigBuilder: RuntimeConfigBuilder = RuntimeConfigBuilder(),
        downloadSession: URLSession = .shared
    ) {
        self.paths = paths
        self.validator = validator ?? MihomoConfigValidator(
            coreBinaryURL: paths.coreBinaryURL(),
            runtimeDirectory: paths.runtimeDirectory
        )
        self.runtimeConfigBuilder = runtimeConfigBuilder
        self.downloadSession = downloadSession
    }

    public func createLocalProfile(name: String, rawConfig: String) async throws -> Profile {
        let trimmed = rawConfig.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProfileManagerError.emptyProfile
        }

        try paths.createDirectories()

        let id = Self.stableIdentifier(for: name)
        let directory = paths.profilesDirectory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let metadata = ProfileMetadata(
            id: id,
            name: name,
            source: .file,
            lastUpdateDate: Date()
        )
        return try await commitProfile(rawConfig: rawConfig, metadata: metadata, directory: directory)
    }

    public func importProfile(from fileURL: URL, name: String? = nil) async throws -> Profile {
        let data = try Data(contentsOf: fileURL)
        guard let rawConfig = String(data: data, encoding: .utf8) else {
            throw ProfileManagerError.invalidProfileData(fileURL)
        }

        let profileName = resolvedProfileName(name, fallbackURL: fileURL)
        let id = Self.stableIdentifier(for: profileName)
        let directory = paths.profilesDirectory.appendingPathComponent(id, isDirectory: true)
        let metadata = ProfileMetadata(
            id: id,
            name: profileName,
            source: .file,
            sourceURL: fileURL.path,
            lastUpdateDate: Date()
        )
        return try await commitProfile(rawConfig: rawConfig, metadata: metadata, directory: directory)
    }

    public func downloadProfile(from url: URL, name: String? = nil, maxBytes: Int = 16 * 1024 * 1024) async throws -> Profile {
        let downloaded = try await downloadRawProfile(from: url, maxBytes: maxBytes)
        let profileName = resolvedDownloadedProfileName(
            explicitName: name,
            url: url,
            contentDisposition: downloaded.contentDisposition
        )
        let id = Self.stableIdentifier(for: profileName)
        let directory = paths.profilesDirectory.appendingPathComponent(id, isDirectory: true)
        let metadata = ProfileMetadata(
            id: id,
            name: profileName,
            source: .url,
            sourceURL: url.absoluteString,
            lastUpdateDate: Date(),
            subscriptionInfo: downloaded.subscriptionInfo,
            qualityReport: downloaded.qualityReport
        )
        return try await commitProfile(rawConfig: downloaded.rawConfig, metadata: metadata, directory: directory)
    }

    public func updateProfile(id: String, maxBytes: Int = 16 * 1024 * 1024) async throws -> Profile {
        let currentProfile = try profile(id: id)
        guard currentProfile.metadata.source == .url,
              let sourceURL = currentProfile.metadata.sourceURL,
              let url = URL(string: sourceURL)
        else {
            return currentProfile
        }

        let downloaded = try await downloadRawProfile(from: url, maxBytes: maxBytes)
        var metadata = currentProfile.metadata
        metadata.lastUpdateDate = Date()
        metadata.subscriptionInfo = downloaded.subscriptionInfo
        metadata.qualityReport = downloaded.qualityReport
        return try await commitProfile(
            rawConfig: downloaded.rawConfig,
            metadata: metadata,
            directory: currentProfile.directory
        )
    }

    public func deleteProfile(id: String) throws {
        let target = try profile(id: id)
        try FileManager.default.removeItem(at: target.directory)
    }

    public func profile(id: String, name: String? = nil) throws -> Profile {
        let directory = paths.profilesDirectory.appendingPathComponent(id, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw ProfileManagerError.profileNotFound(id)
        }
        let metadata = try loadMetadata(id: id, directory: directory, fallbackName: name ?? id)
        return Profile(id: id, name: name ?? metadata.name, directory: directory, metadata: metadata)
    }

    public func listProfiles() throws -> [Profile] {
        guard FileManager.default.fileExists(atPath: paths.profilesDirectory.path) else {
            return []
        }

        return try FileManager.default
            .contentsOfDirectory(at: paths.profilesDirectory, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                return values?.isDirectory == true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { directory in
                let id = directory.lastPathComponent
                let metadata = try loadMetadata(id: id, directory: directory, fallbackName: id)
                return Profile(id: id, name: metadata.name, directory: directory, metadata: metadata)
            }
    }

    public func generateRuntimeConfig(
        for profile: Profile,
        secret: String,
        options: RuntimeConfigOptions = RuntimeConfigOptions()
    ) async throws -> URL {
        try validate(options: options)

        let rawConfig = try String(contentsOf: profile.rawConfigURL, encoding: .utf8)
        let overrideConfig = (try? String(contentsOf: profile.overrideConfigURL, encoding: .utf8)) ?? ""
        let generated = runtimeConfigBuilder.build(
            rawConfig: rawConfig,
            overrideConfig: overrideConfig,
            secret: secret,
            options: options
        )
        let stagedGeneratedURL = profile.directory.appendingPathComponent("generated.yaml.tmp-\(UUID().uuidString)")
        try generated.write(to: stagedGeneratedURL, atomically: true, encoding: .utf8)
        try setPrivateFilePermissions(stagedGeneratedURL)
        try await validator.validateIfAvailable(stagedGeneratedURL)
        try replaceItem(at: profile.generatedConfigURL, with: stagedGeneratedURL)
        return profile.generatedConfigURL
    }

    public func installRuntimeConfig(from generatedConfigURL: URL) throws {
        try paths.createDirectories()
        if FileManager.default.fileExists(atPath: paths.runtimeConfigURL.path) {
            try FileManager.default.removeItem(at: paths.runtimeConfigURL)
        }
        try FileManager.default.copyItem(at: generatedConfigURL, to: paths.runtimeConfigURL)
        try setPrivateFilePermissions(paths.runtimeConfigURL)
    }

    public func proxyPreview(for profile: Profile) throws -> [ProfileProxyGroup] {
        let rawConfig = try String(contentsOf: profile.rawConfigURL, encoding: .utf8)
        return ClashConfigDocument(raw: rawConfig).applyingSelections(profile.metadata.selectedMap)
    }

    public func proxyProviders(for profile: Profile) throws -> [ProfileProxyProvider] {
        let rawConfig = try String(contentsOf: profile.rawConfigURL, encoding: .utf8)
        return ClashConfigDocument(raw: rawConfig).proxyProviders()
    }

    public func saveSelectedProxy(profileID: String, groupName: String, proxyName: String) throws -> Profile {
        let profile = try profile(id: profileID)
        var metadata = profile.metadata
        metadata.selectedMap[groupName] = proxyName
        try writeMetadata(metadata, to: profile.metadataURL)
        return Profile(id: profile.id, name: metadata.name, directory: profile.directory, metadata: metadata)
    }

    public func saveUnfoldSet(profileID: String, unfoldSet: Set<String>) throws -> Profile {
        let profile = try profile(id: profileID)
        var metadata = profile.metadata
        metadata.unfoldSet = unfoldSet
        try writeMetadata(metadata, to: profile.metadataURL)
        return Profile(id: profile.id, name: metadata.name, directory: profile.directory, metadata: metadata)
    }

    public func saveOverrideConfig(profileID: String, overrideConfig: String) async throws -> Profile {
        let profile = try profile(id: profileID)
        let stagedOverrideURL = profile.directory.appendingPathComponent("override.yaml.tmp-\(UUID().uuidString)")
        try overrideConfig.write(to: stagedOverrideURL, atomically: true, encoding: .utf8)
        try setPrivateFilePermissions(stagedOverrideURL)

        let rawConfig = try String(contentsOf: profile.rawConfigURL, encoding: .utf8)
        let generated = runtimeConfigBuilder.build(
            rawConfig: rawConfig,
            overrideConfig: overrideConfig,
            secret: "validation-secret"
        )
        let stagedGeneratedURL = profile.directory.appendingPathComponent("override-validation.yaml.tmp-\(UUID().uuidString)")
        try generated.write(to: stagedGeneratedURL, atomically: true, encoding: .utf8)
        try setPrivateFilePermissions(stagedGeneratedURL)
        try await validator.validateIfAvailable(stagedGeneratedURL)
        try? FileManager.default.removeItem(at: stagedGeneratedURL)

        try replaceItem(at: profile.overrideConfigURL, with: stagedOverrideURL)
        return profile
    }

    public static func makeGeneratedConfig(
        rawConfig: String,
        overrideConfig: String = "",
        secret: String,
        options: RuntimeConfigOptions = RuntimeConfigOptions()
    ) -> String {
        RuntimeConfigBuilder().build(rawConfig: rawConfig, overrideConfig: overrideConfig, secret: secret, options: options)
    }

    public static func makeProxyPreview(rawConfig: String) -> [ProfileProxyGroup] {
        ClashConfigDocument(raw: rawConfig).proxyPreview()
    }

    public static func makeProxyProviders(rawConfig: String) -> [ProfileProxyProvider] {
        ClashConfigDocument(raw: rawConfig).proxyProviders()
    }

    public static func qualityReport(rawConfig: String) -> ProfileQualityReport {
        ClashConfigDocument(raw: rawConfig).qualityReport()
    }

    public static func stableIdentifier(for name: String) -> String {
        let normalized = name
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9_-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return normalized.isEmpty ? UUID().uuidString.lowercased() : normalized
    }

    private func validate(options: RuntimeConfigOptions) throws {
        for port in [options.mixedPort, options.controllerPort] {
            guard (1...65535).contains(port) else {
                throw ProfileManagerError.invalidPort(port)
            }
        }
    }

    private func setPrivateFilePermissions(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func resolvedProfileName(_ name: String?, fallbackURL: URL) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }

        let lastPathComponent = fallbackURL.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return lastPathComponent.isEmpty ? "imported-profile" : lastPathComponent
    }

    private func resolvedDownloadedProfileName(explicitName: String?, url: URL, contentDisposition: String?) -> String {
        let trimmed = explicitName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }

        if let filename = filename(fromContentDisposition: contentDisposition), !filename.isEmpty {
            return filename
        }

        let lastPathComponent = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return lastPathComponent.isEmpty ? "downloaded-profile" : lastPathComponent
    }

    private func filename(fromContentDisposition value: String?) -> String? {
        guard let value else {
            return nil
        }

        let fields = value.split(separator: ";").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for field in fields {
            let lowercased = field.lowercased()
            if lowercased.hasPrefix("filename*="),
               let filename = field.split(separator: "=", maxSplits: 1).last {
                let rawValue = String(filename).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if let encoded = rawValue.split(separator: "'", omittingEmptySubsequences: false).last,
                   let decoded = String(encoded).removingPercentEncoding {
                    return stripYAMLExtension(decoded)
                }
            }

            if lowercased.hasPrefix("filename="),
               let filename = field.split(separator: "=", maxSplits: 1).last {
                return stripYAMLExtension(String(filename).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))
            }
        }
        return nil
    }

    private func stripYAMLExtension(_ value: String) -> String {
        if value.lowercased().hasSuffix(".yaml") || value.lowercased().hasSuffix(".yml") {
            return URL(fileURLWithPath: value).deletingPathExtension().lastPathComponent
        }
        return value
    }

    private func downloadRawProfile(from url: URL, maxBytes: Int) async throws -> DownloadedProfile {
        var bestDegradedReport: ProfileQualityReport?
        var lastError: Error?

        for userAgent in Self.profileDownloadUserAgents {
            do {
                let downloaded = try await downloadRawProfile(from: url, maxBytes: maxBytes, userAgent: userAgent)
                if downloaded.qualityReport.isLikelyDegradedSubscription {
                    bestDegradedReport = downloaded.qualityReport
                    continue
                }
                return downloaded
            } catch {
                lastError = error
            }
        }

        if let bestDegradedReport {
            throw ProfileManagerError.degradedDownloadedProfile(bestDegradedReport)
        }
        if let lastError {
            throw lastError
        }
        throw ProfileManagerError.profileDownloadFailed("未能下载配置")
    }

    private func downloadRawProfile(from url: URL, maxBytes: Int, userAgent: String) async throws -> DownloadedProfile {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-yaml,text/yaml,text/plain,*/*", forHTTPHeaderField: "Accept")

        let (data, response) = try await downloadSession.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw ProfileManagerError.profileDownloadFailed("HTTP \(httpResponse.statusCode)")
        }
        guard data.count <= maxBytes else {
            throw ProfileManagerError.profileTooLarge
        }
        guard let rawConfig = String(data: data, encoding: .utf8) else {
            throw ProfileManagerError.invalidProfileData(url)
        }

        let httpResponse = response as? HTTPURLResponse
        let qualityReport = Self.qualityReport(rawConfig: rawConfig)
        return DownloadedProfile(
            rawConfig: rawConfig,
            contentDisposition: httpResponse?.value(forHTTPHeaderField: "Content-Disposition"),
            subscriptionInfo: httpResponse?
                .value(forHTTPHeaderField: "Subscription-Userinfo")
                .map(ProfileSubscriptionInfo.parse),
            qualityReport: qualityReport
        )
    }

    private static let profileDownloadUserAgents = [
        "MyClash/v0.3.0 clash-verge Platform/darwin",
        "FlClash/v0.8.0 clash-verge Platform/darwin",
        "clash-verge/v2.0.0",
        "mihomo",
        "Clash.Meta"
    ]

    private func commitProfile(rawConfig: String, metadata: ProfileMetadata, directory: URL) async throws -> Profile {
        let trimmed = rawConfig.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProfileManagerError.emptyProfile
        }
        var metadata = metadata
        metadata.qualityReport = Self.qualityReport(rawConfig: rawConfig)

        try paths.createDirectories()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let profile = Profile(id: metadata.id, name: metadata.name, directory: directory, metadata: metadata)
        let stagedRawURL = directory.appendingPathComponent("raw.yaml.tmp-\(UUID().uuidString)")
        try rawConfig.write(to: stagedRawURL, atomically: true, encoding: .utf8)
        try setPrivateFilePermissions(stagedRawURL)
        try await validator.validateIfAvailable(stagedRawURL)
        try replaceItem(at: profile.rawConfigURL, with: stagedRawURL)
        if !FileManager.default.fileExists(atPath: profile.overrideConfigURL.path) {
            try "".write(to: profile.overrideConfigURL, atomically: true, encoding: .utf8)
            try setPrivateFilePermissions(profile.overrideConfigURL)
        }
        try writeMetadata(metadata, to: profile.metadataURL)
        return profile
    }

    private func loadMetadata(id: String, directory: URL, fallbackName: String) throws -> ProfileMetadata {
        let metadataURL = directory.appendingPathComponent("metadata.json")
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            return ProfileMetadata(id: id, name: fallbackName, source: .file)
        }

        let data = try Data(contentsOf: metadataURL)
        var metadata = try JSONDecoder().decode(ProfileMetadata.self, from: data)
        if metadata.id != id {
            metadata.id = id
        }
        if metadata.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata.name = fallbackName
        }
        return metadata
    }

    private func writeMetadata(_ metadata: ProfileMetadata, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        let stagedURL = url.deletingLastPathComponent().appendingPathComponent("metadata.json.tmp-\(UUID().uuidString)")
        try data.write(to: stagedURL, options: .atomic)
        try setPrivateFilePermissions(stagedURL)
        try replaceItem(at: url, with: stagedURL)
    }

    private func replaceItem(at destinationURL: URL, with sourceURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: sourceURL)
        } else {
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        }
        try setPrivateFilePermissions(destinationURL)
    }

}

private struct DownloadedProfile: Sendable {
    let rawConfig: String
    let contentDisposition: String?
    let subscriptionInfo: ProfileSubscriptionInfo?
    let qualityReport: ProfileQualityReport
}
