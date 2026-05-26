import Foundation

struct ClashConfigDocument: Sendable, Equatable {
    private struct TopLevelBlock: Sendable, Equatable {
        let key: String
        let start: Int
        let end: Int
    }

    private struct YAMLListItem: Sendable, Equatable {
        var properties: [String: String] = [:]
        var arrays: [String: [String]] = [:]
    }

    let raw: String

    init(raw: String) {
        self.raw = raw
    }

    func removingManagedTopLevelKeys(_ managedKeys: Set<String>) -> String {
        let lines = raw.components(separatedBy: .newlines)
        let blocks = topLevelBlocks(in: lines)
        let managedRanges = blocks
            .filter { managedKeys.contains($0.key) }
            .map { $0.start..<$0.end }

        guard !managedRanges.isEmpty else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let filtered = lines.enumerated().compactMap { index, line in
            managedRanges.contains { $0.contains(index) } ? nil : line
        }
        return filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func topLevelKeys() -> Set<String> {
        Set(topLevelBlocks(in: raw.components(separatedBy: .newlines)).map(\.key))
    }

    func applyingTopLevelOverride(_ overrideRaw: String, managedKeys: Set<String>) -> String {
        let overrideDocument = ClashConfigDocument(raw: overrideRaw)
        let overrideKeys = overrideDocument.topLevelKeys().subtracting(managedKeys)
        let base = removingManagedTopLevelKeys(managedKeys.union(overrideKeys))
        let override = overrideDocument.removingManagedTopLevelKeys(managedKeys)

        let parts = [base, override]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.joined(separator: "\n\n# Override by MyClash\n")
    }

    func prependingRules(_ ruleLines: [String]) -> String {
        let ruleLines = ruleLines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !ruleLines.isEmpty else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var lines = raw.components(separatedBy: .newlines)
        let blocks = topLevelBlocks(in: lines)
        if let rulesBlock = blocks.first(where: { $0.key == "rules" }) {
            let insertionIndex = rulesBlock.start + 1
            let itemIndentation = firstListItemIndentation(in: lines, block: rulesBlock) ?? 2
            lines.insert(contentsOf: reindentedRuleLines(ruleLines, indentation: itemIndentation), at: insertionIndex)
            return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var result = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !result.isEmpty {
            result.append("\n\n")
        }
        result.append("rules:\n")
        result.append(ruleLines.joined(separator: "\n"))
        result.append("\n  - MATCH,DIRECT")
        return result
    }

    private func firstListItemIndentation(in lines: [String], block: TopLevelBlock) -> Int? {
        let bodyStart = min(block.start + 1, lines.count)
        let bodyEnd = min(block.end, lines.count)
        guard bodyStart < bodyEnd else {
            return nil
        }

        return lines[bodyStart..<bodyEnd].compactMap { line -> Int? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") else {
                return nil
            }
            let indentation = Self.indentationLevel(line)
            return indentation > 0 ? indentation : nil
        }.first
    }

    private func reindentedRuleLines(_ ruleLines: [String], indentation: Int) -> [String] {
        let prefix = String(repeating: " ", count: indentation)
        return ruleLines.map { line in
            prefix + line.trimmingCharacters(in: .whitespaces)
        }
    }

    func proxyPreview() -> [ProfileProxyGroup] {
        let proxies = listItems(inSection: "proxies")
        let proxyNames = proxies.compactMap { $0.properties["name"] }.filter { !$0.isEmpty }
        let groups = listItems(inSection: "proxy-groups")

        let proxyGroups = groups.compactMap { item -> ProfileProxyGroup? in
            guard let name = item.properties["name"], !name.isEmpty else {
                return nil
            }

            let all = (item.arrays["proxies"] ?? item.arrays["use"] ?? [])
                .filter { !$0.isEmpty }
            let type = item.properties["type"] ?? "select"
            let now = item.properties["now"] ?? all.first ?? "-"
            return ProfileProxyGroup(name: name, type: type, now: now, all: all)
        }

        if !proxyGroups.isEmpty {
            return proxyGroups
        }

        guard !proxyNames.isEmpty else {
            return []
        }

        return [
            ProfileProxyGroup(
                name: "节点",
                type: "profile",
                now: proxyNames.first ?? "-",
                all: proxyNames
            )
        ]
    }

    func qualityReport() -> ProfileQualityReport {
        let proxyNames = listItems(inSection: "proxies")
            .compactMap { $0.properties["name"] }
            .filter { !$0.isEmpty }
        let groups = proxyPreview()
        let providerCount = dictionaryEntryCount(inTopLevelSection: "proxy-providers")
        let groupNodeCount = groups.reduce(0) { $0 + $1.all.count }
        let lowercasedRaw = raw.lowercased()
        let containsClientHint = raw.contains("请下载客户端")
            || raw.contains("官方客户端")
            || lowercasedRaw.contains("download client")

        return ProfileQualityReport(
            proxyCount: Set(proxyNames).count,
            groupCount: groups.count,
            providerCount: providerCount,
            groupNodeCount: groupNodeCount,
            containsClientHint: containsClientHint
        )
    }

    func proxyProviders() -> [ProfileProxyProvider] {
        let sectionLines = lines(inTopLevelSection: "proxy-providers")
        guard !sectionLines.isEmpty else {
            return []
        }

        let entryIndent = sectionLines
            .compactMap { line -> Int? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard let parsed = Self.parseKeyValue(trimmed), !parsed.key.isEmpty else {
                    return nil
                }
                return parsed.value.isEmpty || (parsed.value.hasPrefix("{") && parsed.value.hasSuffix("}"))
                    ? Self.indentationLevel(line)
                    : nil
            }
            .min()

        guard let entryIndent else {
            return []
        }

        var providers: [ProfileProxyProvider] = []
        var currentName: String?
        var properties: [String: String] = [:]
        var nestedKey: String?

        func appendCurrentProvider() {
            guard let currentName, !currentName.isEmpty else {
                return
            }
            providers.append(
                ProfileProxyProvider(
                    name: currentName,
                    type: properties["type"] ?? "-",
                    path: properties["path"],
                    url: properties["url"],
                    interval: properties["interval"].flatMap(Int.init),
                    healthCheckEnabled: Self.parseBool(properties["health-check.enable"])
                )
            )
        }

        for line in sectionLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = Self.indentationLevel(line)
            guard let parsed = Self.parseKeyValue(trimmed), !parsed.key.isEmpty else {
                continue
            }

            if indent == entryIndent {
                appendCurrentProvider()
                currentName = parsed.key
                properties = [:]
                nestedKey = nil
                if parsed.value.hasPrefix("{"), parsed.value.hasSuffix("}") {
                    for pair in Self.splitInlineMap(String(parsed.value.dropFirst().dropLast())) {
                        if let inlineParsed = Self.parseKeyValue(pair) {
                            properties[inlineParsed.key] = inlineParsed.value
                        }
                    }
                }
                continue
            }

            guard currentName != nil, indent > entryIndent else {
                continue
            }

            if parsed.value.isEmpty {
                nestedKey = parsed.key
            } else if let nestedKey {
                properties["\(nestedKey).\(parsed.key)"] = parsed.value
            } else {
                properties[parsed.key] = parsed.value
            }
        }

        appendCurrentProvider()
        return providers
    }

