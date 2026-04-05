import Foundation

public enum NetworkMirrorSelector {
    private static let store = UserDefaults.standard

    public static func prioritize(_ urls: [URL], key: String) -> [URL] {
        guard let host = store.string(forKey: "mirror.last.\(key)") else {
            return deduplicated(urls)
        }
        let unique = deduplicated(urls)
        let preferred = unique.filter { $0.host == host }
        let rest = unique.filter { $0.host != host }
        return preferred + rest
    }

    public static func markSuccess(_ url: URL, key: String) {
        guard let host = url.host, !host.isEmpty else { return }
        store.set(host, forKey: "mirror.last.\(key)")
    }

    private static func deduplicated(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        var result: [URL] = []
        for url in urls {
            let value = url.absoluteString
            if seen.contains(value) { continue }
            seen.insert(value)
            result.append(url)
        }
        return result
    }
}
