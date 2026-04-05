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
    @Published public var javaDescription: String = "无"
    @Published public var autoSelectJava: Bool = true
    @Published public var javaSelectionHint: String = ""
    @Published public var loaded: Bool = false
    
    public var description: String {
        guard let instance else { return "" }
        if let modLoader: ModLoader = instance.modLoader {
            return "\(instance.version.description)，\(modLoader)"
        }
        return instance.version.description
    }
    
    public var iconName: String {
        if let modLoader: ModLoader = instance?.modLoader {
            return modLoader.icon
        }
        return "GrassBlock"
    }
    
    public let id: String
    
    public init(id: String) {
        self.id = id
    }
    
    public func load() async throws {
        let instance: MinecraftInstance = try InstanceManager.shared.loadInstance(id)
        self.instance = instance
        self.jvmHeapSize = instance.config.jvmHeapSize.description
        self.autoSelectJava = instance.config.autoSelectJava
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
        instance.setJVMHeapSize(heapSize)
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
