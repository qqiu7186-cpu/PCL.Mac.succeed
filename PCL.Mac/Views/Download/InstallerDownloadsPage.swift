import SwiftUI
import Core
import AppKit
import SwiftyJSON

private struct InstallerDownloadEntry: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let urls: [URL]

    var primaryURL: URL? { urls.first }

    init(id: String, title: String, subtitle: String, url: URL) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.urls = [url]
    }

    init(id: String, title: String, subtitle: String, urls: [URL]) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.urls = urls
    }
}

private struct InstallerDownloadsPage: View {
    let title: String
    let placeholder: String
    let loader: () async -> [InstallerDownloadEntry]

    @State private var query: String = ""
    @State private var entries: [InstallerDownloadEntry] = []
    @State private var loading: Bool = false
    @State private var downloadingTitle: String?
    @State private var downloadingProgress: Double = 0

    private var filteredEntries: [InstallerDownloadEntry] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return entries }
        return entries.filter {
            $0.title.lowercased().contains(keyword) || $0.subtitle.lowercased().contains(keyword)
        }
    }

    var body: some View {
        CardContainer {
            MySearchBox(placeholder: placeholder) { keyword in
                query = keyword
            }

            if loading {
                MyLoading(viewModel: .init(text: "加载中"))
            } else {
                MyCard(title, foldable: false) {
                    if let downloadingTitle {
                        MyText("正在下载：\(downloadingTitle)（\(Int(downloadingProgress * 100))%）", color: .colorGray3)
                            .padding(.bottom, 8)
                    }
                    if filteredEntries.isEmpty {
                        MyText("暂无可用条目", color: .colorGray3)
                            .padding(.vertical, 8)
                    } else {
                        MyList(items: filteredEntries.map { item in
                            ListItem(image: "IconBlock", name: item.title, description: item.subtitle)
                        }) { index in
                            guard let index else { return }
                            let target = filteredEntries[index]
                            startDownload(target)
                        }
                    }
                }
            }
        }
        .task {
            loading = true
            entries = await loader().sorted { $0.title.compare($1.title, options: .numeric) == .orderedDescending }
            loading = false
        }
    }

    private func startDownload(_ target: InstallerDownloadEntry) {
        let panel = NSSavePanel()
        panel.title = "下载 \(target.title)"
        panel.nameFieldStringValue = suggestedFileName(for: target)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        downloadingTitle = target.title
        downloadingProgress = 0
        hint("开始下载：\(target.title)", type: .info)

        Task {
            do {
                try await downloadFromMirrors(target, destination: destination)
                hint("下载完成：\(target.title)", type: .finish)
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                NSPasteboard.general.clearContents()
                if let url = target.primaryURL {
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
                hint("下载失败：\(error.localizedDescription)", type: .critical)
                hint("已复制链接到剪贴板，可手动下载", type: .info)
            }
            downloadingTitle = nil
            downloadingProgress = 0
        }
    }

    private func downloadFromMirrors(_ target: InstallerDownloadEntry, destination: URL) async throws {
        let ordered = NetworkMirrorSelector.prioritize(target.urls, key: "installer.file.\(target.id)")
        var errors: [String] = []
        for url in ordered {
            try Task.checkCancellation()
            do {
                try await SingleFileDownloader.download(
                    url: url,
                    destination: destination,
                    sha1: nil,
                    replaceMethod: .replace,
                    progressHandler: { progress in
                        downloadingProgress = progress
                    }
                )
                NetworkMirrorSelector.markSuccess(url, key: "installer.file.\(target.id)")
                return
            } catch {
                errors.append("\(url.host ?? url.absoluteString): \(error.localizedDescription)")
            }
        }
        throw SimpleError(errors.isEmpty ? "无可用镜像。" : errors.joined(separator: " | "))
    }

    private func suggestedFileName(for target: InstallerDownloadEntry) -> String {
        let lastPath = target.primaryURL?.lastPathComponent ?? ""
        if !lastPath.isEmpty, lastPath != "/" {
            return lastPath.removingPercentEncoding ?? lastPath
        }
        let safeTitle = target.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "\(safeTitle).jar"
    }
}

