import Foundation

public enum NodeCatalogSource: String, Sendable, Equatable {
    case preview
    case runtime
}

public struct NodeCatalog: Sendable, Equatable {
    public let source: NodeCatalogSource
    public let groups: [NodeGroup]

    public init(source: NodeCatalogSource, groups: [NodeGroup]) {
        self.source = source
        self.groups = groups
    }
}

public struct NodeGroup: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let type: String
    public let now: String
    public let nodes: [NodeItem]

    public init(name: String, type: String, now: String, nodes: [NodeItem]) {
        self.name = name
        self.type = type
        self.now = now
        self.nodes = nodes
    }
}

public struct NodeItem: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let type: String
    public let delayMilliseconds: Int?
    public let isSelected: Bool

    public init(name: String, type: String = "-", delayMilliseconds: Int? = nil, isSelected: Bool = false) {
        self.name = name
        self.type = type
        self.delayMilliseconds = delayMilliseconds
        self.isSelected = isSelected
    }
}

public struct NodeCatalogBuilder: Sendable {
    public init() {}

    public func previewCatalog(groups: [ProfileProxyGroup]) -> NodeCatalog {
        NodeCatalog(source: .preview, groups: groups.map { group in
            NodeGroup(
                name: group.name,
                type: group.type,
                now: group.now,
                nodes: group.all.map { NodeItem(name: $0, isSelected: $0 == group.now) }
            )
        })
    }

    public func runtimeCatalog(collection: ProxyCollection) -> NodeCatalog {
        let proxyTypeByName = collection.proxies.reduce(into: [String: String]()) { result, pair in
            result[pair.key] = pair.value.type ?? "-"
        }
        let delayByName = collection.proxies.reduce(into: [String: Int]()) { result, pair in
            if let delay = pair.value.latestDelayMilliseconds {
                result[pair.key] = delay
            }
        }

        let groups: [NodeGroup] = collection.proxies.values
            .filter { ($0.all?.isEmpty == false) }
            .map { item in
                let name = item.name ?? "-"
                let now = item.now ?? "-"
                let nodes = (item.all ?? []).map { proxyName in
                    NodeItem(
                        name: proxyName,
                        type: proxyTypeByName[proxyName] ?? "-",
                        delayMilliseconds: delayByName[proxyName],
                        isSelected: proxyName == now
                    )
                }
                return NodeGroup(name: name, type: item.type ?? "-", now: now, nodes: nodes)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return NodeCatalog(source: .runtime, groups: groups)
    }
}

private extension ProxyItem {
    var latestDelayMilliseconds: Int? {
        history?
            .compactMap(\.delay)
            .reversed()
            .first { $0 > 0 }
    }
}
