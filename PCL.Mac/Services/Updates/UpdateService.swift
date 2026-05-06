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
import Security

enum SparkleChannelRouting {
    static let stableChannelIdentifier: String = "stable"
    static let betaChannelIdentifier: String = "beta"
    static let betaGrayChannelIdentifier: String = "beta-gray"

    static func normalizedChannelIdentifier(_ channelIdentifier: String?) -> String? {
        let normalizedChannel = channelIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedChannel, !normalizedChannel.isEmpty else {
            return nil
        }
        return normalizedChannel
    }

    static func allowedChannels(for channelIdentifier: String?) -> Set<String> {
        [requestChannelIdentifier(for: channelIdentifier)]
    }

    static func requestChannelIdentifier(for channelIdentifier: String?) -> String {
        normalizedChannelIdentifier(channelIdentifier) ?? stableChannelIdentifier
    }

    static func prioritizedRequestChannels(for channelIdentifier: String?) -> [String] {
        let requestedChannel = requestChannelIdentifier(for: channelIdentifier)
        if requestedChannel == betaChannelIdentifier {
            return [betaGrayChannelIdentifier, betaChannelIdentifier]
        }
        return [requestedChannel]
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
        let selectedChannel = requestChannelIdentifier(for: selectedChannelIdentifier)
        let normalizedItemChannel = normalizedChannelIdentifier(itemChannelIdentifier)
        let inferredItemChannel = inferredChannelIdentifier(from: fileURL)

        if let normalizedItemChannel {
            return normalizedItemChannel == selectedChannel
        }

        if let inferredItemChannel {
            return inferredItemChannel == selectedChannel
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
    private var currentCheckContext: UpdateCheckContext?
    
    private var sparkleFeedURLString: String? {
        sanitizedInfoString(for: "SUFeedURL")
    }
    
    private var configuredSparkleChannel: String? {
        sanitizedInfoString(for: "SparkleChannel")
    }
    
    var canUseSparkle: Bool {
        sparkleFeedURLString != nil
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
        UpdateIdentityStore.shared.userID()
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

            guard currentCheckContext == nil else {
                if manually {
                    hint("已经有更新检查正在进行，请稍候。", type: .info)
                }
                return
            }

            guard startSparkleIfNeeded() else {
                let message = "未检测到可用的 Sparkle 更新源，无法检查启动器更新。"
                err(message)
                if manually {
                    hint(message, type: .critical)
                }
                return
            }

            let requestChannelIdentifier = await resolveRequestChannelIdentifier()
            currentCheckContext = .init(requestChannelIdentifier: requestChannelIdentifier)
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

    private func resolveRequestChannelIdentifier() async -> String {
        let prioritizedChannels = SparkleChannelRouting.prioritizedRequestChannels(for: selectedChannelIdentifier)
        guard prioritizedChannels.count > 1 else {
            return prioritizedChannels[0]
        }

        var candidates: [AppcastUpdateCandidate] = []
        for channel in prioritizedChannels {
            if let candidate = await bestAvailableCandidate(forChannelIdentifier: channel) {
                candidates.append(candidate)
            }
        }

        guard !candidates.isEmpty else {
            return SparkleChannelRouting.requestChannelIdentifier(for: selectedChannelIdentifier)
        }

        let preferredCandidate = AppcastUpdateCandidateSelector.preferredCandidate(
            from: candidates,
            prioritizedChannels: prioritizedChannels
        )

        if let preferredCandidate {
            log("更新检查选择频道：\(preferredCandidate.channelIdentifier)（版本 \(preferredCandidate.versionString)）")
            return preferredCandidate.channelIdentifier
        }

        return SparkleChannelRouting.requestChannelIdentifier(for: selectedChannelIdentifier)
    }

    private func bestAvailableCandidate(forChannelIdentifier channelIdentifier: String) async -> AppcastUpdateCandidate? {
        guard let feedURLString = feedURLString(forChannelIdentifier: channelIdentifier),
              let feedURL = URL(string: feedURLString) else {
            return nil
        }

        var request = URLRequest(url: feedURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                warn("探测更新频道失败：\(channelIdentifier) 返回 HTTP \(httpResponse.statusCode)")
                return nil
            }
            return AppcastFeedCandidateEvaluator.bestAvailableCandidate(
                in: data,
                channelIdentifier: channelIdentifier,
                currentBuildVersion: String(Metadata.bundleVersion),
                currentSystemVersion: ProcessInfo.processInfo.operatingSystemVersion.sparkleComparableVersion
            )
        } catch {
            warn("探测更新频道失败：\(channelIdentifier) - \(error.localizedDescription)")
            return nil
        }
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: .numeric)
    }

    private func startSparkleIfNeeded() -> Bool {
        guard canUseSparkle, let sparkleController else {
            warn("Sparkle 更新源未完成配置")
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

        let isDynamicFeed = components.path.contains("/api/v1/appcast/")

        if !isDynamicFeed {
            let normalizedChannel = SparkleChannelRouting.normalizedChannelIdentifier(channelIdentifier)
            guard let normalizedChannel else {
                components.queryItems = nil
                return components.string
            }

            var pathComponents = components.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            if let stableIndex = pathComponents.lastIndex(of: SparkleChannelRouting.stableChannelIdentifier) {
                pathComponents[stableIndex] = normalizedChannel
                components.path = pathComponents.joined(separator: "/")
            }
            components.queryItems = nil
            return components.string
        }

        var queryItems: [URLQueryItem] = [
            .init(name: "current_build", value: String(Metadata.bundleVersion)),
            .init(name: "user_id", value: softwareUpdateUserID),
            .init(name: "macos_version", value: ProcessInfo.processInfo.operatingSystemVersionString.sparkleNormalizedMacOSVersion)
        ]

        let requestChannelIdentifier = SparkleChannelRouting.requestChannelIdentifier(for: channelIdentifier)
        queryItems.insert(.init(name: "channel", value: requestChannelIdentifier), at: 0)

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
        feedURLString(forChannelIdentifier: currentCheckContext?.requestChannelIdentifier ?? selectedChannelIdentifier)
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        SparkleChannelRouting.allowedChannels(for: currentCheckContext?.requestChannelIdentifier ?? selectedChannelIdentifier)
    }

    func bestValidUpdate(in appcast: SUAppcast, for updater: SPUUpdater) -> SUAppcastItem? {
        let selectedChannelIdentifier = currentCheckContext?.requestChannelIdentifier ?? selectedChannelIdentifier
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
        finishCurrentCheck()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        err("Sparkle 更新失败：\(error.localizedDescription)")
        if latestCheckWasManual || showingSparkleProgressHint {
            hint("更新失败：\(error.localizedDescription)", type: .critical)
        }
        finishCurrentCheck()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        log("Sparkle 找到可用更新：\(item.versionString)")
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        hint("正在下载并安装更新，完成后 PCL.Mac 会自动重启……")
        showingSparkleProgressHint = true
        latestCheckWasManual = false
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        err("Sparkle 下载更新失败：\(error.localizedDescription)")
        hint("更新失败：\(error.localizedDescription)", type: .critical)
        finishCurrentCheck()
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        finishCurrentCheck()
    }
}

private extension UpdateService {
    struct UpdateCheckContext {
        let requestChannelIdentifier: String
    }

    func finishCurrentCheck() {
        currentCheckContext = nil
        latestCheckWasManual = false
        showingSparkleProgressHint = false
    }
}

struct AppcastUpdateCandidate: Equatable {
    let channelIdentifier: String
    let versionString: String
}

enum AppcastUpdateCandidateSelector {
    static func preferredCandidate(
        from candidates: [AppcastUpdateCandidate],
        prioritizedChannels: [String]
    ) -> AppcastUpdateCandidate? {
        candidates.max { lhs, rhs in
            let versionComparison = compareVersions(lhs.versionString, rhs.versionString)
            if versionComparison == .orderedSame {
                let lhsPriority = prioritizedChannels.firstIndex(of: lhs.channelIdentifier) ?? .max
                let rhsPriority = prioritizedChannels.firstIndex(of: rhs.channelIdentifier) ?? .max
                return lhsPriority > rhsPriority
            }
            return versionComparison == .orderedAscending
        }
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: .numeric)
    }
}

private struct AppcastFeedItem {
    var versionString: String?
    var minimumSystemVersion: String?
    var maximumSystemVersion: String?
    var minimumUpdateVersion: String?
}

enum AppcastFeedCandidateEvaluator {
    static func bestAvailableCandidate(
        in data: Data,
        channelIdentifier: String,
        currentBuildVersion: String,
        currentSystemVersion: String
    ) -> AppcastUpdateCandidate? {
        AppcastCandidateInspector.bestAvailableCandidate(
            in: data,
            channelIdentifier: channelIdentifier,
            currentBuildVersion: currentBuildVersion,
            currentSystemVersion: currentSystemVersion
        )
    }
}

private final class AppcastCandidateInspector: NSObject, XMLParserDelegate {
    private let channelIdentifier: String
    private let currentBuildVersion: String
    private let currentSystemVersion: String