struct OptiFineInstallerPage: View {
    var body: some View {
        InstallerDownloadsPage(title: "OptiFine", placeholder: "搜索 OptiFine 版本") {
            guard let json = try? await Requests.get("https://bmclapi2.bangbang93.com/optifine/versionList").json() else {
                return []
            }
            return json.arrayValue.compactMap {
                let version = $0["mcversion"].stringValue
                let type = $0["type"].stringValue
                let patch = $0["patch"].stringValue
                guard let url = URL(string: "https://bmclapi2.bangbang93.com/optifine/\(version)/\(type)/\(patch)") else { return nil }
                return InstallerDownloadEntry(
                    id: "optifine-\(version)-\(type)-\(patch)",
                    title: "\(version) \(type)_\(patch)",
                    subtitle: $0["filename"].stringValue,
                    url: url
                )
            }
        }
    }
}

struct LegacyFabricInstallerPage: View {
    var body: some View {
        InstallerDownloadsPage(title: "Legacy Fabric", placeholder: "搜索 Legacy Fabric Installer") {
            guard let json = try? await Requests.get("https://meta.legacyfabric.net/v2/versions/installer").json() else {
                return []
            }
            return json.arrayValue.compactMap {
                let version = $0["version"].stringValue
                guard let url = URL(string: $0["url"].stringValue), !version.isEmpty else { return nil }
                return InstallerDownloadEntry(
                    id: "legacy-fabric-\(version)",
                    title: "Legacy Fabric Installer \(version)",
                    subtitle: $0["stable"].boolValue ? "稳定版" : "测试版",
                    url: url
                )
            }
        }
    }
}

struct QuiltInstallerPage: View {
    var body: some View {
        InstallerDownloadsPage(title: "Quilt", placeholder: "搜索 Quilt Installer") {
            guard let json = try? await Requests.get("https://meta.quiltmc.org/v3/versions/installer").json() else {
                return []
            }
            return json.arrayValue.compactMap {
                let version = $0["version"].stringValue
                guard let url = URL(string: $0["url"].stringValue), !version.isEmpty else { return nil }
                return InstallerDownloadEntry(
                    id: "quilt-\(version)",
                    title: "Quilt Installer \(version)",
                    subtitle: $0["maven"].stringValue,
                    url: url
                )
            }
        }
    }
}

struct LiteLoaderInstallerPage: View {
    var body: some View {
        InstallerDownloadsPage(title: "LiteLoader", placeholder: "搜索 LiteLoader 版本") {
            guard let json = try? await Requests.get("https://dl.liteloader.com/versions/versions.json").json() else {
                return []
            }
            var items: [InstallerDownloadEntry] = []
            for (mcVersion, detail) in json["versions"].dictionaryValue {
                let version = detail["snapshots"]["com.mumfrey:liteloader"]["latest"]["version"].stringValue
                guard !version.isEmpty,
                      let url = URL(string: "https://dl.liteloader.com/versions/com/mumfrey/liteloader/\(version)/liteloader-\(version).jar") else { continue }
                items.append(.init(
                    id: "liteloader-\(mcVersion)-\(version)",
                    title: "LiteLoader \(mcVersion)",
                    subtitle: version,
                    url: url
                ))
            }
            return items
        }
    }
}

struct CleanroomInstallerPage: View {
    var body: some View {
        InstallerDownloadsPage(title: "Cleanroom", placeholder: "搜索 Cleanroom 版本") {
            guard let response = try? await Requests.get(
                "https://api.github.com/repos/CleanroomMC/Cleanroom/releases?per_page=50",
                headers: ["Accept": "application/vnd.github+json", "User-Agent": "PCL-Mac"]
            ),
            let releases = try? response.json().array else { return [] }

            var items: [InstallerDownloadEntry] = []
            for release in releases {
                let tag = release["tag_name"].stringValue
                for asset in release["assets"].arrayValue {
                    guard let url = URL(string: asset["browser_download_url"].stringValue) else { continue }
                    let name = asset["name"].stringValue
                    guard !name.isEmpty else { continue }
                    items.append(.init(id: "cleanroom-\(tag)-\(name)", title: name, subtitle: tag, url: url))
                }
            }
            return items
        }
    }
}

