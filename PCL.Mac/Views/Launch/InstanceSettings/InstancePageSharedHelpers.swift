import Foundation
import AppKit
import CryptoKit
import Core
import ZIPFoundation

enum InstancePageLoader {
    struct ArchivePreviewMetadata {
        let title: String?
        let description: String?
        let icon: NSImage?
    }

    static func loadInstance(_ id: String) -> MinecraftInstance? {
        try? InstanceManager.shared.loadInstance(id)
    }

    static func fileSizeString(_ byteSize: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }

    static func folderSize(at url: URL) -> Int64 {
        InstanceFileBrowserService.directoryByteSize(at: url)
    }

    static func modPreviewIcon(at url: URL) -> NSImage? {
        modPreviewMetadata(at: url).icon
    }

    static func modPreviewMetadata(at url: URL) -> ArchivePreviewMetadata {
        if let metadata = fabricModMetadata(at: url) {
            return metadata
        }
        if let metadata = quiltModMetadata(at: url) {
            return metadata
        }
        if let metadata = forgeModMetadata(at: url) {
            return metadata
        }
        if let metadata = legacyForgeModMetadata(at: url) {
            return metadata
        }

        return .init(
            title: nil,
            description: nil,
            icon: fallbackArchiveIcon(at: url, candidates: ["pack.png", "icon.png", "logo.png", "assets/icon.png"])
        )
    }

    static func resourcePreviewMetadata(at url: URL) -> ArchivePreviewMetadata {
        let description = resourcePackDescription(at: url)
        let icon = resourcePreviewIcon(at: url)
        return .init(title: nil, description: description, icon: icon)
    }

    static func friendlyArchiveDisplayName(for url: URL) -> String {
        let baseName = url.deletingPathExtension().lastPathComponent
        let cleaned = baseName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"\b(?:v)?\d+(?:\.\d+)+(?:\s*(?:beta|alpha|rc)\d*)?\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\b(?:mc|minecraft)\s*\d+(?:\.\d+)+\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? baseName : cleaned
    }

    static func resourcePreviewIcon(at url: URL) -> NSImage? {
        if directoryExists(at: url) {
            for candidate in ["pack.png", "icon.png"] {
                let imageURL = url.appending(path: candidate)
                if let image = NSImage(contentsOf: imageURL) {
                    return image
                }
            }
            return nil
        }

        for candidate in ["pack.png", "icon.png"] {
            if let image = archiveImage(at: url, entryPath: candidate) {
                return image
            }
        }
        return nil
    }

    private static func fabricModMetadata(at url: URL) -> ArchivePreviewMetadata? {
        guard let object = archiveJSONObject(at: url, entryPath: "fabric.mod.json") else {
            return nil
        }

        let title = object["name"] as? String
        let description = object["description"] as? String
        let iconPath = archiveJSONIconPath(at: url, entryPath: "fabric.mod.json")
        let icon = iconPath.flatMap { archiveImage(at: url, entryPath: $0) }
        return .init(title: title?.nilIfBlank, description: description?.nilIfBlank, icon: icon)
    }

    private static func forgeModMetadata(at url: URL) -> ArchivePreviewMetadata? {
        guard let content = archiveString(at: url, entryPath: "META-INF/mods.toml") else {
            return nil
        }

        let title = tomlValue(forKey: "displayName", in: content)
        let description = tomlDescription(in: content)
        let iconPath = archiveTOMLIconPath(at: url, entryPath: "META-INF/mods.toml")
        let icon = iconPath.flatMap { archiveImage(at: url, entryPath: $0) }
        if title == nil, description == nil, icon == nil {
            return nil
        }
        return .init(title: title?.nilIfBlank, description: description?.nilIfBlank, icon: icon)
    }

    private static func quiltModMetadata(at url: URL) -> ArchivePreviewMetadata? {
        guard let object = archiveJSONObject(at: url, entryPath: "quilt.mod.json"),
              let quiltLoader = object["quilt_loader"] as? [String: Any] else {
            return nil
        }

        let title: String?
        let description: String?
        if let metadata = quiltLoader["metadata"] as? [String: Any] {
            title = metadata["name"] as? String
            description = metadata["description"] as? String
        } else {
            title = nil
            description = nil
        }

        let iconPath: String?
        if let icon = quiltLoader["icon"] as? String {
            iconPath = icon
        } else if let iconMap = quiltLoader["icon"] as? [String: Any] {
            iconPath = iconMap
                .compactMap { key, value -> (Int, String)? in
                    guard let size = Int(key), let path = value as? String else { return nil }
                    return (size, path)
                }
                .sorted { $0.0 > $1.0 }
                .first?.1
        } else {
            iconPath = nil
        }

        let icon = iconPath.flatMap { archiveImage(at: url, entryPath: $0) }
        if title == nil, description == nil, icon == nil {
            return nil
        }
        return .init(title: title?.nilIfBlank, description: description?.nilIfBlank, icon: icon)
    }

