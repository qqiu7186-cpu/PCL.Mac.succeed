//
//  AppRouter.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/11/9.
//

import SwiftUI
import Core

enum AppRoute: Identifiable, Hashable, Equatable {
    // 根页面
    case launch, download, multiplayer, settings, more, tasks
    
    // 启动页面的子页面
    case instanceList(MinecraftRepository), noInstanceRepository, instanceSettings(id: String)
    
    // 实例设置页面的子页面
    case instanceOverview(id: String), instanceConfig(id: String), instanceModify(id: String), instanceExport(id: String)
    case instanceSaves(id: String), instanceScreenshots(id: String), instanceMods(id: String), instanceResourcepacks(id: String), instanceShaderpacks(id: String), instanceSchematics(id: String), instanceServers(id: String)
    
    // 下载页面的子页面
    case minecraftDownload, minecraftInstallOptions(version: VersionManifest.Version)
    case modDownload, modpackDownload, datapackDownload, resourcepackDownload, shaderpackDownload, worldDownload, favoritesDownload
    case installerMinecraftDownload, installerOptiFineDownload, installerForgeDownload, installerNeoForgeDownload, installerCleanroomDownload, installerFabricDownload, installerLegacyFabricDownload, installerQuiltDownload, installerLabyModDownload, installerLiteLoaderDownload
    case projectInstall(project: ProjectListItemModel)
    
    // 联机页面的子页面
    case multiplayerSub, multiplayerSettings
    
    // 设置页面的子页面
    case javaSettings, otherSettings
    
    // 更多页面的子页面
    case about, toolbox
    
    var id: String { stringValue }
    
    var stringValue: String {
        switch self {
        default: String(describing: self)
        }
    }
}

@MainActor
class AppRouter: ObservableObject {
    static let shared: AppRouter = .init()
    private static let rootRoutes: [AppRoute] = [.launch, .download, .multiplayer, .settings, .more]
    
    @Published private(set) var path: [AppRoute] = [.launch]
    
    /// 当前页面的主内容（右半部分）
    @ViewBuilder
    var content: some View {
        switch getLast() {
        case .launch:
            LaunchPage()
        case .minecraftDownload:
            MinecraftDownloadPage()
        case .minecraftInstallOptions(let version):
            MinecraftInstallOptionsPage(version: version)
        case .modDownload:
            ResourcesSearchPage(type: .mod)
        case .datapackDownload:
            ResourcesSearchPage(type: .mod, requiredCategories: ["datapack"])
        case .resourcepackDownload:
            ResourcesSearchPage(type: .resourcepack)
        case .shaderpackDownload:
            ResourcesSearchPage(type: .shader)
        case .modpackDownload:
            ResourcesSearchPage(type: .modpack)
        case .worldDownload:
            ResourcesSearchPage(type: .modpack, requiredCategories: ["worldgen"])
        case .favoritesDownload:
            FavoritesDownloadPage()
        case .installerMinecraftDownload:
            MinecraftDownloadPage()
        case .installerForgeDownload:
            ForgeInstallerPage()
        case .installerNeoForgeDownload:
            NeoForgeInstallerPage()
        case .installerFabricDownload:
            FabricInstallerPage()
        case .installerOptiFineDownload:
            OptiFineInstallerPage()
        case .installerCleanroomDownload:
            CleanroomInstallerPage()
        case .installerLegacyFabricDownload:
            LegacyFabricInstallerPage()
        case .installerQuiltDownload:
            QuiltInstallerPage()
        case .installerLabyModDownload:
            LabyModInstallerPage()
        case .installerLiteLoaderDownload:
            LiteLoaderInstallerPage()
        case .projectInstall(let project):
            ResourceInstallPage(project: project)
                .id(project)
        case .tasks:
            TasksPage()
        case .instanceList(let repository):
            InstanceListPage(repository: repository)
        case .noInstanceRepository:
            NoInstanceRepositoryPage()
        case .multiplayerSub:
            MultiplayerPage()
        case .multiplayerSettings:
            MultiplayerSettingsPage()
        case .javaSettings:
            JavaSettingsPage()
        case .otherSettings:
            OtherSettingsPage()
        case .about:
            AboutPage()
        case .toolbox:
            ToolboxPage()
        case .instanceConfig(let id):
            InstanceConfigPage(id: id)
        case .instanceOverview(let id):
            InstanceOverviewPage(id: id)
        case .instanceModify(let id):
            InstanceModifyPage(id: id)
        case .instanceExport(let id):
            InstanceExportPage(id: id)
        case .instanceMods(let id):
            InstanceModsPage(id: id)
        case .instanceSaves(let id):
            InstanceSavesPage(id: id)
        case .instanceScreenshots(let id):
            InstanceFolderResourcePage(
                id: id,
                title: "截图",
                folderName: "screenshots",
                allowedTypes: [.png, .jpeg, .bmp, .webP, .tiff],
                quickOpenButtonText: "打开截图文件夹",
                importButtonText: "从文件安装",
                emptyTitle: "暂时没有截图文件",
                emptyDescription: "在游戏内按下截图键(默认为F2)后，可在此处查看保存的截图。",
                showImportButton: false,
                showEmptyOpenFolderButton: true,
                hideTopCardWhenEmpty: true,
                hideListCountWhenEmpty: true
            )
        case .instanceResourcepacks(let id):
            InstanceFolderResourcePage(
                id: id,
                title: "资源包",
                folderName: "resourcepacks",
                allowedTypes: [.zip],
                quickOpenButtonText: "打开资源包文件夹",
                importButtonText: "从文件安装",
                emptyTitle: "尚未安装资源包",
                emptyDescription: "你可以从已经下载好的文件安装资源包。",
                showEmptyOpenFolderButton: true,
                hideTopCardWhenEmpty: true,
                hideListCountWhenEmpty: true,
                emptyDownloadButtonText: "下载资源包",
                primaryButtonWidth: 130,
                listActionButtonWidth: 100
            )
        case .instanceShaderpacks(let id):
            InstanceFolderResourcePage(
                id: id,
                title: "光影包",
                folderName: "shaderpacks",
                allowedTypes: [.zip],
                quickOpenButtonText: "打开光影包文件夹",
                importButtonText: "从文件安装",
                emptyTitle: "尚未安装光影包",
                emptyDescription: "你可以从已经下载好的文件安装光影包。",
                showEmptyOpenFolderButton: true,
                hideTopCardWhenEmpty: true,
                hideListCountWhenEmpty: true,
                emptyDownloadButtonText: "下载光影包",
                primaryButtonWidth: 130,
                listActionButtonWidth: 100
            )
        case .instanceSchematics(let id):
            InstanceFolderResourcePage(
                id: id,
                title: "投影原理图",
                folderName: "schematics",
                allowedTypes: [.data, .zip],
                quickOpenButtonText: "打开投影原理图文件夹",
                importButtonText: "从文件安装",
                emptyTitle: "该实例暂时没有投影原理图",
                emptyDescription: "如需使用投影，请先安装相关 Mod 并启动一次游戏。"
            )
        case .instanceServers(let id):
            InstanceServersPage(id: id)
        default:
            Spacer()
        }
    }
    
