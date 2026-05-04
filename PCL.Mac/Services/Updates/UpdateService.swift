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

enum SparkleChannelRouting {
    static func normalizedChannelIdentifier(_ channelIdentifier: String?) -> String? {
        let normalizedChannel = channelIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedChannel, !normalizedChannel.isEmpty else {
            return nil
        }
        return normalizedChannel
    }

    static func allowedChannels(for channelIdentifier: String?) -> Set<String> {
        guard let channelIdentifier = normalizedChannelIdentifier(channelIdentifier) else {
            return []
        }
        return [channelIdentifier]
    }

    static func inferredChannelIdentifier(from fileURL: URL?) -> String? {
        guard let fileURL else {
            return nil
        }
        let path = fileURL.path.lowercased()
        if path.contains("/beta-gray/") {
            return "beta-gray"
        }
        if path.contains("/beta/") {
            return "beta"
        }
        if path.contains("/stable/") {
            return nil
        }
        return nil
    }

    static func allowsAppcastItem(itemChannelIdentifier: String?, fileURL: URL?, selectedChannelIdentifier: String?) -> Bool {
        let normalizedSelectedChannel = normalizedChannelIdentifier(selectedChannelIdentifier)
        let normalizedItemChannel = normalizedChannelIdentifier(itemChannelIdentifier)
        let inferredItemChannel = inferredChannelIdentifier(from: fileURL)

        if let normalizedItemChannel {
            return normalizedItemChannel == normalizedSelectedChannel
        }

        if let inferredItemChannel {
            return inferredItemChannel == normalizedSelectedChannel
        }

        return true
    }
}

@MainActor
final class UpdateService: NSObject {
    public static let shared: UpdateService = .init()
    private static let releaseNotesPageURL: URL = .init(string: "https://update.gzitvs.cn/projects/PCL.Mac.Refactor")!
    private static let defaultDynamicFeedURL: URL = .init(string: "https://update.gzitvs.cn/api/v1/appcast/cn.gzitvs.PCL-Mac/")!
    
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
            let savedValue = SparkleChannelRouting.normalizedChannelIdentifier(LauncherConfig.shared.softwareUpdateChannel)
            if let savedValue {
                return savedValue
            }
            return SparkleChannelRouting.normalizedChannelIdentifier(configuredSparkleChannel)
        }
        set {
            let normalizedValue = SparkleChannelRouting.normalizedChannelIdentifier(newValue)
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

    var softwareUpdateUserID: String {
        if let existing = LauncherConfig.shared.softwareUpdateUserID?.trimmingCharacters(in: .whitespacesAndNewlines), !existing.isEmpty {
            return existing
        }

        let generatedID = UUID().uuidString.lowercased()
        LauncherConfig.mutate {
            $0.softwareUpdateUserID = generatedID
        }
        do {
            try LauncherConfig.save()
        } catch {
            err("保存更新用户标识失败：\(error.localizedDescription)")
        }
        return generatedID
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
        let baseFeedURL: URL
        if let sparkleFeedURLString,
           let configuredURL = URL(string: sparkleFeedURLString) {
            baseFeedURL = configuredURL
        } else {
            baseFeedURL = Self.defaultDynamicFeedURL
        }

        guard var components = URLComponents(url: baseFeedURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        var queryItems: [URLQueryItem] = [
            .init(name: "current_build", value: String(Metadata.bundleVersion)),
            .init(name: "user_id", value: softwareUpdateUserID),
            .init(name: "macos_version", value: ProcessInfo.processInfo.operatingSystemVersionString.sparkleNormalizedMacOSVersion)
        ]

        let normalizedChannel = SparkleChannelRouting.normalizedChannelIdentifier(channelIdentifier)
        if let normalizedChannel, !normalizedChannel.isEmpty {
            queryItems.insert(.init(name: "channel", value: normalizedChannel), at: 0)
        }

        components.queryItems = queryItems
        return components.string
    }
}

private extension String {
    var sparkleNormalizedMacOSVersion: String {
        let pattern = #"(\d+)\.(\d+)(?:\.(\d+))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(self.startIndex..., in: self)) else {
            return "0.0"
        }

        let major = Range(match.range(at: 1), in: self).map { String(self[$0]) } ?? "0"
        let minor = Range(match.range(at: 2), in: self).map { String(self[$0]) } ?? "0"
        let patch = Range(match.range(at: 3), in: self).map { String(self[$0]) }
        if let patch, !patch.isEmpty {
            return "\(major).\(minor).\(patch)"
        }
        return "\(major).\(minor)"
    }
}

extension UpdateService: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        feedURLString(forChannelIdentifier: selectedChannelIdentifier)
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        SparkleChannelRouting.allowedChannels(for: selectedChannelIdentifier)
    }

    func bestValidUpdate(in appcast: SUAppcast, for updater: SPUUpdater) -> SUAppcastItem? {
        let selectedChannelIdentifier = selectedChannelIdentifier
        let eligibleItems = appcast.items.filter {
            SparkleChannelRouting.allowsAppcastItem(
                itemChannelIdentifier: $0.channel,
                fileURL: $0.fileURL,
                selectedChannelIdentifier: selectedChannelIdentifier
            )
        }

        guard eligibleItems.count != appcast.items.count else {
            return nil
        }

        return eligibleItems.first ?? SUAppcastItem.empty()
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
