import Foundation

public struct ControllerEndpoint: Sendable, Equatable {
    public var host: String
    public var port: Int
    public var secret: String

    public init(host: String = "127.0.0.1", port: Int = 9090, secret: String) {
        self.host = host
        self.port = port
        self.secret = secret
    }

    public var baseURL: URL {
        URL(string: "http://\(host):\(port)")!
    }

    public func websocketURL(path: String) -> URL {
        URL(string: "ws://\(host):\(port)\(path)")!
    }
}

public enum ControllerClientError: Error, LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Controller returned an invalid response."
        case let .httpStatus(status):
            return "Controller returned HTTP status \(status)."
        }
    }
}

public struct MihomoVersion: Codable, Sendable, Equatable {
    public let version: String?
    public let meta: Bool?
    public let premium: Bool?
}

public struct MihomoConfig: Codable, Sendable, Equatable {
    public let port: Int?
    public let socksPort: Int?
    public let redirPort: Int?
    public let tproxyPort: Int?
    public let mixedPort: Int?
    public let allowLan: Bool?
    public let mode: String?
    public let logLevel: String?

    enum CodingKeys: String, CodingKey {
        case port
        case socksPort = "socks-port"
        case redirPort = "redir-port"
        case tproxyPort = "tproxy-port"
        case mixedPort = "mixed-port"
        case allowLan = "allow-lan"
        case mode
        case logLevel = "log-level"
    }
}

public struct ProxyCollection: Decodable, Sendable, Equatable {
    public let proxies: [String: ProxyItem]

    public init(proxies: [String: ProxyItem]) {
        self.proxies = proxies
    }

    enum CodingKeys: String, CodingKey {
        case proxies
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.proxies = (try? container.decodeLossyDictionary([String: ProxyItem].self, forKey: .proxies)) ?? [:]
    }
}

public struct ProxyItem: Decodable, Sendable, Equatable {
    public let name: String?
    public let type: String?
    public let now: String?
    public let all: [String]?
    public let history: [ProxyDelayHistory]?

    public init(name: String?, type: String?, now: String?, all: [String]?, history: [ProxyDelayHistory]?) {
        self.name = name
        self.type = type
        self.now = now
        self.all = all
        self.history = history
    }

    enum CodingKeys: String, CodingKey {
        case name
        case type
        case now
        case all
        case history
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = container.decodeFlexibleStringIfPresent(forKey: .name)
        self.type = container.decodeFlexibleStringIfPresent(forKey: .type)
        self.now = container.decodeFlexibleStringIfPresent(forKey: .now)
        self.all = container.decodeFlexibleStringArrayIfPresent(forKey: .all)
        self.history = (try? container.decodeLossyArray([ProxyDelayHistory].self, forKey: .history)) ?? nil
    }
}

public struct ProxyDelayHistory: Decodable, Sendable, Equatable {
    public let time: String?
    public let delay: Int?

    public init(time: String?, delay: Int?) {
        self.time = time
        self.delay = delay
    }

    enum CodingKeys: String, CodingKey {
        case time
        case delay
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.time = container.decodeFlexibleStringIfPresent(forKey: .time)
        self.delay = container.decodeFlexibleIntIfPresent(forKey: .delay)
    }
}

public struct ConnectionCollection: Decodable, Sendable, Equatable {
    public let uploadTotal: Int?
    public let downloadTotal: Int?
    public let connections: [ConnectionItem]

    public init(uploadTotal: Int?, downloadTotal: Int?, connections: [ConnectionItem]) {
        self.uploadTotal = uploadTotal
        self.downloadTotal = downloadTotal
        self.connections = connections
    }

    enum CodingKeys: String, CodingKey {
        case uploadTotal
        case downloadTotal
        case connections
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.uploadTotal = container.decodeFlexibleIntIfPresent(forKey: .uploadTotal)
        self.downloadTotal = container.decodeFlexibleIntIfPresent(forKey: .downloadTotal)
        self.connections = (try? container.decodeLossyArray([ConnectionItem].self, forKey: .connections)) ?? []
    }
}

public struct ConnectionItem: Decodable, Sendable, Equatable {
    public let id: String
    public let upload: Int?
    public let download: Int?
    public let start: String?
    public let chains: [String]?
    public let rule: String?
    public let rulePayload: String?

