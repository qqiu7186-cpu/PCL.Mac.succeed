import Foundation
import Core

@MainActor
final class UpdateSettingsViewModel: ObservableObject {
    enum ChannelOption: String, CaseIterable, Identifiable {
        case stable = ""
        case beta = "beta"
        case betaGray = "beta-gray"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .stable: "正式版 / Release"
            case .beta: "测试版 / Beta"
            case .betaGray: "灰度测试 / Beta Gray"
            }
        }

        var description: String {
            switch self {
            case .stable: "稳定更新，适合日常使用。"
            case .beta: "优先收到测试构建，可能包含未完全验证的改动。"
            case .betaGray: "用于更小范围的预灰度测试，适合提前验证更新。"
            }
        }

        static func from(identifier: String?) -> ChannelOption {
            guard let identifier, let option = ChannelOption(rawValue: identifier) else {
                return .stable
            }
            return option
        }
    }

    @Published var selectedChannel: ChannelOption
    @Published var automaticallyChecksForUpdates: Bool
    @Published var automaticallyDownloadsUpdates: Bool

    private let updateController: AppUpdateSettingsControlling

    init(updateController: AppUpdateSettingsControlling? = nil) {
        let controller = updateController ?? UpdateService.shared
        self.updateController = controller
        self.selectedChannel = ChannelOption.from(identifier: controller.selectedChannelIdentifier)
        self.automaticallyChecksForUpdates = controller.automaticallyChecksForUpdates
        self.automaticallyDownloadsUpdates = controller.automaticallyDownloadsUpdates
    }

    var canUseSparkle: Bool {
        updateController.canUseSparkle
    }

    var allowsAutomaticDownloads: Bool {
        updateController.allowsAutomaticDownloads
    }

    var currentVersionDescription: String {
        "PCL.Mac \(Metadata.appVersion) (\(Metadata.bundleVersion))"
    }

    var currentStatusDescription: String {
        if Metadata.debugMode || Metadata.bundleVersion == 0 {
            return "当前为调试环境，自动更新检查不会执行。"
        }
        if canUseSparkle {
            return "当前已接入 SparkleGrayAdmin 动态更新源。"
        }
        return "当前未检测到可用的 Sparkle 更新源，无法检查启动器更新。"
    }

    var userIDDescription: String {
        updateController.softwareUpdateUserID
    }

    func selectChannel(_ option: ChannelOption) {
        guard selectedChannel != option else { return }
        selectedChannel = option
        updateController.selectedChannelIdentifier = option.rawValue.isEmpty ? nil : option.rawValue
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        automaticallyChecksForUpdates = isEnabled
        updateController.automaticallyChecksForUpdates = isEnabled
        if !isEnabled && automaticallyDownloadsUpdates {
            automaticallyDownloadsUpdates = false
            updateController.automaticallyDownloadsUpdates = false
        }
    }

    func setAutomaticallyDownloadsUpdates(_ isEnabled: Bool) {
        guard allowsAutomaticDownloads else {
            automaticallyDownloadsUpdates = false
            updateController.automaticallyDownloadsUpdates = false
            return
        }
        if isEnabled && !automaticallyChecksForUpdates {
            automaticallyChecksForUpdates = true
            updateController.automaticallyChecksForUpdates = true
        }
        automaticallyDownloadsUpdates = isEnabled
        updateController.automaticallyDownloadsUpdates = isEnabled
    }

    func checkForUpdates() {
        updateController.runInteractiveUpdateFlow(manually: true)
    }
}