    func applyingSelections(_ selections: [String: String]) -> [ProfileProxyGroup] {
        proxyPreview().map { group in
            guard let selected = selections[group.name], group.all.contains(selected) else {
                return group
            }
            return ProfileProxyGroup(name: group.name, type: group.type, now: selected, all: group.all)
        }
    }

    private func listItems(inSection sectionName: String) -> [YAMLListItem] {
        let sectionLines = lines(inTopLevelSection: sectionName)
        let baseIndent = sectionLines
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }
            .map(Self.indentationLevel)
            .min()

        guard let baseIndent else {
            return []
        }

        var items: [YAMLListItem] = []
        var index = 0
        while index < sectionLines.count {
            let line = sectionLines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            guard Self.indentationLevel(line) == baseIndent, trimmed.hasPrefix("- ") else {
                index += 1
                continue
            }

            var item = YAMLListItem()
            Self.applyListItemContent(String(trimmed.dropFirst(2)), to: &item)
            index += 1

            var activeArrayKey: String?
            while index < sectionLines.count {
                let nestedLine = sectionLines[index]
                let nestedTrimmed = nestedLine.trimmingCharacters(in: .whitespaces)
                let nestedIndent = Self.indentationLevel(nestedLine)
                if nestedIndent == baseIndent, nestedTrimmed.hasPrefix("- ") {
                    break
                }

                if nestedTrimmed.hasPrefix("- "), nestedIndent > baseIndent, let activeArrayKey {
                    item.arrays[activeArrayKey, default: []].append(Self.cleanScalar(String(nestedTrimmed.dropFirst(2))))
                } else if let parsed = Self.parseKeyValue(nestedTrimmed), nestedIndent > baseIndent {
                    if parsed.value.isEmpty {
                        activeArrayKey = parsed.key
                        item.arrays[parsed.key, default: []] = item.arrays[parsed.key] ?? []
                    } else {
                        activeArrayKey = nil
                        item.properties[parsed.key] = parsed.value
                        if let inlineArray = Self.parseInlineArray(parsed.value) {
                            item.arrays[parsed.key] = inlineArray
                        }
                    }
                }

                index += 1
            }

            items.append(item)
        }

