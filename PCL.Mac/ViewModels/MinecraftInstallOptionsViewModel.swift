//
//  MinecraftInstallOptionsViewModel.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/2/13.
//

import Foundation
import Core

@MainActor
class MinecraftInstallOptionsViewModel: ObservableObject {
    @Published public var name: String { didSet { checkName() } }
    @Published public var loader: MinecraftInstallTask.Loader? {
        willSet { lastLoader = loader?.type }
        didSet {
            if let lastLoader, loader == nil {
                if name == "\(version.id)-\(lastLoader)" {
                    name = version.id
                    return
                }
            } else if let loader, lastLoader == nil {
                if name == version.id {
                    name = "\(version.id)-\(loader.type)"
                    return
                }
            } else if let loader, let lastLoader {
                if name == "\(version.id)-\(lastLoader)" {
                    name = "\(version.id)-\(loader.type)"
                    return
                }
            }
            checkName()
        }
    }
    @Published public var errorMessage: String?
    public let version: VersionManifest.Version
    public let modifyContext: InstanceModifyContext?
    private var lastLoader: ModLoader?
    private let taskDispatcher: InstallTaskDispatching
    private let routeNavigator: InstallRouteNavigating
    private let prompter: InstallPrompting
    
    init(
        version: VersionManifest.Version,
        modifyContext: InstanceModifyContext? = nil,
        taskDispatcher: InstallTaskDispatching? = nil,
        routeNavigator: InstallRouteNavigating? = nil,
        prompter: InstallPrompting? = nil
    ) {
        self.version = version
        self.modifyContext = modifyContext
        self.name = modifyContext?.instanceID ?? version.id
        self.taskDispatcher = taskDispatcher ?? SharedInstallTaskDispatcher()
        self.routeNavigator = routeNavigator ?? SharedInstallRouteNavigator()
        self.prompter = prompter ?? SharedInstallPrompter()
        checkName()
    }
    
    private func checkName() {
        do {
            if name.isEmpty {
                errorMessage = "实例名不能为空！"
                return
            }
            if loader != nil && name == version.id {
                errorMessage = "带 Mod 加载器的实例名不能与版本号一致！"
                return
            }
            guard let repository: MinecraftRepository = InstanceManager.shared.currentRepository else {
                throw SimpleError("检查实例名失败：请先添加并选择一个游戏目录！")
            }
            if let modifyContext {
                if name != modifyContext.instanceID {
                    errorMessage = "版本管理模式下不能修改实例名。"
                    return
                }
                let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if normalized.isEmpty {
                    errorMessage = "实例名不能为空！"
                    return
                }
                if !repository.contains(normalized) {
                    errorMessage = "未找到要修改的实例：\(normalized)"
                    return
                }
                errorMessage = nil
                return
            }
            _ = try repository.checkInstanceName(name, trim: false)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func startInstall(in repository: MinecraftRepository, instanceManager: InstanceManager) -> String? {
        if let errorMessage {
            return errorMessage
        }

        if taskDispatcher.hasRunningInstallTask {
            routeNavigator.showTasksPageIfNeeded()
            return "当前有正在进行的安装任务，请稍后再试。"
        }

        let minecraftVersion = MinecraftVersion(version.id)
        let isReplacingExistingInstance = modifyContext != nil
        let task = MinecraftInstallTask.create(name: name, version: minecraftVersion, repository: repository, modLoader: loader, replaceExisting: isReplacingExistingInstance) { instance in
            instanceManager.switchInstance(to: instance, repository)
            AppRouter.shared.activeModifyContext = nil
            self.routeNavigator.dismissInstallOptionsIfNeeded()
        }

        taskDispatcher.executeMinecraftInstall(task) { error in
            guard let error else { return }
            Task { @MainActor in
                await self.prompter.showError(title: "下载/安装失败", content: "任务执行失败：\(error.localizedDescription)\n\n请检查日志后重试。")
            }
        }
        routeNavigator.showTasksPage()
        return nil
    }
}