    /// 当前页面的侧边栏（左半部分）
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
    
    /// 当前页面是不是子页面（需要显示返回键和标题，隐藏导航按钮）
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
    
    /// 当前子页面的标题
    var title: String {
        switch getLast() {
        case .tasks: "任务列表"
        case .instanceList, .noInstanceRepository: "实例列表"
        case .instanceSettings(let id), .instanceOverview(let id):
            "实例设置 · 概览（\(id)）"
        case .instanceConfig(let id):
            "实例设置 · 设置（\(id)）"
        case .instanceModify(let id):
            "实例设置 · 修改（\(id)）"
        case .instanceExport(let id):
            "实例设置 · 导出（\(id)）"
        case .instanceSaves(let id):
            "实例设置 · 存档（\(id)）"
        case .instanceScreenshots(let id):
            "实例设置 · 截图（\(id)）"
        case .instanceMods(let id):
            "实例设置 · 模组（\(id)）"
        case .instanceResourcepacks(let id):
            "实例设置 · 资源包（\(id)）"
        case .instanceShaderpacks(let id):
            "实例设置 · 光影包（\(id)）"
        case .instanceSchematics(let id):
            "实例设置 · 投影原理图（\(id)）"
        case .instanceServers(let id):
            "实例设置 · 服务器（\(id)）"
        case .minecraftInstallOptions(let version): "游戏安装 - \(version.id)"
        case .projectInstall(let project): "资源下载 - \(project.title)"
        default: "错误：当前页面没有标题，请报告此问题！"
        }
    }
    
    func getLast() -> AppRoute {
        return path[path.count - 1]
    }
    
    func getRoot() -> AppRoute {
        return path[0]
    }
    
    func setRoot(_ newRoot: AppRoute) {
        path = [newRoot]
        // 各根页面的默认子页面
        if newRoot == .download { append(.minecraftDownload) }
        if newRoot == .multiplayer { append(.multiplayerSub) }
        if newRoot == .settings { append(.javaSettings) }
        if newRoot == .more { append(.about) }
    }
    
    func append(_ route: AppRoute) {
        path.append(route)
        if case .instanceSettings(let id) = route { append(.instanceOverview(id: id)) }
    }
    
    func removeLast() {
        if path.count > 1 {
            path.removeLast()
            if case .instanceSettings = getLast() { removeLast() }
        }
    }

    func replaceInstanceID(from oldID: String, to newID: String) {
        path = path.map { route in
            switch route {
            case .instanceSettings(let id) where id == oldID: .instanceSettings(id: newID)
            case .instanceOverview(let id) where id == oldID: .instanceOverview(id: newID)
            case .instanceConfig(let id) where id == oldID: .instanceConfig(id: newID)
            case .instanceModify(let id) where id == oldID: .instanceModify(id: newID)
            case .instanceExport(let id) where id == oldID: .instanceExport(id: newID)
            case .instanceSaves(let id) where id == oldID: .instanceSaves(id: newID)
            case .instanceScreenshots(let id) where id == oldID: .instanceScreenshots(id: newID)
            case .instanceMods(let id) where id == oldID: .instanceMods(id: newID)
            case .instanceResourcepacks(let id) where id == oldID: .instanceResourcepacks(id: newID)
            case .instanceShaderpacks(let id) where id == oldID: .instanceShaderpacks(id: newID)
            case .instanceSchematics(let id) where id == oldID: .instanceSchematics(id: newID)
            case .instanceServers(let id) where id == oldID: .instanceServers(id: newID)
            default: route
            }
        }
    }
    
    private init() {}
}
