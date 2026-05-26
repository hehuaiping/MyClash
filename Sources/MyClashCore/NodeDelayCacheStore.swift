import Foundation

public struct CachedNodeDelay: Codable, Sendable, Equatable {
    public var name: String
    public var delay: Int
    public var updatedAt: Date

    public init(name: String, delay: Int, updatedAt: Date = Date()) {
        self.name = name
        self.delay = delay
        self.updatedAt = updatedAt
    }
}

public actor NodeDelayCacheStore {
    private let fileURL: URL
    private var cache: [String: CachedNodeDelay] = [:]
    private var loaded = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func delays(maxAge: TimeInterval? = nil, now: Date = Date()) async -> [String: Int] {
        await loadIfNeeded()
        return cache.reduce(into: [String: Int]()) { result, pair in
            if let maxAge, now.timeIntervalSince(pair.value.updatedAt) > maxAge {
                return
            }
            result[pair.key] = pair.value.delay
        }
    }

    public func upsert(_ delays: [String: Int], now: Date = Date()) async throws {
        await loadIfNeeded()
        for (name, delay) in delays where !name.isEmpty {
            cache[name] = CachedNodeDelay(name: name, delay: delay, updatedAt: now)
        }
        try persist()
    }

    public func clear() async throws {
        cache = [:]
        loaded = true
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private func loadIfNeeded() async {
        guard !loaded else {
            return
        }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else {
            cache = [:]
            return
        }
        let entries = (try? JSONDecoder().decode([CachedNodeDelay].self, from: data)) ?? []
        cache = entries.reduce(into: [String: CachedNodeDelay]()) { result, item in
            result[item.name] = item
        }
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Array(cache.values).sorted { $0.name < $1.name })
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