    private var items: [AppcastFeedItem] = []
    private var currentItem: AppcastFeedItem?
    private var textBuffer: String = ""

    init(channelIdentifier: String, currentBuildVersion: String, currentSystemVersion: String) {
        self.channelIdentifier = channelIdentifier
        self.currentBuildVersion = currentBuildVersion
        self.currentSystemVersion = currentSystemVersion
    }

    static func bestAvailableCandidate(in data: Data, channelIdentifier: String, currentBuildVersion: String, currentSystemVersion: String) -> AppcastUpdateCandidate? {
        let inspector = AppcastCandidateInspector(
            channelIdentifier: channelIdentifier,
            currentBuildVersion: currentBuildVersion,
            currentSystemVersion: currentSystemVersion
        )
        let parser = XMLParser(data: data)
        parser.delegate = inspector
        guard parser.parse() else {
            return nil
        }
        return inspector.bestCandidate()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let localName = localName(for: elementName)
        textBuffer = ""

        if localName == "item" {
            currentItem = .init()
            return
        }

        guard localName == "enclosure", currentItem != nil else {
            return
        }

        if currentItem?.versionString == nil {
            currentItem?.versionString = attributeValue(named: "version", in: attributeDict)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard currentItem != nil else {
            return
        }

        let localName = localName(for: elementName)
        let trimmedText = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedText.isEmpty {
            switch localName {
            case "version":
                currentItem?.versionString = trimmedText
            case "minimumSystemVersion":
                currentItem?.minimumSystemVersion = trimmedText
            case "maximumSystemVersion":
                currentItem?.maximumSystemVersion = trimmedText
            case "minimumUpdateVersion":
                currentItem?.minimumUpdateVersion = trimmedText
            default:
                break
            }
        }

        if localName == "item", let item = currentItem {
            items.append(item)
            currentItem = nil
        }

        textBuffer = ""
    }

    private func bestCandidate() -> AppcastUpdateCandidate? {
        let candidates = items.compactMap { item -> AppcastUpdateCandidate? in
            guard let versionString = item.versionString,
                  compareVersions(versionString, currentBuildVersion) == .orderedDescending else {
                return nil
            }

            if let minimumUpdateVersion = item.minimumUpdateVersion,
               compareVersions(currentBuildVersion, minimumUpdateVersion) == .orderedAscending {
                return nil
            }

            if let minimumSystemVersion = item.minimumSystemVersion,
               compareVersions(currentSystemVersion, minimumSystemVersion) == .orderedAscending {
                return nil
            }

            if let maximumSystemVersion = item.maximumSystemVersion,
               compareVersions(currentSystemVersion, maximumSystemVersion) == .orderedDescending {
                return nil
            }

            return .init(channelIdentifier: channelIdentifier, versionString: versionString)
        }

        return candidates.max { lhs, rhs in
            compareVersions(lhs.versionString, rhs.versionString) == .orderedAscending
        }
    }

    private func localName(for elementName: String) -> String {
        elementName.split(separator: ":").last.map(String.init) ?? elementName
    }

    private func attributeValue(named expectedName: String, in attributes: [String: String]) -> String? {
        for (key, value) in attributes where localName(for: key) == expectedName {
            return value
        }
        return nil
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: .numeric)
    }
}

private extension OperatingSystemVersion {
    var sparkleComparableVersion: String {
        "\(majorVersion).\(minorVersion).\(patchVersion)"
    }
}

private final class UpdateIdentityStore {
    static let shared = UpdateIdentityStore()