    private static func legacyForgeModMetadata(at url: URL) -> ArchivePreviewMetadata? {
        guard let json = try? ArchiveUtils.getEntry(url: url, path: "mcmod.info"),
              let object = try? JSONSerialization.jsonObject(with: json) else {
            return nil
        }

        let rootObject: [String: Any]?
        if let array = object as? [[String: Any]] {
            rootObject = array.first
        } else {
            rootObject = object as? [String: Any]
        }

        guard let rootObject else { return nil }
        let title = (rootObject["name"] as? String) ?? (rootObject["modid"] as? String)
        let description = rootObject["description"] as? String
        return .init(title: title?.nilIfBlank, description: description?.nilIfBlank, icon: nil)
    }

    private static func resourcePackDescription(at url: URL) -> String? {
        if directoryExists(at: url) {
            let mcmetaURL = url.appending(path: "pack.mcmeta")
            guard let data = try? Data(contentsOf: mcmetaURL) else {
                return nil
            }
            return packDescription(from: data)
        }

        guard let data = try? ArchiveUtils.getEntry(url: url, path: "pack.mcmeta") else {
            return nil
        }
        return packDescription(from: data)
    }

    private static func packDescription(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pack = object["pack"] as? [String: Any],
              let description = pack["description"] else {
            return nil
        }
        return extractText(from: description)?.nilIfBlank
    }