    public init(
        id: String,
        upload: Int?,
        download: Int?,
        start: String?,
        chains: [String]?,
        rule: String?,
        rulePayload: String?
    ) {
        self.id = id
        self.upload = upload
        self.download = download
        self.start = start
        self.chains = chains
        self.rule = rule
        self.rulePayload = rulePayload
    }

    enum CodingKeys: String, CodingKey {
        case id
        case upload
        case download
        case start
        case chains
        case rule
        case rulePayload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = container.decodeFlexibleStringIfPresent(forKey: .id) ?? UUID().uuidString
        self.upload = container.decodeFlexibleIntIfPresent(forKey: .upload)
        self.download = container.decodeFlexibleIntIfPresent(forKey: .download)
        self.start = container.decodeFlexibleStringIfPresent(forKey: .start)
        self.chains = container.decodeFlexibleStringArrayIfPresent(forKey: .chains)
        self.rule = container.decodeFlexibleStringIfPresent(forKey: .rule)
        self.rulePayload = container.decodeFlexibleStringIfPresent(forKey: .rulePayload)
    }
}

public struct DelayResponse: Decodable, Sendable, Equatable {
    public let delay: Int

    public init(delay: Int) {
        self.delay = delay
    }

    enum CodingKeys: String, CodingKey {
        case delay
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.delay = container.decodeFlexibleIntIfPresent(forKey: .delay) ?? -1
    }
}

public struct ProxyProviderCollection: Decodable, Sendable, Equatable {
    public let providers: [String: RuntimeProxyProvider]

    public init(providers: [String: RuntimeProxyProvider]) {
        self.providers = providers
    }

    enum CodingKeys: String, CodingKey {
        case providers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.providers = (try? container.decodeLossyDictionary([String: RuntimeProxyProvider].self, forKey: .providers)) ?? [:]
    }
}

public struct RuntimeProxyProvider: Decodable, Sendable, Equatable {
    public let name: String?
    public let type: String?
    public let vehicleType: String?
    public let updatedAt: String?
    public let subscriptionInfo: String?
    public let proxies: [ProxyItem]?

    public init(name: String?, type: String?, vehicleType: String?, updatedAt: String?, subscriptionInfo: String?, proxies: [ProxyItem]?) {
        self.name = name
        self.type = type
        self.vehicleType = vehicleType
        self.updatedAt = updatedAt
        self.subscriptionInfo = subscriptionInfo
        self.proxies = proxies
    }

    enum CodingKeys: String, CodingKey {
        case name
        case type
        case vehicleType = "vehicleType"
        case updatedAt = "updatedAt"
        case subscriptionInfo = "subscriptionInfo"
        case proxies
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = container.decodeFlexibleStringIfPresent(forKey: .name)
        self.type = container.decodeFlexibleStringIfPresent(forKey: .type)
        self.vehicleType = container.decodeFlexibleStringIfPresent(forKey: .vehicleType)
        self.updatedAt = container.decodeFlexibleStringIfPresent(forKey: .updatedAt)
        self.subscriptionInfo = container.decodeFlexibleStringIfPresent(forKey: .subscriptionInfo)
        self.proxies = (try? container.decodeLossyArray([ProxyItem].self, forKey: .proxies)) ?? nil
    }
}

public struct ControllerClient: Sendable {
    private let endpoint: ControllerEndpoint
    private let session: URLSession

