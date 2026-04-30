//
//  InstanceConfigViewModel.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/6.
//

import Foundation
import Core

@MainActor
class InstanceConfigViewModel: ObservableObject {
    @Published public var instance: MinecraftInstance?
    @Published public var jvmHeapSize: String = ""
    @Published public var memoryMode: MinecraftInstance.Config.MemoryMode = .custom
    @Published public var versionIsolationEnabled: Bool = true
    @Published public var javaDescription: String = "无"
    @Published public var autoSelectJava: Bool = true
    @Published public var javaSelectionHint: String = ""
    @Published public var windowTitleFollowsGlobal: Bool = true
    @Published public var customWindowTitle: String = ""
    @Published public var customInfo: String = ""
    @Published public var serverEntry: String = ""
    @Published public var jvmArgs: String = ""
    @Published public var gameArgs: String = ""
    @Published public var classpathPrefix: String = ""
    @Published public var launchPrecommand: String = ""
    @Published public var followProxySettings: Bool = true
    @Published public var disableValidation: Bool = false
    @Published public var useLog4jConfig: Bool = false
    @Published public var loaded: Bool = false
    
    public var description: String {
        guard let instance else { return "" }
        if let modLoader: ModLoader = instance.modLoader {
            return "\(instance.version.description)，\(modLoader)"
        }
        return instance.version.description
    }
    
    public var icon: ImageResource {
        if let modLoader: ModLoader = instance?.modLoader {
            return modLoader.icon
        }
        return .iconGrassBlock
    }
    
    public let id: String
    
    public init(id: String) {
        self.id = id
    }
    
    public func load() async throws {
        let instance: MinecraftInstance = try InstanceManager.shared.loadInstance(id)
        self.instance = instance
        self.jvmHeapSize = instance.config.jvmHeapSize.description
        self.memoryMode = instance.config.memoryMode
        self.versionIsolationEnabled = instance.config.versionIsolationEnabled
        self.autoSelectJava = instance.config.autoSelectJava
        self.windowTitleFollowsGlobal = instance.config.windowTitle == nil
        self.customWindowTitle = instance.config.windowTitle ?? instance.name
        self.customInfo = InstanceMetadataService.description(for: id)
        self.serverEntry = instance.config.autoJoinServer ?? ""
        self.jvmArgs = instance.config.jvmArguments
        self.gameArgs = instance.config.gameArguments
        self.classpathPrefix = instance.config.classpathPrefix
        self.launchPrecommand = instance.config.preLaunchCommand
        self.followProxySettings = instance.config.followProxySettings
        self.disableValidation = instance.config.disableResourceValidation
        self.useLog4jConfig = instance.config.enableLog4jDebug
        self.refreshJavaDescription()
        self.loaded = true
    }
    
    public func javaList() -> [JavaRuntime] {
        return JavaManager.shared.javaRuntimes
            .filter { $0.executableURL != instance?.config.javaURL }
            .sorted { $0.version > $1.version }
    }
    
    @MainActor
    public func setHeapSize(_ heapSize: UInt64) {
        guard let instance else { return }
        memoryMode = .custom
        instance.setMemoryMode(.custom)
        instance.setJVMHeapSize(heapSize)
    }

    @MainActor
    public func setMemoryMode(_ mode: MinecraftInstance.Config.MemoryMode) {
        guard let instance else { return }
        memoryMode = mode
        instance.setMemoryMode(mode)
    }

    @MainActor
    public func setVersionIsolationEnabled(_ enabled: Bool) {
        guard let instance else { return }
        versionIsolationEnabled = enabled
        instance.setVersionIsolationEnabled(enabled)
    }
    
    @MainActor
    public func switchJava(to runtime: JavaRuntime) throws {
        guard let instance else { return }
        let javaRange = instance.manifest.supportedJavaMajorRange(
            for: instance.version,
            modLoader: instance.modLoader,
            modLoaderVersion: instance.modLoaderVersion
        )
        if !javaRange.contains(runtime.majorVersion) {
            throw Error.invalidJavaVersion(min: javaRange.lowerBound, max: javaRange.upperBound)
        }
        instance.config.autoSelectJava = false
        instance.setJava(url: runtime.executableURL)
        autoSelectJava = false
        refreshJavaDescription()
    }

    @MainActor
    public func setAutoSelectJava(_ enabled: Bool) {
        guard let instance else { return }
        instance.setAutoSelectJava(enabled)
        if enabled {
            _ = instance.resolveJavaForLaunch()
        }
        autoSelectJava = enabled
        refreshJavaDescription()
    }

    @MainActor
    public func setWindowTitleFollowsGlobal(_ enabled: Bool) {
        guard let instance else { return }
        windowTitleFollowsGlobal = enabled
        if enabled {
            instance.setWindowTitle(nil)
        } else {
            let title = customWindowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty {
                customWindowTitle = instance.name
                instance.setWindowTitle(instance.name)
            } else {
                instance.setWindowTitle(title)
            }
        }
    }

    @MainActor
    public func setCustomWindowTitle(_ title: String) {
        guard let instance else { return }
        customWindowTitle = title
        guard !windowTitleFollowsGlobal else { return }
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        instance.setWindowTitle(normalized.isEmpty ? instance.name : normalized)
    }

    @MainActor
    public func setCustomInfo(_ text: String) {
        customInfo = text
        InstanceMetadataService.setDescription(text, for: id)
    }

    @MainActor
    public func setServerEntry(_ value: String) {
        guard let instance else { return }
        serverEntry = value
        instance.setAutoJoinServer(value)
    }

    @MainActor
    public func setJVMArguments(_ value: String) {
        guard let instance else { return }
        jvmArgs = value
        instance.setJVMArguments(value)
    }

    @MainActor
    public func setGameArguments(_ value: String) {
        guard let instance else { return }
        gameArgs = value
        instance.setGameArguments(value)
    }

    @MainActor
    public func setClasspathPrefix(_ value: String) {
        guard let instance else { return }
        classpathPrefix = value
        instance.setClasspathPrefix(value)
    }

    @MainActor
    public func setLaunchPrecommand(_ value: String) {
        guard let instance else { return }
        launchPrecommand = value
        instance.setPreLaunchCommand(value)
    }

    @MainActor
    public func setFollowProxySettings(_ enabled: Bool) {
        guard let instance else { return }
        followProxySettings = enabled
        instance.setFollowProxySettings(enabled)
    }

    @MainActor
    public func setDisableValidation(_ enabled: Bool) {
        guard let instance else { return }
        disableValidation = enabled
        instance.setDisableResourceValidation(enabled)
    }

    @MainActor
    public func setUseLog4jConfig(_ enabled: Bool) {
        guard let instance else { return }
        useLog4jConfig = enabled
        instance.setEnableLog4jDebug(enabled)
    }

    @MainActor
    public func refreshJavaDescription() {
        guard let instance else {
            javaDescription = "无"
            javaSelectionHint = ""
            return
        }

        if let runtime: JavaRuntime = instance.previewResolvedJavaForLaunch() {
            javaDescription = runtime.description
            javaSelectionHint = "当前模式：\(instance.config.autoSelectJava ? "自动" : "手动")。当前生效：\(runtime.version)（\(runtime.executableURL.path)）"
        } else {
            javaDescription = "无"
            javaSelectionHint = "当前模式：\(instance.config.autoSelectJava ? "自动" : "手动")。当前生效：未找到可用 Java"
        }
    }
    
    public enum Error: Swift.Error {
        case invalidJavaVersion(min: Int, max: Int)
    }
}
