import SwiftUI

extension AppRouter {
    @ViewBuilder
    var content: some View {
        switch getLast() {
        case .launch:
            LaunchPage()
        case .minecraftDownload:
            MinecraftDownloadPage()
        case .minecraftInstallOptions(let version, let modifyContext):
            MinecraftInstallOptionsPage(version: version, modifyContext: modifyContext)
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
        case .projectInstall(let target):
            ResourceInstallPage(target: target)
                .id(target)
        case .tasks:
            TasksPage()
        case .instanceList(let target):
            InstanceListPage(target: target)
        case .noInstanceRepository:
            NoInstanceRepositoryPage()
        case .multiplayerSub:
            MultiplayerPage()
        case .multiplayerSettings:
            MultiplayerSettingsPage()
        case .javaSettings:
            JavaSettingsPage()
        case .updateSettings:
            UpdateSettingsPage()
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
            InstanceScreenshotsPage(id: id)
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
                listActionButtonWidth: 100,
                remoteProjectType: .resourcepack
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
                listActionButtonWidth: 100,
                remoteProjectType: .shader
            )
        case .instanceSchematics(let id):
            InstanceSchematicsPage(id: id)
        case .instanceServers(let id):
            InstanceServersPage(id: id)
        default:
            Spacer()
        }
    }
}
