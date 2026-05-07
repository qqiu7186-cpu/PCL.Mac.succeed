import Foundation
import AppKit
import Core
import SwiftScaffolding

final class AppBootstrapService {
    static let shared = AppBootstrapService()
    private static let archivePreviewCacheLifetime: TimeInterval = 7 * 24 * 60 * 60
    private static let archivePreviewCacheByteLimit: Int64 = 128 * 1024 * 1024

    func runInitialBootstrap(isUnderTesting: Bool) {
        runStage("基础环境初始化") {
            URLConstants.createDirectories()
            LogManager.shared.enableLogging()
            log("正在启动 PCL.Mac.Refactor \(Metadata.appVersion)")
            try enableSwiftScaffoldingLogging()
        }

        runStage("临时文件清理") {
            for url in try FileManager.default.contentsOfDirectory(at: URLConstants.tempURL, includingPropertiesForKeys: nil) {
                try FileManager.default.removeItem(at: url)
            }
            pruneArchivePreviewCache()
        }

        runStage("版本清单恢复") {
            try restoreVersionManifestCacheOrFetch()
        }

        guard !isUnderTesting else { return }

        runStage("关键单例预热") {
            _ = LauncherConfig.shared
            _ = JavaManager.shared
        }

        runStage("字体加载") {
            let fontURL: URL = URLConstants.resourcesURL.appending(path: "PCL.ttf")
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error)
            if let error = error?.takeUnretainedValue() {
                throw error
            }
        }

        runStage("版本缓存恢复") {
            try VersionCache.load()
        }
    }

    private func runStage(_ name: String, _ block: () throws -> Void) {
        let startedAt = Date()
        do {
            try block()
            log("启动阶段完成：\(name)（\(formatDuration(since: startedAt))）")
        } catch {
            let wrappedError = AppError.wrap(error, category: .runtime, action: "启动阶段失败：\(name)")
            err("\(wrappedError.localizedDescription)（\(formatDuration(since: startedAt))）")
        }
    }

    private func enableSwiftScaffoldingLogging() throws {
        try SwiftScaffolding.Logger.enableLogging(url: URLConstants.logsDirectoryURL.appending(path: "swift-scaffolding.log"))
    }

    private func restoreVersionManifestCacheOrFetch() throws {
        let cacheURL: URL = URLConstants.cacheURL.appending(path: "version_manifest.json")
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            let cachedData: Data = try .init(contentsOf: cacheURL)
            let manifest: VersionManifest = try JSONDecoder.shared.decode(VersionManifest.self, from: cachedData)
            CoreState.versionManifest = manifest
            return
        }

        Task(priority: .utility) {
            let startedAt = Date()
            do {
                let response = try await Requests.get("https://launchermeta.mojang.com/mc/game/version_manifest.json")
                let manifest: VersionManifest = try response.decode(VersionManifest.self)
                CoreState.versionManifest = manifest
                try response.data.write(to: cacheURL)
                log("启动后台预热完成：拉取版本列表（\(formatDuration(since: startedAt))）")
            } catch {
                let wrappedError = AppError.wrap(error, category: .network, action: "启动后台预热失败：拉取版本列表")
                err("\(wrappedError.localizedDescription)（\(formatDuration(since: startedAt))）")
            }
        }
    }

    private func formatDuration(since startedAt: Date) -> String {
        String(format: "%.3fs", Date().timeIntervalSince(startedAt))
    }

    private func pruneArchivePreviewCache() {
        let cacheDirectory = URLConstants.cacheURL.appending(path: "ArchivePreviewIcons")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let now = Date()
        var files: [(url: URL, modifiedAt: Date, byteSize: Int64)] = entries.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else {
                return nil
            }
            return (url, values.contentModificationDate ?? .distantPast, Int64(values.fileSize ?? 0))
        }

        for file in files where now.timeIntervalSince(file.modifiedAt) > Self.archivePreviewCacheLifetime {
            try? FileManager.default.removeItem(at: file.url)
        }

        files.removeAll { now.timeIntervalSince($0.modifiedAt) > Self.archivePreviewCacheLifetime }
        var totalSize = files.reduce(Int64(0)) { $0 + $1.byteSize }
        guard totalSize > Self.archivePreviewCacheByteLimit else { return }

        for file in files.sorted(by: { $0.modifiedAt < $1.modifiedAt }) {
            try? FileManager.default.removeItem(at: file.url)
            totalSize -= file.byteSize
            if totalSize <= Self.archivePreviewCacheByteLimit {
                break
            }
        }
    }

    private init() {}
}