struct LabyModInstallerPage: View {
    var body: some View {
        InstallerDownloadsPage(title: "LabyMod", placeholder: "搜索 LabyMod 下载项") {
            guard let response = try? await Requests.get("https://www.labymod.net/en/changelog"),
                  let html = String(data: response.data, encoding: .utf8),
                  let regex = try? NSRegularExpression(pattern: #"https://(?:releases\.r2\.labymod\.net|dl\.labymod\.net)[^"'<>\s]+"#) else {
                return []
            }

            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            var seen: Set<String> = []
            var items: [InstallerDownloadEntry] = []
            for match in regex.matches(in: html, options: [], range: range) {
                guard let swiftRange = Range(match.range, in: html) else { continue }
                let link = String(html[swiftRange])
                guard seen.insert(link).inserted, let url = URL(string: link) else { continue }
                let filename = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
                items.append(.init(id: "labymod-\(filename)", title: filename, subtitle: url.host ?? "labymod", url: url))
            }
            return items
        }
    }
}

struct ForgeInstallerPage: View {
    var body: some View {
        InstallerDownloadsPage(title: "Forge", placeholder: "搜索 Forge 版本") {
            let mirrors = [
                URL(string: "https://bmclapi2.bangbang93.com/forge/promos")!,
                URL(string: "https://bmclapi.bangbang93.com/forge/promos")!,
                URL(string: "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json")!
            ]
            guard let json = await requestFirstJSONFromMirrors(mirrors, key: "installer.list.forge") else {
                return []
            }
            let entries: [InstallerDownloadEntry] = json.arrayValue.compactMap { item in
                let promoName = item["name"].stringValue
                let mcVersion = item["build"]["mcversion"].stringValue
                let forgeVersion = item["build"]["version"].stringValue
                guard !promoName.isEmpty, !mcVersion.isEmpty, !forgeVersion.isEmpty else { return nil }
                let path = "net/minecraftforge/forge/\(mcVersion)-\(forgeVersion)/forge-\(mcVersion)-\(forgeVersion)-installer.jar"
                return InstallerDownloadEntry(
                    id: "forge-\(mcVersion)-\(forgeVersion)",
                    title: "Forge \(mcVersion) - \(forgeVersion)",
                    subtitle: promoName,
                    urls: [
                        URL(string: "https://maven.minecraftforge.net/\(path)")!,
                        URL(string: "https://files.minecraftforge.net/maven/\(path)")!,
                        URL(string: "https://bmclapi2.bangbang93.com/maven/\(path)")!,
                        URL(string: "https://bmclapi.bangbang93.com/maven/\(path)")!
                    ]
                )
            }
            var seen: Set<String> = []
            return entries.filter { seen.insert($0.id).inserted }
        }
    }
}