    public init(endpoint: ControllerEndpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    public func version() async throws -> MihomoVersion {
        try await get("/version")
    }

    public func configs() async throws -> MihomoConfig {
        try await get("/configs")
    }

    public func proxies() async throws -> ProxyCollection {
        try await get("/proxies")
    }

    public func connections() async throws -> ConnectionCollection {
        try await get("/connections")
    }

    public func selectProxy(groupName: String, proxyName: String) async throws {
        let encodedGroup = Self.encodePathComponent(groupName)
        let body = try JSONSerialization.data(withJSONObject: ["name": proxyName])
        _ = try await request(path: "/proxies/\(encodedGroup)", method: "PUT", body: body)
    }

    public func closeConnection(id: String) async throws {
        let encodedID = Self.encodePathComponent(id)
        _ = try await request(path: "/connections/\(encodedID)", method: "DELETE", body: nil)
    }

    public func closeAllConnections() async throws {
        _ = try await request(path: "/connections", method: "DELETE", body: nil)
    }

    public func delay(groupName: String, testURL: String = "https://www.gstatic.com/generate_204", timeoutMilliseconds: Int = 5000) async throws -> DelayResponse {
        let encodedGroup = Self.encodePathComponent(groupName)
        let encodedURL = testURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? testURL
        return try await get("/group/\(encodedGroup)/delay?url=\(encodedURL)&timeout=\(timeoutMilliseconds)")
    }

    public func proxyDelay(proxyName: String, testURL: String = "https://www.gstatic.com/generate_204", timeoutMilliseconds: Int = 5000) async throws -> DelayResponse {
        let encodedProxy = Self.encodePathComponent(proxyName)
        let encodedURL = testURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? testURL
        return try await get("/proxies/\(encodedProxy)/delay?url=\(encodedURL)&timeout=\(timeoutMilliseconds)")
    }

    public func proxyProviders() async throws -> ProxyProviderCollection {
        try await get("/providers/proxies")
    }

    public func refreshProxyProvider(name: String) async throws {
        let encodedName = Self.encodePathComponent(name)
        _ = try await request(path: "/providers/proxies/\(encodedName)", method: "PUT", body: nil)
    }

    public var trafficWebSocketURL: URL {
        endpoint.websocketURL(path: "/traffic")
    }

    public var logsWebSocketURL: URL {
        endpoint.websocketURL(path: "/logs")
    }

    public var connectionsWebSocketURL: URL {
        endpoint.websocketURL(path: "/connections")
    }

    public func authorizedWebSocketRequest(path: String) -> URLRequest {
        var request = URLRequest(url: endpoint.websocketURL(path: path))
        authorize(&request)
        return request
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await request(path: path, method: "GET", body: nil)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func request(path: String, method: String, body: Data?) async throws -> Data {
        let requestURL = URL(string: endpoint.baseURL.absoluteString + path)
            ?? endpoint.baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.httpBody = body
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        authorize(&request)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ControllerClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ControllerClientError.httpStatus(httpResponse.statusCode)
        }
        return data
    }

    private func authorize(_ request: inout URLRequest) {
        guard !endpoint.secret.isEmpty else {
            return
        }
        request.setValue("Bearer \(endpoint.secret)", forHTTPHeaderField: "Authorization")
    }

    private static func encodePathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleStringIfPresent(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    func decodeFlexibleIntIfPresent(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    func decodeFlexibleStringArrayIfPresent(forKey key: Key) -> [String]? {
        if let values = try? decodeIfPresent([String].self, forKey: key) {
            return values
        }
        if let values = try? decodeIfPresent([LossyStringValue].self, forKey: key) {
            return values.compactMap(\.value)
        }
        if let value = decodeFlexibleStringIfPresent(forKey: key) {
            return [value]
        }
        return nil
    }

    func decodeLossyArray<T: Decodable>(_ type: [T].Type, forKey key: Key) throws -> [T] {
        var nested = try nestedUnkeyedContainer(forKey: key)
        var values: [T] = []
        while !nested.isAtEnd {
            if let value = try? nested.decode(T.self) {
                values.append(value)
            } else {
                _ = try? nested.decode(LossyDiscard.self)
            }
        }
        return values
    }

    func decodeLossyDictionary<T: Decodable>(_ type: [String: T].Type, forKey key: Key) throws -> [String: T] {
        let nested = try nestedContainer(keyedBy: DynamicCodingKey.self, forKey: key)
        var values: [String: T] = [:]
        for nestedKey in nested.allKeys {
            if let value = try? nested.decode(T.self, forKey: nestedKey) {
                values[nestedKey.stringValue] = value
            }
        }
        return values
    }
}

private struct LossyStringValue: Decodable {
    let value: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self.value = value
        } else if let value = try? container.decode(Int.self) {
            self.value = String(value)
        } else if let value = try? container.decode(Double.self) {
            self.value = String(value)
        } else if let value = try? container.decode(Bool.self) {
            self.value = String(value)
        } else {
            self.value = nil
        }
    }
}

private struct LossyDiscard: Decodable {
    init(from decoder: Decoder) throws {
        if var container = try? decoder.unkeyedContainer() {
            while !container.isAtEnd {
                _ = try? container.decode(LossyDiscard.self)
            }
            return
        }
        if let container = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            for key in container.allKeys {
                _ = try? container.decode(LossyDiscard.self, forKey: key)
            }
            return
        }
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            return
        }
        if (try? container.decode(String.self)) != nil {
            return
        }
        if (try? container.decode(Double.self)) != nil {
            return
        }
        if (try? container.decode(Bool.self)) != nil {
            return
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