    private static func extractText(from value: Any) -> String? {
        if let string = value as? String {
            return string
        }
        if let dict = value as? [String: Any] {
            let text = (dict["text"] as? String).map { [$0] } ?? []
            let extras = (dict["extra"] as? [Any] ?? []).compactMap(extractText)
            let joined = (text + extras).joined()
            return joined.isEmpty ? nil : joined
        }
        if let array = value as? [Any] {
            let joined = array.compactMap(extractText).joined()
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    private static func fallbackArchiveIcon(at url: URL, candidates: [String]) -> NSImage? {
        for candidate in candidates {
            if let image = archiveImage(at: url, entryPath: candidate) {
                return image
            }
        }
        return nil
    }

    private static func archiveJSONObject(at url: URL, entryPath: String) -> [String: Any]? {
        guard let data = try? ArchiveUtils.getEntry(url: url, path: entryPath),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func archiveString(at url: URL, entryPath: String) -> String? {
        guard let data = try? ArchiveUtils.getEntry(url: url, path: entryPath) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func archiveImage(at url: URL, entryPath: String) -> NSImage? {
        guard let cachedURL = extractArchiveEntryToCache(at: url, entryPath: entryPath) else {
            return nil
        }
        return NSImage(contentsOf: cachedURL)
    }

    private static func extractArchiveEntryToCache(at url: URL, entryPath: String) -> URL? {
        guard let resolvedPath = resolveArchiveEntryPath(at: url, entryPath: entryPath),
              let data = try? ArchiveUtils.getEntry(url: url, path: resolvedPath) else {
            return nil
        }

        let cacheDirectory = URLConstants.cacheURL.appending(path: "ArchivePreviewIcons")
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let fingerprint = archiveCacheFingerprint(for: url, entryPath: resolvedPath, data: data)
        let ext = URL(fileURLWithPath: resolvedPath).pathExtension.nilIfBlank ?? "png"
        let cachedURL = cacheDirectory.appending(path: "\(fingerprint).\(ext)")
        if !FileManager.default.fileExists(atPath: cachedURL.path) {
            try? data.write(to: cachedURL, options: .atomic)
        }
        return cachedURL
    }

    private static func archiveCacheFingerprint(for url: URL, entryPath: String, data: Data) -> String {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970) ?? 0
        let input = Data("\(url.path)|\(entryPath)|\(modified)|\(data.count)".utf8)
        return Insecure.SHA1.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    private static func resolveArchiveEntryPath(at url: URL, entryPath: String) -> String? {
        guard let archive = try? Archive(url: url, accessMode: .read) else {
            return nil
        }

        let normalizedCandidate = entryPath.replacingOccurrences(of: "\\", with: "/")
        let directCandidates = [
            normalizedCandidate,
            normalizedCandidate.hasPrefix("/") ? String(normalizedCandidate.dropFirst()) : normalizedCandidate,
            normalizedCandidate.hasPrefix("./") ? String(normalizedCandidate.dropFirst(2)) : normalizedCandidate
        ]
        for candidate in directCandidates where archive[candidate] != nil {
            return candidate
        }

        let targetPath = normalizedCandidate.trimmingCharacters(in: CharacterSet(charactersIn: "/.")).lowercased()
        let targetName = URL(fileURLWithPath: normalizedCandidate).lastPathComponent.lowercased()
        for entry in archive {
            let path = entry.path.replacingOccurrences(of: "\\", with: "/")
            let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/.")).lowercased()
            if normalizedPath == targetPath || normalizedPath.hasSuffix("/\(targetPath)") {
                return entry.path
            }
            if !targetName.isEmpty, URL(fileURLWithPath: path).lastPathComponent.lowercased() == targetName {
                return entry.path
            }
        }
        return nil
    }

    private static func archiveJSONIconPath(at url: URL, entryPath: String) -> String? {
        guard let object = archiveJSONObject(at: url, entryPath: entryPath) else {
            return nil
        }

        if let icon = object["icon"] as? String {
            return icon
        }

        if let iconMap = object["icon"] as? [String: Any] {
            return iconMap
                .compactMap { key, value -> (Int, String)? in
                    guard let size = Int(key), let path = value as? String else { return nil }
                    return (size, path)
                }
                .sorted { $0.0 > $1.0 }
                .first?.1
        }

        return nil
    }

    private static func archiveTOMLIconPath(at url: URL, entryPath: String) -> String? {
        guard let content = archiveString(at: url, entryPath: entryPath) else {
            return nil
        }

        return tomlValue(forKey: "logoFile", in: content)
    }

    private static func tomlValue(forKey key: String, in content: String) -> String? {
        let pattern = #"(?m)^\s*"# + NSRegularExpression.escapedPattern(for: key) + #"\s*=\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, range: nsRange),
              let valueRange = Range(match.range(at: 1), in: content) else {
            return nil
        }
        return String(content[valueRange])
    }

    private static func tomlDescription(in content: String) -> String? {
        let multilinePattern = #"(?s)description\s*=\s*'''(.*?)'''"#
        if let regex = try? NSRegularExpression(pattern: multilinePattern) {
            let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)
            if let match = regex.firstMatch(in: content, range: nsRange),
               let valueRange = Range(match.range(at: 1), in: content) {
                return String(content[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let pattern = #"(?m)^\s*description\s*=\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, range: nsRange),
              let valueRange = Range(match.range(at: 1), in: content) else {
            return nil
        }
        return String(content[valueRange])
    }

    private static func directoryExists(at url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

actor InstanceRemoteProjectIconResolver {
    static let shared = InstanceRemoteProjectIconResolver()

    private struct HashIconRecord {
        let iconURL: URL?
    }

    private struct ProjectIconRecord {
        let type: ModrinthProjectType
        let iconURL: URL?
    }

    private struct CurseForgeMatchResponse: Decodable {
        struct DataPayload: Decodable {
            struct ExactMatch: Decodable {
                struct FilePayload: Decodable {
                    let fileFingerprint: UInt32
                }

                let id: Int
                let file: FilePayload
            }

            let exactMatches: [ExactMatch]
        }

        let data: DataPayload
    }

    private struct CurseForgeProjectsResponse: Decodable {
        let data: [CurseForgeProject]
    }

    private struct CurseForgeProject: Decodable {
        struct Links: Decodable {
            let websiteURL: String?

            private enum CodingKeys: String, CodingKey {
                case websiteURL = "websiteUrl"
            }
        }

        struct Logo: Decodable {
            let url: URL?
            let thumbnailURL: URL?

            private enum CodingKeys: String, CodingKey {
                case url
                case thumbnailURL = "thumbnailUrl"
            }
        }

        let id: Int
        let links: Links?
        let logo: Logo?

        var iconURL: URL? {
            logo?.thumbnailURL ?? logo?.url
        }

        var projectType: ModrinthProjectType? {
            guard let websiteURL = links?.websiteURL?.lowercased() else { return nil }
            if websiteURL.contains("/mc-mods/") || websiteURL.contains("/mod/") {
                return .mod
            }
            if websiteURL.contains("/resourcepacks/") || websiteURL.contains("/texture-packs/") {
                return .resourcepack
            }
            if websiteURL.contains("/shaders/") {
                return .shader
            }
            return nil
        }
    }

    private var hashIconCache: [String: HashIconRecord] = [:]
    private var projectIconCache: [String: ProjectIconRecord] = [:]
    private var curseForgeFingerprintCache: [UInt32: HashIconRecord] = [:]
    private var didLogMissingCurseForgeKey: Bool = false

    func iconURLs(for fileURLs: [URL], expectedType: ModrinthProjectType) async -> [URL: URL] {
        var hashByURL: [URL: String] = [:]
        var fingerprintByHash: [String: UInt32] = [:]
        for url in fileURLs where shouldAttemptRemoteLookup(for: url) {
            do {
                let hash = try FileUtils.sha1(of: url)
                hashByURL[url] = hash
                if fingerprintByHash[hash] == nil,
                   let fingerprint = curseForgeFingerprint(forFileAt: url) {
                    fingerprintByHash[hash] = fingerprint
                }
            } catch {
                warn("计算资源文件哈希失败：\(url.lastPathComponent)，将跳过在线图标：\(error.localizedDescription)")
            }
        }

        let unresolvedHashes = Set(hashByURL.values).filter { hashIconCache[$0] == nil }
        if !unresolvedHashes.isEmpty {
            await populateHashIconCache(for: Array(unresolvedHashes), expectedType: expectedType, fingerprintByHash: fingerprintByHash)
        }

        var resolved: [URL: URL] = [:]
        for (url, hash) in hashByURL {
            if let iconURL = hashIconCache[hash]?.iconURL {
                resolved[url] = iconURL
            }
        }
        return resolved
    }

    private func shouldAttemptRemoteLookup(for url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let lowercasedName = url.lastPathComponent.lowercased()
        return lowercasedName.hasSuffix(".jar") ||
            lowercasedName.hasSuffix(".zip") ||
            lowercasedName.hasSuffix(".litemod") ||
            lowercasedName.hasSuffix(".jar.disabled") ||
            lowercasedName.hasSuffix(".zip.disabled") ||
            lowercasedName.hasSuffix(".litemod.disabled")
    }

    private func populateHashIconCache(for hashes: [String], expectedType: ModrinthProjectType, fingerprintByHash: [String: UInt32]) async {
        var unresolvedHashes = Set(hashes)

        do {
            let versionsByHash = try await ModrinthAPIClient.shared.versions(ofHashes: hashes)
            for hash in hashes {
                guard let version = versionsByHash[hash] else { continue }
                let iconURL = await projectIconURL(for: version.projectId, expectedType: expectedType)
                hashIconCache[hash] = .init(iconURL: iconURL)
                unresolvedHashes.remove(hash)
            }
        } catch {
            warn("获取 Modrinth 在线资源图标失败，将尝试其他来源：\(error.localizedDescription)")
        }

        if !unresolvedHashes.isEmpty {
            await populateCurseForgeHashIconCache(
                for: Array(unresolvedHashes),
                expectedType: expectedType,
                fingerprintByHash: fingerprintByHash
            )
            unresolvedHashes = unresolvedHashes.filter { hashIconCache[$0] == nil }
        }

        for hash in unresolvedHashes where hashIconCache[hash] == nil {
            hashIconCache[hash] = .init(iconURL: nil)
        }
    }

    private func populateCurseForgeHashIconCache(for hashes: [String], expectedType: ModrinthProjectType, fingerprintByHash: [String: UInt32]) async {
        guard let apiKey = curseForgeAPIKey else {
            if !didLogMissingCurseForgeKey {
                didLogMissingCurseForgeKey = true
                warn("未配置 CurseForge API Key，实例页将跳过 CurseForge 图标识别。")
            }
            return
        }

        let unresolvedPairs = hashes.compactMap { hash -> (String, UInt32)? in
            guard let fingerprint = fingerprintByHash[hash] else { return nil }
            return (hash, fingerprint)
        }
        guard !unresolvedPairs.isEmpty else { return }

        for (hash, fingerprint) in unresolvedPairs where curseForgeFingerprintCache[fingerprint] != nil {
            hashIconCache[hash] = curseForgeFingerprintCache[fingerprint]
        }

        let pendingPairs = unresolvedPairs.filter { curseForgeFingerprintCache[$0.1] == nil }
        guard !pendingPairs.isEmpty else { return }

        do {
            let matches = try await Requests.post(
                "https://api.curseforge.com/v1/fingerprints/432",
                headers: ["x-api-key": apiKey],
                body: ["fingerprints": pendingPairs.map(\.1)],
                using: .json
            ).decode(CurseForgeMatchResponse.self)

            let projectIDsByFingerprint = Dictionary(uniqueKeysWithValues: matches.data.exactMatches.map { ($0.file.fileFingerprint, $0.id) })
            let projectIDs = Array(Set(projectIDsByFingerprint.values))

            guard !projectIDs.isEmpty else {
                for (hash, fingerprint) in pendingPairs {
                    let record = HashIconRecord(iconURL: nil)
                    curseForgeFingerprintCache[fingerprint] = record
                    hashIconCache[hash] = record
                }
                return
            }

            let projects = try await Requests.post(
                "https://api.curseforge.com/v1/mods",
                headers: ["x-api-key": apiKey],
                body: ["modIds": projectIDs],
                using: .json
            ).decode(CurseForgeProjectsResponse.self)

            let projectRecords = Dictionary(uniqueKeysWithValues: projects.data.map { project in
                (
                    project.id,
                    ProjectIconRecord(type: project.projectType ?? expectedType, iconURL: project.iconURL)
                )
            })

            for (hash, fingerprint) in pendingPairs {
                let record: HashIconRecord
                if let projectID = projectIDsByFingerprint[fingerprint],
                   let project = projectRecords[projectID],
                   project.type == expectedType {
                    record = .init(iconURL: project.iconURL)
                } else {
                    record = .init(iconURL: nil)
                }
                curseForgeFingerprintCache[fingerprint] = record
                hashIconCache[hash] = record
            }
        } catch {
            warn("获取 CurseForge 在线资源图标失败，将回退到本地图标：\(error.localizedDescription)")
            for (hash, fingerprint) in pendingPairs {
                let record = HashIconRecord(iconURL: nil)
                curseForgeFingerprintCache[fingerprint] = record
                hashIconCache[hash] = record
            }
        }
    }

    private func projectIconURL(for projectId: String, expectedType: ModrinthProjectType) async -> URL? {
        if let cached = projectIconCache[projectId] {
            return cached.type == expectedType ? cached.iconURL : nil
        }

        do {
            let project = try await ModrinthAPIClient.shared.project(projectId, revalidate: false)
            let record = ProjectIconRecord(type: project.type, iconURL: project.iconURL)
            projectIconCache[projectId] = record
            return record.type == expectedType ? record.iconURL : nil
        } catch {
            warn("获取在线资源项目信息失败：\(projectId)，将回退到本地图标：\(error.localizedDescription)")
            projectIconCache[projectId] = .init(type: expectedType, iconURL: nil)
            return nil
        }
    }

    private var curseForgeAPIKey: String? {
        ProcessInfo.processInfo.environment["CURSEFORGE_API_KEY"]?.nilIfBlank ?? LauncherConfig.shared.curseForgeAPIKey?.nilIfBlank
    }

    private func curseForgeFingerprint(forFileAt url: URL) -> UInt32? {
        guard FileManager.default.fileExists(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        var bytes: [UInt8] = []
        while let data = try? handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            for byte in data where byte != 9 && byte != 10 && byte != 13 && byte != 32 {
                bytes.append(byte)
            }
        }
        guard !bytes.isEmpty else { return nil }

        let multiplier: UInt32 = 0x5BD1E995
        let shift: UInt32 = 24
        var hash: UInt32 = 1 ^ UInt32(bytes.count)
        var index = 0

        while index + 4 <= bytes.count {
            var chunk = UInt32(bytes[index]) |
                (UInt32(bytes[index + 1]) << 8) |
                (UInt32(bytes[index + 2]) << 16) |
                (UInt32(bytes[index + 3]) << 24)
            chunk = chunk &* multiplier
            chunk ^= chunk >> shift
            chunk = chunk &* multiplier

            hash = hash &* multiplier
            hash ^= chunk
            index += 4
        }

        switch bytes.count - index {
        case 3:
            hash ^= UInt32(bytes[index]) | (UInt32(bytes[index + 1]) << 8)
            hash ^= UInt32(bytes[index + 2]) << 16
            hash = hash &* multiplier
        case 2:
            hash ^= UInt32(bytes[index]) | (UInt32(bytes[index + 1]) << 8)
            hash = hash &* multiplier
        case 1:
            hash ^= UInt32(bytes[index])
            hash = hash &* multiplier
        default:
            break
        }

        hash ^= hash >> 13
        hash = hash &* multiplier
        hash ^= hash >> 15
        return hash
    }
}
