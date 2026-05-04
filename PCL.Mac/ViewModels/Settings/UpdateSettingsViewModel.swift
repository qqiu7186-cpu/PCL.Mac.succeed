import Foundation
import Core

@MainActor
final class UpdateSettingsViewModel: ObservableObject {
    enum ChannelOption: String, CaseIterable, Identifiable {
        case stable = ""
        case beta = "beta"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .stable: "正式版 / Release"
            case .beta: "测试版 / Beta"
            }
        }

        var description: String {
            switch self {
            case .stable: "稳定更新，适合日常使用。"
            case .beta: "优先收到测试构建，可能包含未完全验证的改动。"
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
            return "Sparkle 已启用，当前会优先使用自动更新链路。"
        }
        return "Sparkle 未完成配置，当前会回退到旧版 update.json 更新链路。"
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
