//
//  MinecraftInstallOptionsPage.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/2/11.
//

import SwiftUI
import Core
import SwiftyJSON

struct MinecraftInstallOptionsPage: View {
    @StateObject private var viewModel: MinecraftInstallOptionsViewModel
    @EnvironmentObject private var instanceVM: InstanceManager
    
    init(version: VersionManifest.Version) {
        self._viewModel = .init(wrappedValue: .init(version: version))
    }
    
    var body: some View {
        CardContainer {
            VStack {
                MyTip(text: "Forge / NeoForge 版本列表由 BMCLAPI 提供。", theme: .blue)
                    .padding(.bottom, 10)
                MyCard("", titled: false, limitHeight: false) {
                    HStack {
                        Image(icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .padding(.trailing, 12)
                        VStack(alignment: .leading) {
                            if let errorMessage = viewModel.errorMessage {
                                MyText(errorMessage, color: .red)
                            }
                            MyTextField(text: $viewModel.name)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 15)
                VStack(spacing: 6) {
                    ModLoaderCard(.fabric, viewModel.version.id, $viewModel.loader)
                        .cardIndex(1)
                    ModLoaderCard(.forge, viewModel.version.id, $viewModel.loader)
                        .cardIndex(2)
                    ModLoaderCard(.neoforge, viewModel.version.id, $viewModel.loader)
                        .cardIndex(3)
                }
                Spacer()
            }
            .padding(EdgeInsets(top: 10, leading: 25, bottom: 25, trailing: 25))
        }
        .overlay(alignment: .bottom) {
            MyExtraTextButton(image: "DownloadPageIcon", imageSize: 20, text: "开始下载") {
                if let errorMessage = viewModel.errorMessage {
                    hint(errorMessage, type: .critical)
                    return
                }
                guard let repository = instanceVM.currentRepository else {
                    warn("试图安装 \(viewModel.version)，但没有设置游戏仓库")
                    hint("请先添加一个游戏目录！", type: .critical)
                    return
                }
                let hasRunningInstallTask: Bool = TaskManager.shared.tasks
                    .contains(where: { $0.name.contains("安装") || $0.name.contains("下载") })
                if hasRunningInstallTask {
                    hint("当前有正在进行的安装任务，请稍后再试。", type: .info)
                    if AppRouter.shared.getLast() != .tasks {
                        AppRouter.shared.append(.tasks)
                    }
                    return
                }
                let minecraftVersion: MinecraftVersion = .init(viewModel.version.id)
                TaskManager.shared.execute(task: MinecraftInstallTask.create(name: viewModel.name, version: minecraftVersion, repository: repository, modLoader: viewModel.loader) { instance in
                    instanceVM.switchInstance(to: instance, repository)
                    if AppRouter.shared.getLast() == .tasks {
                        AppRouter.shared.removeLast()
                        if case .minecraftInstallOptions = AppRouter.shared.getLast() {
                            AppRouter.shared.removeLast()
                        }
                    }
                }, completion: { error in
                    if let error {
                        MessageBoxManager.shared.showText(
                            title: "下载/安装失败",
                            content: "任务执行失败：\(error.localizedDescription)\n\n请检查日志后重试。",
                            level: .error
                        )
                    }
                })
                AppRouter.shared.append(.tasks)
            }
            .padding()
        }
        .animation(.spring(duration: 0.2), value: viewModel.errorMessage)
    }
    
    private var icon: String {
        if let loader = viewModel.loader {
            return loader.type.icon
        } else {
            return viewModel.version.type == .snapshot ? "Dirt" : "GrassBlock"
        }
    }
}

private struct ModLoaderCard: View {
    @Binding private var currentLoader: MinecraftInstallTask.Loader?
    @State private var versions: [Version]?
    @State private var loadState: LoadState = .loading
    private let type: ModLoader
    private let minecraftVersion: String
    
    init(_ type: ModLoader, _ minecraftVersion: String, _ currentLoader: Binding<MinecraftInstallTask.Loader?>) {
        self.type = type
        self.minecraftVersion = minecraftVersion
        self._currentLoader = currentLoader
    }
    
    var body: some View {
        MyCard("", titled: false, limitHeight: false, padding: 0) {
            ZStack(alignment: .topLeading) {
                MyCard(type.description, foldable: loadState == .finished, folded: true) {
                    if let versions {
                        MyList(items: versions.map { ListItem(image: type.icon, name: $0.id, description: $0.beta ? "测试版" : "稳定版") }) { index in
                            if let index {
                                currentLoader = MinecraftInstallTask.Loader(type: type, version: versions[index].id)
                            } else {
                                currentLoader = nil
                            }
                        }
                    }
                }
                .disableCardAppearAnimation()
                HStack(spacing: 7) {
                    if let currentLoader, currentLoader.type == type {
                        Image(type.icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18)
                        MyText(currentLoader.version, color: .colorGray1)
                    } else {
                        MyText(loadState.description, color: .colorGray4)
                    }
                }
                .padding(.leading, 300)
                .padding(.top, 10)
                .allowsHitTesting(false)
            }
        }
        .task(id: type) {
            await loadVersions()
        }
    }
    
    private func loadVersions() async {
        do {
            let versions: [Version] = switch type {
            case .fabric:
                try await Requests.get("https://meta.fabricmc.net/v2/versions/loader/\(minecraftVersion)").json().arrayValue
                    .map { .init(id: $0["loader"]["version"].stringValue) }
            case .forge:
                try await requestFirstAvailableJSON(from: forgeListMirrors(minecraftVersion: minecraftVersion)).arrayValue
                    .map { Version(id: $0["version"].stringValue) }
            case .neoforge:
                try await requestFirstAvailableJSON(from: neoForgeListMirrors(minecraftVersion: minecraftVersion)).arrayValue
                    .map { json in
                        let version: String = json["version"].stringValue
                        return Version(id: version.hasPrefix("1.20.1-") ? String(version.dropFirst("1.20.1-".count)) : version)
                    }
            }
            await MainActor.run {
                self.versions = versions.sorted { $0.id.compare($1.id, options: .numeric) == .orderedDescending }
                loadState = versions.isEmpty ? .noUsableVersion : .finished
            }
        } catch {
            err("加载 \(type) 版本列表失败：\(error.localizedDescription)")
            await MainActor.run {
                loadState = .error(message: "网络连接中断（镜像重试失败）：\(error.localizedDescription)")
            }
        }
    }

    private func requestFirstAvailableJSON(from urls: [URL]) async throws -> JSON {
        let orderedUrls = NetworkMirrorSelector.prioritize(urls, key: "modloader.list.\(type.rawValue)")
        var errors: [String] = []
        for url in orderedUrls {
            try Task.checkCancellation()
            do {
                let json = try await Requests.get(url.absoluteString).json()
                NetworkMirrorSelector.markSuccess(url, key: "modloader.list.\(type.rawValue)")
                return json
            } catch {
                errors.append("\(url.host ?? url.absoluteString): \(error.localizedDescription)")
            }
        }
        throw SimpleError(errors.isEmpty ? "无可用镜像。" : errors.joined(separator: " | "))
    }

    private func forgeListMirrors(minecraftVersion: String) -> [URL] {
        [
            URL(string: "https://bmclapi2.bangbang93.com/forge/minecraft/\(minecraftVersion)")!,
            URL(string: "https://bmclapi.bangbang93.com/forge/minecraft/\(minecraftVersion)")!,
            URL(string: "https://download.mcbbs.net/forge/minecraft/\(minecraftVersion)")!,
            URL(string: "https://bmclapi2-cn.bangbang93.com/forge/minecraft/\(minecraftVersion)")!
        ]
    }

    private func neoForgeListMirrors(minecraftVersion: String) -> [URL] {
        [
            URL(string: "https://bmclapi2.bangbang93.com/neoforge/list/\(minecraftVersion)")!,
            URL(string: "https://bmclapi.bangbang93.com/neoforge/list/\(minecraftVersion)")!,
            URL(string: "https://download.mcbbs.net/neoforge/list/\(minecraftVersion)")!,
            URL(string: "https://bmclapi2-cn.bangbang93.com/neoforge/list/\(minecraftVersion)")!
        ]
    }
    
    private enum LoadState: Equatable, CustomStringConvertible {
        case loading
        case noUsableVersion
        case error(message: String)
        case finished
        
        var description: String {
            switch self {
            case .loading: "加载中"
            case .noUsableVersion: "无可用版本"
            case .error(let message): "加载失败：\(message)"
            case .finished: "可以添加"
            }
        }
    }
    
    private struct Version {
        public let id: String
        public let beta: Bool
        
        public init(id: String) {
            self.id = id
            // 稳定版判断逻辑：https://github.com/PCL-Community/PCL2-CE/blob/45773cb9c69e677a3ae334c3d1f55f08468d623a/Plain%20Craft%20Launcher%202/Modules/Minecraft/ModDownload.vb#L1047
            self.beta = id.contains("alpha")
        }
    }
}
