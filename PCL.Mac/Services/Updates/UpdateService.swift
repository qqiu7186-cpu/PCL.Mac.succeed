//
//  UpdateService.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/26.
//

import Foundation
import AppKit
import Core
import Sparkle

@MainActor
final class UpdateService: NSObject {
    public static let shared: UpdateService = .init()
    private static let releaseNotesPageURL: URL = .init(string: "https://update.gzitvs.cn/projects/PCL.Mac.Refactor")!
    
    private let semaphore: AsyncSemaphore = .init(value: 1)
    private lazy var sparkleController: SPUStandardUpdaterController? = makeSparkleController()
    private lazy var updaterSettings: SPUUpdaterSettings = .init(hostBundle: .main)
    private var sparkleStarted: Bool = false
    private var latestCheckWasManual: Bool = false
    private var showingSparkleProgressHint: Bool = false
    
    private var sparkleFeedURLString: String? {
        sanitizedInfoString(for: "SUFeedURL")
    }
    
    private var sparklePublicKey: String? {
        sanitizedInfoString(for: "SUPublicEDKey")
    }

    private var configuredSparkleChannel: String? {
        sanitizedInfoString(for: "SparkleChannel")
    }
    
    var canUseSparkle: Bool {
        sparkleFeedURLString != nil && sparklePublicKey != nil
    }

    var selectedChannelIdentifier: String? {
        get {
            let savedValue = LauncherConfig.shared.softwareUpdateChannel?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let savedValue, !savedValue.isEmpty {
                return savedValue
            }
            return configuredSparkleChannel
        }
        set {
            let trimmedValue = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedValue = (trimmedValue?.isEmpty == false) ? trimmedValue : nil
            LauncherConfig.mutate {
                $0.softwareUpdateChannel = normalizedValue
            }
            do {
                try LauncherConfig.save()
            } catch {
                err("保存更新通道失败：\(error.localizedDescription)")
                hint("保存更新通道失败：\(error.localizedDescription)", type: .critical)
            }
            if sparkleStarted {
                sparkleController?.updater.resetUpdateCycle()
            }
        }
    }

    var currentFeedURLString: String? {
        feedURLString(forChannelIdentifier: selectedChannelIdentifier)
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterSettings.automaticallyChecksForUpdates }
        set { updaterSettings.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updaterSettings.automaticallyDownloadsUpdates }
        set { updaterSettings.automaticallyDownloadsUpdates = newValue }
    }

    var allowsAutomaticDownloads: Bool {
        updaterSettings.allowsAutomaticUpdates
    }

    func openReleaseNotesPage() {
        NSWorkspace.shared.open(Self.releaseNotesPageURL)
    }
    
    public func runInteractiveUpdateFlow(manually: Bool = false) {
        Task {
            await semaphore.wait()
            defer { Task { await semaphore.signal() } }
            guard !Metadata.debugMode, Metadata.bundleVersion != 0 else {
                if manually {
                    hint("调试模式下不检查更新。", type: .info)
                }
                return
            }

            guard startSparkleIfNeeded() else {
                await runLegacyUpdateFlow(manually: manually)
                return
            }

            latestCheckWasManual = manually
            showingSparkleProgressHint = false
            if manually {
                hint("正在检查更新……")
                sparkleController?.checkForUpdates(nil)
            } else {
                sparkleController?.updater.checkForUpdatesInBackground()
            }
        }
    }
    
    private func startSparkleIfNeeded() -> Bool {
        guard canUseSparkle, let sparkleController else {
            log("Sparkle 未完成配置，继续使用旧更新链路")
            return false
        }
        guard !sparkleStarted else {
            return true
        }

        sparkleController.startUpdater()
        sparkleStarted = true
        log("Sparkle 更新器已启动")
        return true
    }

    private func runLegacyUpdateFlow(manually: Bool) async {
        if manually {
            hint("正在检查更新……")
        }
        let version: UpdateModel.Version?
        do {
            version = try await UpdateManager.shared.checkUpdates()
        } catch {
            err("检查更新失败：\(error.localizedDescription)")
            if manually {
                hint("检查更新失败：\(error.localizedDescription)", type: .critical)
            }
            return
        }
        guard let version else {
            if manually {
                hint("当前使用的是最新版本，无需更新！", type: .finish)
            }
            return
        }

        guard await MessageBoxManager.shared.showTextAsync(
            title: "PCL.Mac 有更新可用",
            content: "发现新版本：\(version.name)\n更新摘要：\(version.summary)\n\n是否下载并安装更新？",
            level: .info,
            buttons: version.updateLogLinks.enumerated().map { index, link in
                return .init(id: index + 2, label: link.name, type: .normal) {
                    NSWorkspace.shared.open(link.url)
                }
            } + [.no(), .yes(label: "下载并安装（\(formatSize(version.downloads.size))）", type: .highlight)]
        ) == 1 else { return }
        hint("正在下载并安装更新，完成后 PCL.Mac 会自动重启……")
        do {
            try await UpdateManager.shared.installUpdate(version)
        } catch {
            err("更新启动器失败：\(error.localizedDescription)")
            hint("更新失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func makeSparkleController() -> SPUStandardUpdaterController? {
        guard canUseSparkle else {
            return nil
        }
        return SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    }

    private func sanitizedInfoString(for key: String) -> String? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func formatSize(_ size: Int) -> String {
        let units: [String] = ["B", "KB", "MB", "GB", "TB"]
        var value: Double = .init(size)
        var unitIndex: Int = 0
        
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        
        let formatted: String = .init(format: value < 10 && unitIndex > 0 ? "%.1f" : "%.0f", value)
        return "\(formatted) \(units[unitIndex])"
    }

    private func feedURLString(forChannelIdentifier channelIdentifier: String?) -> String? {
        guard let sparkleFeedURLString else {
            return nil
        }

        let normalizedChannel = channelIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedChannel, !normalizedChannel.isEmpty else {
            return sparkleFeedURLString
        }

        guard let feedURL = URL(string: sparkleFeedURLString),
              var components = URLComponents(url: feedURL, resolvingAgainstBaseURL: false) else {
            return sparkleFeedURLString
        }

        var pathComponents = components.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if let stableIndex = pathComponents.lastIndex(of: "stable") {
            pathComponents[stableIndex] = normalizedChannel
            components.path = pathComponents.joined(separator: "/")
            return components.string ?? sparkleFeedURLString
        }

        return sparkleFeedURLString
    }
}

extension UpdateService: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        feedURLString(forChannelIdentifier: selectedChannelIdentifier)
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        []
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        if latestCheckWasManual {
            hint("当前使用的是最新版本，无需更新！", type: .finish)
        }
        latestCheckWasManual = false
        showingSparkleProgressHint = false
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        err("Sparkle 更新失败：\(error.localizedDescription)")
        if latestCheckWasManual || showingSparkleProgressHint {
            hint("更新失败：\(error.localizedDescription)", type: .critical)
        }
        latestCheckWasManual = false
        showingSparkleProgressHint = false
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        hint("正在下载并安装更新，完成后 PCL.Mac 会自动重启……")
        showingSparkleProgressHint = true
        latestCheckWasManual = false
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        err("Sparkle 下载更新失败：\(error.localizedDescription)")
        hint("更新失败：\(error.localizedDescription)", type: .critical)
        showingSparkleProgressHint = false
        latestCheckWasManual = false
    }
}
