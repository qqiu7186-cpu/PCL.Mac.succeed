import Foundation

public enum JavaRuntimeMirrorResolver {
    private static let runtimeListPath = "/v1/products/java-runtime/2ec0cc96c44e5a76b9c8b7c39df7210883d12871/all.json"

    public static var runtimeListURLs: [URL] {
        [
            URL(string: "https://launchermeta.mojang.com\(runtimeListPath)")!,
            URL(string: "https://piston-meta.mojang.com\(runtimeListPath)")!,
            URL(string: "https://bmclapi2.bangbang93.com\(runtimeListPath)")!,
            URL(string: "https://bmclapi.bangbang93.com\(runtimeListPath)")!
        ]
    }

    public static func candidateURLs(for original: URL) -> [URL] {
        var candidates: [URL] = [original]
        guard let host = original.host else {
            return candidates
        }

        switch host {
        case "launchermeta.mojang.com", "piston-meta.mojang.com":
            candidates.append(contentsOf: mirroredURLs(for: original, hosts: [
                "launchermeta.mojang.com",
                "piston-meta.mojang.com",
                "bmclapi2.bangbang93.com",
                "bmclapi.bangbang93.com"
            ]))
        case "bmclapi2.bangbang93.com", "bmclapi.bangbang93.com":
            if original.path == runtimeListPath || original.path.hasPrefix("/v1/products/java-runtime/") {
                candidates.append(contentsOf: mirroredURLs(for: original, hosts: [
                    "launchermeta.mojang.com",
                    "piston-meta.mojang.com",
                    "bmclapi2.bangbang93.com",
                    "bmclapi.bangbang93.com"
                ]))
            } else {
                candidates.append(contentsOf: mirroredURLs(for: original, hosts: [
                    "piston-data.mojang.com",
                    "launcher.mojang.com",
                    "bmclapi2.bangbang93.com",
                    "bmclapi.bangbang93.com"
                ]))
            }
        case "launcher.mojang.com", "piston-data.mojang.com":
            candidates.append(contentsOf: mirroredURLs(for: original, hosts: [
                "piston-data.mojang.com",
                "launcher.mojang.com",
                "bmclapi2.bangbang93.com",
                "bmclapi.bangbang93.com"
            ]))
        default:
            break
        }

        return deduplicated(candidates)
    }

    private static func mirroredURLs(for original: URL, hosts: [String]) -> [URL] {
        hosts.compactMap { host in
            var components = URLComponents(url: original, resolvingAgainstBaseURL: false)
            components?.scheme = "https"
            components?.host = host
            return components?.url
        }
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
