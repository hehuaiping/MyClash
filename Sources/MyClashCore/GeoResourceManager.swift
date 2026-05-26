import Foundation

public enum GeoResourceKind: String, CaseIterable, Sendable, Codable, Identifiable {
    case geoIP = "geoip"
    case geoSite = "geosite"
    case mmdb = "mmdb"
    case asn = "asn"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .geoIP:
            return "GEOIP"
        case .geoSite:
            return "GEOSITE"
        case .mmdb:
            return "MMDB"
        case .asn:
            return "ASN"
        }
    }
}

public struct GeoResourceDefinition: Sendable, Equatable, Identifiable {
    public let kind: GeoResourceKind
    public let fileName: String
    public let sourceNames: [String]
    public let defaultURL: URL

    public var id: String { kind.id }
    public var label: String { kind.label }
}

public struct GeoResourceStatus: Sendable, Equatable, Identifiable {
    public let definition: GeoResourceDefinition
    public let fileURL: URL
    public let exists: Bool
    public let size: UInt64
    public let lastModified: Date?
    public let sourceURL: URL

    public var id: String { definition.id }
}

public enum GeoResourceManagerError: Error, LocalizedError {
    case invalidURL(String)
    case emptyDownload(GeoResourceKind)

    public var errorDescription: String? {
        switch self {
        case let .invalidURL(value):
            return "资源下载地址无效：\(value)"
        case let .emptyDownload(kind):
            return "\(kind.label) 下载结果为空。"
        }
    }
}

public struct GeoResourceManager: Sendable {
    public typealias Downloader = @Sendable (URL) async throws -> Data

    public static let definitions: [GeoResourceDefinition] = [
        GeoResourceDefinition(
            kind: .geoIP,
            fileName: "GeoIP.dat",
            sourceNames: ["GeoIP.dat", "GEOIP.dat", "geoip.dat"],
            defaultURL: URL(string: "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat")!
        ),
        GeoResourceDefinition(
            kind: .geoSite,
            fileName: "GeoSite.dat",
            sourceNames: ["GeoSite.dat", "GEOSITE.dat", "geosite.dat"],
            defaultURL: URL(string: "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat")!
        ),
        GeoResourceDefinition(
            kind: .mmdb,
            fileName: "GeoIP.metadb",
            sourceNames: ["GeoIP.metadb", "GEOIP.metadb", "geoip.metadb", "Country.mmdb", "country.mmdb"],
            defaultURL: URL(string: "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb")!
        ),
        GeoResourceDefinition(
            kind: .asn,
            fileName: "ASN.mmdb",
            sourceNames: ["ASN.mmdb", "asn.mmdb", "GeoLite2-ASN.mmdb", "geolite2-asn.mmdb"],
            defaultURL: URL(string: "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/GeoLite2-ASN.mmdb")!
        )
    ]

    private let paths: AppPaths
    private let searchDirectories: [URL]
    private let downloader: Downloader

    public init(
        paths: AppPaths,
        searchDirectories: [URL]? = nil,
        downloader: @escaping Downloader = Self.defaultDownloader
    ) {
        self.paths = paths
        self.searchDirectories = searchDirectories ?? Self.defaultSearchDirectories()
        self.downloader = downloader
    }

