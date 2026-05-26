import Foundation

public enum ProxyBypassRules {
    public static let defaultEntries: [String] = [
        "localhost",
        "*.local",
        "127.0.0.1",
        "::1",
        "10.0.0.0/8",
        "172.16.0.0/12",
        "192.168.0.0/16",
        "169.254.0.0/16",
        "100.64.0.0/10",
        "fc00::/7",
        "fe80::/10"
    ]

    public static func normalize(_ text: String) -> [String] {
        normalize(
            text
                .components(separatedBy: .newlines)
                .flatMap { $0.split(separator: ",").map(String.init) }
        )
    }

    public static func normalize(_ entries: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for entry in entries {
            let cleaned = stripInlineComment(from: entry)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard !cleaned.isEmpty, !cleaned.hasPrefix("#") else {
                continue
            }
            let key = cleaned.lowercased()
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            result.append(cleaned)
        }
        return result
    }

    public static func ruleLines(for entries: [String]) -> [String] {
        normalize(entries).compactMap(ruleLine)
    }

    public static func defaultText() -> String {
        defaultEntries.joined(separator: "\n")
    }

    private static func ruleLine(for entry: String) -> String? {
        let value = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }

        if value.contains("/") {
            if value.contains(":") {
                return "  - IP-CIDR6,\(value),DIRECT,no-resolve"
            }
            return "  - IP-CIDR,\(value),DIRECT,no-resolve"
        }

        if isIPv4Literal(value) {
            return "  - IP-CIDR,\(value)/32,DIRECT,no-resolve"
        }

        if isIPv6Literal(value) {
            return "  - IP-CIDR6,\(value)/128,DIRECT,no-resolve"
        }

        if value.hasPrefix("*.") {
            return "  - DOMAIN-SUFFIX,\(String(value.dropFirst(2))),DIRECT"
        }

        if value == "localhost" {
            return "  - DOMAIN,\(value),DIRECT"
        }

        return "  - DOMAIN-SUFFIX,\(value),DIRECT"
    }

    private static func stripInlineComment(from entry: String) -> String {
        var isEscaped = false
        var quote: Character?
        var result = ""

        for character in entry {
            if isEscaped {
                result.append(character)
                isEscaped = false
                continue
            }

            if character == "\\" {
                result.append(character)
                isEscaped = true
                continue
            }

            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                }
                result.append(character)
                continue
            }

            if character == "#", quote == nil {
                break
            }

            result.append(character)
        }

        return result
    }

    private static func isIPv4Literal(_ value: String) -> Bool {
        let parts = value.split(separator: ".")
        guard parts.count == 4 else {
            return false
        }
        return parts.allSatisfy { part in
            guard let number = Int(part), (0...255).contains(number) else {
                return false
            }
            return String(number) == part || part == "0"
        }
    }

    private static func isIPv6Literal(_ value: String) -> Bool {
        value.contains(":") && !value.contains("*")
    }
}