struct NeoForgeInstallerPage: View {
    var body: some View {
        InstallerDownloadsPage(title: "NeoForge", placeholder: "搜索 NeoForge 版本") {
            let metadataMirrors = [
                URL(string: "https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml")!,
                URL(string: "https://bmclapi2.bangbang93.com/maven/net/neoforged/neoforge/maven-metadata.xml")!,
                URL(string: "https://bmclapi.bangbang93.com/maven/net/neoforged/neoforge/maven-metadata.xml")!
            ]

            let legacyMetadataMirrors = [
                URL(string: "https://maven.neoforged.net/releases/net/neoforged/forge/maven-metadata.xml")!,
                URL(string: "https://bmclapi2.bangbang93.com/maven/net/neoforged/forge/maven-metadata.xml")!,
                URL(string: "https://bmclapi.bangbang93.com/maven/net/neoforged/forge/maven-metadata.xml")!
            ]

            guard let neoForgeXml = await requestFirstTextFromMirrors(metadataMirrors, key: "installer.list.neoforge.metadata") else {
                return []
            }

            let neoForgeVersions = extractVersions(fromMavenMetadata: neoForgeXml)
            let legacyVersions = (await requestFirstTextFromMirrors(legacyMetadataMirrors, key: "installer.list.neoforge.legacy-metadata"))
                .map(extractVersions(fromMavenMetadata:)) ?? []

            let allVersions = Array(Set(neoForgeVersions + legacyVersions))
            return allVersions.compactMap { version in
                guard !version.isEmpty else { return nil }
                let isLegacy = version.hasPrefix("1.20.1-")
                let path: String
                if isLegacy {
                    path = "net/neoforged/forge/\(version)/forge-\(version)-installer.jar"
                } else {
                    path = "net/neoforged/neoforge/\(version)/neoforge-\(version)-installer.jar"
                }
                return InstallerDownloadEntry(
                    id: "neoforge-\(version)",
                    title: "NeoForge \(version)",
                    subtitle: isLegacy ? "Legacy Forge 兼容线" : "NeoForge",
                    urls: [
                        URL(string: "https://maven.neoforged.net/releases/\(path)")!,
                        URL(string: "https://bmclapi2.bangbang93.com/maven/\(path)")!,
                        URL(string: "https://bmclapi.bangbang93.com/maven/\(path)")!
                    ]
                )
            }
        }
    }
}

struct FabricInstallerPage: View {
    var body: some View {
        InstallerDownloadsPage(title: "Fabric", placeholder: "搜索 Fabric Installer") {
            let mirrors = [
                URL(string: "https://meta.fabricmc.net/v2/versions/installer")!,
                URL(string: "https://meta2.fabricmc.net/v2/versions/installer")!
            ]
            guard let json = await requestFirstJSONFromMirrors(mirrors, key: "installer.list.fabric") else {
                return []
            }
            return json.arrayValue.compactMap { item in
                let version = item["version"].stringValue
                guard !version.isEmpty else { return nil }
                let path = "net/fabricmc/fabric-installer/\(version)/fabric-installer-\(version).jar"
                return InstallerDownloadEntry(
                    id: "fabric-installer-\(version)",
                    title: "Fabric Installer \(version)",
                    subtitle: item["stable"].boolValue ? "稳定版" : "测试版",
                    urls: [
                        URL(string: "https://maven.fabricmc.net/\(path)")!,
                        URL(string: "https://bmclapi2.bangbang93.com/maven/\(path)")!,
                        URL(string: "https://bmclapi.bangbang93.com/maven/\(path)")!,
                        URL(string: "https://download.mcbbs.net/maven/\(path)")!,
                        URL(string: "https://bmclapi2-cn.bangbang93.com/maven/\(path)")!
                    ]
                )
            }
        }
    }
}

private func requestFirstJSONFromMirrors(_ urls: [URL], key: String) async -> JSON? {
    let ordered = NetworkMirrorSelector.prioritize(urls, key: key)
    for url in ordered {
        do {
            let json = try await Requests.get(url.absoluteString).json()
            NetworkMirrorSelector.markSuccess(url, key: key)
            return json
        } catch {
            continue
        }
    }
    return nil
}

private func requestFirstTextFromMirrors(_ urls: [URL], key: String) async -> String? {
    let ordered = NetworkMirrorSelector.prioritize(urls, key: key)
    for url in ordered {
        do {
            let response = try await Requests.get(url.absoluteString)
            if let text = String(data: response.data, encoding: .utf8), !text.isEmpty {
                NetworkMirrorSelector.markSuccess(url, key: key)
                return text
            }
        } catch {
            continue
        }
    }
    return nil
}

private func extractVersions(fromMavenMetadata xml: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: "<version>([^<]+)</version>") else {
        return []
    }
    let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
    return regex.matches(in: xml, options: [], range: range).compactMap { match in
        guard match.numberOfRanges > 1, let swiftRange = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        return String(xml[swiftRange])
    }
}