        return items
    }

    private func lines(inTopLevelSection sectionName: String) -> [String] {
        let lines = raw.components(separatedBy: .newlines)
        guard let block = topLevelBlocks(in: lines).first(where: { $0.key == sectionName }) else {
            return []
        }
        return Array(lines[(block.start + 1)..<block.end])
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty && !trimmed.hasPrefix("#")
            }
    }

    private func dictionaryEntryCount(inTopLevelSection sectionName: String) -> Int {
        let sectionLines = lines(inTopLevelSection: sectionName)
        let entries = sectionLines.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let parsed = Self.parseKeyValue(trimmed), !parsed.key.isEmpty else {
                return nil
            }
            return parsed.key
        }
        return Set(entries).count
    }

    private func topLevelBlocks(in lines: [String]) -> [TopLevelBlock] {
        var starts: [(key: String, index: Int)] = []

        for (index, line) in lines.enumerated() {
            guard let key = Self.topLevelKey(in: line) else {
                continue
            }
            starts.append((key, index))
        }

        return starts.enumerated().map { offset, item in
            let end = offset + 1 < starts.count ? starts[offset + 1].index : lines.count
            return TopLevelBlock(key: item.key, start: item.index, end: end)
        }
    }

    private static func topLevelKey(in line: String) -> String? {
        guard !line.hasPrefix(" "), !line.hasPrefix("\t") else {
            return nil
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
            return nil
        }

        var quote: Character?
        for (index, character) in trimmed.enumerated() {
            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                }
            }

            if character == ":", quote == nil {
                let key = String(trimmed.prefix(index)).trimmingCharacters(in: .whitespaces)
                return key.isEmpty ? nil : key
            }
        }
        return nil
    }

    private static func applyListItemContent(_ content: String, to item: inout YAMLListItem) {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return
        }

        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            for pair in splitInlineMap(String(trimmed.dropFirst().dropLast())) {
                if let parsed = parseKeyValue(pair) {
                    item.properties[parsed.key] = parsed.value
                    if let inlineArray = parseInlineArray(parsed.value) {
                        item.arrays[parsed.key] = inlineArray
                    }
                }
            }
            return
        }

        if let parsed = parseKeyValue(trimmed) {
            item.properties[parsed.key] = parsed.value
            if let inlineArray = parseInlineArray(parsed.value) {
                item.arrays[parsed.key] = inlineArray
            }
        }
    }

    private static func parseKeyValue(_ text: String) -> (key: String, value: String)? {
        var quote: Character?
        for index in text.indices {
            let character = text[index]
            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                }
            }
            if character == ":", quote == nil {
                let key = text[..<index].trimmingCharacters(in: .whitespaces)
                let value = text[text.index(after: index)...].trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else {
                    return nil
                }
                return (key, cleanScalar(String(value)))
            }
        }
        return nil
    }

    private static func parseInlineArray(_ value: String) -> [String]? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else {
            return nil
        }

        let content = String(trimmed.dropFirst().dropLast())
        return splitCommaSeparated(content).map(cleanScalar).filter { !$0.isEmpty }
    }

    private static func splitInlineMap(_ content: String) -> [String] {
        splitCommaSeparated(content)
    }

    private static func splitCommaSeparated(_ content: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var bracketDepth = 0

        for character in content {
            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                }
            }

            if quote == nil {
                if character == "[" {
                    bracketDepth += 1
                } else if character == "]", bracketDepth > 0 {
                    bracketDepth -= 1
                }
            }

            if character == ",", quote == nil, bracketDepth == 0 {
                result.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }

        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    private static func cleanScalar(_ value: String) -> String {
        stripInlineComment(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private static func parseBool(_ value: String?) -> Bool {
        guard let value else {
            return false
        }
        switch value.lowercased() {
        case "true", "yes", "1", "on":
            return true
        default:
            return false
        }
    }

    private static func stripInlineComment(_ value: String) -> String {
        var quote: Character?
        var previous: Character?
        for (offset, character) in value.enumerated() {
            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                }
            }

            if character == "#", quote == nil, (previous == nil || previous == " ") {
                return String(value.prefix(offset))
            }
            previous = character
        }
        return value
    }

    private static func indentationLevel(_ line: String) -> Int {
        line.prefix { $0 == " " }.count
    }
}