    public func ensureBundledResources() throws {
        try FileManager.default.createDirectory(
            at: paths.runtimeDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        for definition in Self.definitions {
            let destination = fileURL(for: definition)
            if FileManager.default.fileExists(atPath: destination.path) {
                continue
            }

            guard let source = firstExistingFile(named: definition.sourceNames) else {
                continue
            }
            try FileManager.default.copyItem(at: source, to: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        }
    }

    public func statuses(urlOverrides: [GeoResourceKind: URL] = [:]) -> [GeoResourceStatus] {
        Self.definitions.map { definition in
            status(for: definition, sourceURL: urlOverrides[definition.kind] ?? definition.defaultURL)
        }
    }

    public func sync(kind: GeoResourceKind, url: URL? = nil) async throws -> GeoResourceStatus {
        let definition = try Self.definition(for: kind)
        let sourceURL = url ?? definition.defaultURL
        let data = try await downloader(sourceURL)
        guard !data.isEmpty else {
            throw GeoResourceManagerError.emptyDownload(kind)
        }

        try FileManager.default.createDirectory(
            at: paths.runtimeDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let destination = fileURL(for: definition)
        let temporary = paths.runtimeDirectory.appendingPathComponent(".\(definition.fileName).download-\(UUID().uuidString)")
        try data.write(to: temporary, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return status(for: definition, sourceURL: sourceURL)
    }

    public static func definition(for kind: GeoResourceKind) throws -> GeoResourceDefinition {
        guard let definition = definitions.first(where: { $0.kind == kind }) else {
            throw GeoResourceManagerError.invalidURL(kind.rawValue)
        }
        return definition
    }

    public static func urlOverrides(from strings: [String: String]) throws -> [GeoResourceKind: URL] {
        var result: [GeoResourceKind: URL] = [:]
        for kind in GeoResourceKind.allCases {
            guard let value = strings[kind.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty
            else {
                continue
            }
            guard let url = URL(string: value), url.scheme?.hasPrefix("http") == true else {
                throw GeoResourceManagerError.invalidURL(value)
            }
            result[kind] = url
        }
        return result
    }

    public static func defaultURLStrings() -> [String: String] {
        definitions.reduce(into: [:]) { result, definition in
            result[definition.kind.id] = definition.defaultURL.absoluteString
        }
    }

    public static func defaultURLsByKind() -> [GeoResourceKind: URL] {
        definitions.reduce(into: [:]) { result, definition in
            result[definition.kind] = definition.defaultURL
        }
    }

    public static func defaultSearchDirectories() -> [URL] {
        var directories: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            appendResourceSearchDirectories(baseURL: resourceURL, to: &directories)
        }
        appendResourceSearchDirectories(baseURL: Bundle.main.bundleURL, to: &directories)
        appendResourceSearchDirectories(baseURL: Bundle.main.bundleURL.deletingLastPathComponent(), to: &directories)
        if let executablePath = CommandLine.arguments.first, !executablePath.isEmpty {
            appendResourceSearchDirectories(
                baseURL: URL(fileURLWithPath: executablePath).deletingLastPathComponent(),
                to: &directories
            )
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        directories.append(home.appendingPathComponent(".config/clash", isDirectory: true))
        directories.append(home.appendingPathComponent("Library/Application Support/com.follow.clash", isDirectory: true))
        directories.append(home.appendingPathComponent("Library/Application Support/Clash", isDirectory: true))
        directories.append(home.appendingPathComponent("code/FlClash/assets/data", isDirectory: true))
        return uniqueURLs(directories)
    }

    private static func appendResourceSearchDirectories(baseURL: URL, to directories: inout [URL]) {
        let resourceBundleURL = baseURL.appendingPathComponent("MyClash_MyClashCore.bundle", isDirectory: true)
        directories.append(resourceBundleURL.appendingPathComponent("Geo", isDirectory: true))
        directories.append(resourceBundleURL)
        directories.append(baseURL.appendingPathComponent("Geo", isDirectory: true))
        directories.append(baseURL)
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            let key = url.standardizedFileURL.path
            return seen.insert(key).inserted
        }
    }

    private func status(for definition: GeoResourceDefinition, sourceURL: URL) -> GeoResourceStatus {
        let url = fileURL(for: definition)
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return GeoResourceStatus(
            definition: definition,
            fileURL: url,
            exists: FileManager.default.fileExists(atPath: url.path),
            size: (attributes?[.size] as? NSNumber)?.uint64Value ?? 0,
            lastModified: attributes?[.modificationDate] as? Date,
            sourceURL: sourceURL
        )
    }

    private func fileURL(for definition: GeoResourceDefinition) -> URL {
        paths.runtimeDirectory.appendingPathComponent(definition.fileName)
    }

    private func firstExistingFile(named names: [String]) -> URL? {
        for directory in searchDirectories {
            for name in names {
                let url = directory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
        }
        return nil
    }

    public static func defaultDownloader(url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw ProfileManagerError.profileDownloadFailed("HTTP \(httpResponse.statusCode)")
        }
        return data
    }
}