    private let service = "cn.gzitvs.PCL-Mac.update.identity"
    private let account = "installation-user-id"

    func userID() -> String {
        if let existing = readFromKeychain(), !existing.isEmpty {
            return existing
        }

        if let legacy = LauncherConfig.shared.softwareUpdateUserID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !legacy.isEmpty {
            if saveToKeychain(legacy) {
                clearLegacyConfigUserID()
                return legacy
            }
            return legacy
        }

        let generatedID = "upd_" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        if saveToKeychain(generatedID) {
            clearLegacyConfigUserID()
            return generatedID
        }

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

    private func clearLegacyConfigUserID() {
        guard LauncherConfig.shared.softwareUpdateUserID != nil else { return }
        LauncherConfig.mutate {
            $0.softwareUpdateUserID = nil
        }
        do {
            try LauncherConfig.save()
        } catch {
            err("清理旧版更新用户标识失败：\(error.localizedDescription)")
        }
    }

    private func readFromKeychain() -> String? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private func saveToKeychain(_ value: String) -> Bool {
        let data = Data(value.utf8)
        var query = keychainQuery()

        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        if updateStatus != errSecItemNotFound {
            err("更新 Keychain 中的更新用户标识失败：\(updateStatus)")
        }

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus != errSecSuccess {
            err("保存 Keychain 中的更新用户标识失败：\(addStatus)")
            return false
        }
        return true
    }

    private func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
