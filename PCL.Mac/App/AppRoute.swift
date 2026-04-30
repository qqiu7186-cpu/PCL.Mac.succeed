import SwiftUI
import Core

struct ProjectInstallTarget: Identifiable, Hashable, Equatable {
    let id: String
    let title: String
    let type: ModrinthProjectType

    init(id: String, title: String, type: ModrinthProjectType) {
        self.id = id
        self.title = title
        self.type = type
    }

    init(project: ProjectListItemModel) {
        self.init(id: project.id, title: project.title, type: project.type)
    }
}

struct RepositoryRouteTarget: Identifiable, Hashable, Equatable {
    let repositoryPath: String
    let name: String

    var id: String { repositoryPath }

    init(repository: MinecraftRepository) {
        self.repositoryPath = repository.url.standardizedFileURL.path
        self.name = repository.name
    }
}

struct InstanceModifyContext: Identifiable, Hashable, Equatable {
    let instanceID: String

    var id: String { instanceID }
}

enum AppRoute: Identifiable, Hashable, Equatable {
    case launch, download, multiplayer, settings, more, tasks

    case instanceList(RepositoryRouteTarget), noInstanceRepository, instanceSettings(id: String)

    case instanceOverview(id: String), instanceConfig(id: String), instanceModify(id: String), instanceExport(id: String)
    case instanceSaves(id: String), instanceScreenshots(id: String), instanceMods(id: String), instanceResourcepacks(id: String), instanceShaderpacks(id: String), instanceSchematics(id: String), instanceServers(id: String)

    case minecraftDownload, minecraftInstallOptions(version: VersionManifest.Version, modifyContext: InstanceModifyContext? = nil)
    case modDownload, modpackDownload, datapackDownload, resourcepackDownload, shaderpackDownload, worldDownload, favoritesDownload
    case installerMinecraftDownload, installerOptiFineDownload, installerForgeDownload, installerNeoForgeDownload, installerCleanroomDownload, installerFabricDownload, installerLegacyFabricDownload, installerQuiltDownload, installerLabyModDownload, installerLiteLoaderDownload
    case projectInstall(ProjectInstallTarget)

    case multiplayerSub, multiplayerSettings

    case javaSettings, otherSettings

    case about, toolbox

    var id: String { stringValue }

    var stringValue: String {
        switch self {
        default: String(describing: self)
        }
    }
}
