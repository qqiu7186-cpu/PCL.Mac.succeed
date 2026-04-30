import SwiftUI

extension AppRouter {
    var sidebar: any Sidebar {
        switch getLast() {
        case .launch: LaunchSidebar()
        case .instanceList, .noInstanceRepository: InstanceListSidebar()
        case .instanceSettings(let id),
            .instanceOverview(let id), .instanceConfig(let id), .instanceModify(let id), .instanceExport(let id),
            .instanceSaves(let id), .instanceScreenshots(let id), .instanceMods(let id), .instanceResourcepacks(let id), .instanceShaderpacks(let id), .instanceSchematics(let id), .instanceServers(let id):
            InstanceSettingsSidebar(id: id)
        case .minecraftDownload,
            .modDownload, .modpackDownload, .datapackDownload, .resourcepackDownload, .shaderpackDownload, .worldDownload, .favoritesDownload,
            .installerMinecraftDownload, .installerOptiFineDownload, .installerForgeDownload, .installerNeoForgeDownload, .installerCleanroomDownload, .installerFabricDownload, .installerLegacyFabricDownload, .installerQuiltDownload, .installerLabyModDownload, .installerLiteLoaderDownload:
            DownloadSidebar()
        case .multiplayer, .multiplayerSub, .multiplayerSettings: MultiplayerSidebar()
        case .settings, .javaSettings, .otherSettings: SettingsSidebar()
        case .more, .about, .toolbox: MoreSidebar()
        case .tasks: TasksSidebar()
        default: EmptySidebar()
        }
    }

    var isSubPage: Bool {
        switch getLast() {
        case .tasks: true
        case .instanceList, .noInstanceRepository: true
        case .instanceSettings, .instanceOverview, .instanceConfig, .instanceModify, .instanceExport,
             .instanceSaves, .instanceScreenshots, .instanceMods, .instanceResourcepacks, .instanceShaderpacks, .instanceSchematics, .instanceServers: true
        case .minecraftInstallOptions: true
        case .projectInstall: true
        default: false
        }
    }

    var title: String {
        switch getLast() {
        case .tasks:
            return "任务列表"
        case .instanceList, .noInstanceRepository:
            return "实例选择"
        case .instanceSettings(let id), .instanceOverview(let id), .instanceConfig(let id), .instanceModify(let id), .instanceExport(let id), .instanceSaves(let id), .instanceScreenshots(let id), .instanceMods(let id), .instanceResourcepacks(let id), .instanceShaderpacks(let id), .instanceSchematics(let id), .instanceServers(let id):
            return "实例设置 - \(id)"
        case .minecraftInstallOptions(let version, let modifyContext):
            if modifyContext != nil {
                return "版本管理 - \(version.id)"
            }
            return "游戏安装 - \(version.id)"
        case .projectInstall(let target):
            return "资源下载 - \(target.title)"
        default:
            return "错误：当前页面没有标题，请报告此问题！"
        }
    }
}
