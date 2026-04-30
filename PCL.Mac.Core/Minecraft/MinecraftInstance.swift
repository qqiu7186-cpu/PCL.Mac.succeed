//
//  MinecraftInstance.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/11/25.
//

import Foundation
import SwiftyJSON

public class MinecraftInstance: Equatable {
    private static let configFileName: String = ".clconfig.json"
    public let runningDirectory: URL
    public let version: MinecraftVersion
    public let manifest: ClientManifest
    public let config: Config
    public let modLoader: ModLoader?
    public let modLoaderVersion: String?
    
    public var name: String { runningDirectory.lastPathComponent }
    public var manifestURL: URL { runningDirectory.appending(path: "\(name).json") }
    
    private var cachedJavaRuntime: JavaRuntime?
    
    /// 根据运行目录、版本与客户端清单创建实例对象。
    ///
    /// 如果只需要从磁盘加载实例，请使用 `MinecraftInstance.load(from:)`。
    /// - Parameters:
    ///   - runningDirectory: 实例运行目录。
    ///   - version: 实例的 Minecraft 版本。
    ///   - manifest: 客户端清单。
    ///   - config: 实例配置。
    ///   - modLoader: 实例安装的模组加载器。
    public init(runningDirectory: URL, version: MinecraftVersion, manifest: ClientManifest, config: Config, modLoader: ModLoader?, modLoaderVersion: String?) {
        self.runningDirectory = runningDirectory
        self.version = version
        self.manifest = manifest
        self.config = config
        self.modLoader = modLoader
        self.modLoaderVersion = modLoaderVersion
        VersionCache.add(version: version, for: self)
        if config.autoSelectJava && config.javaURL == nil {
            setJava(url: searchJava().map(\.executableURL))
        }
    }
    
    /// 设置 JVM Heap Size 并保存。
    public func setJVMHeapSize(_ heapSize: UInt64) {
        config.jvmHeapSize = heapSize
        saveConfig()
    }

    public func setMemoryMode(_ mode: Config.MemoryMode) {
        config.memoryMode = mode
        saveConfig()
    }

    public func setVersionIsolationEnabled(_ enabled: Bool) {
        config.versionIsolationEnabled = enabled
        saveConfig()
    }
    
    /// 设置实例使用的 Java 并保存。
    public func setJava(url: URL?) {
        config.javaURL = url
        saveConfig()
        cachedJavaRuntime = nil
    }

    public func setAutoSelectJava(_ enabled: Bool) {
        config.autoSelectJava = enabled
        saveConfig()
    }

    public func setWindowTitle(_ title: String?) {
        config.windowTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        saveConfig()
    }

    public func setAutoJoinServer(_ entry: String?) {
        config.autoJoinServer = entry?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        saveConfig()
    }

    public func setJVMArguments(_ arguments: String) {
        config.jvmArguments = arguments
        saveConfig()
    }

    public func setGameArguments(_ arguments: String) {
        config.gameArguments = arguments
        saveConfig()
    }

    public func setClasspathPrefix(_ prefix: String) {
        config.classpathPrefix = prefix
        saveConfig()
    }

    public func setPreLaunchCommand(_ command: String) {
        config.preLaunchCommand = command
        saveConfig()
    }

    public func setFollowProxySettings(_ enabled: Bool) {
        config.followProxySettings = enabled
        saveConfig()
    }

    public func setDisableResourceValidation(_ enabled: Bool) {
        config.disableResourceValidation = enabled
        saveConfig()
    }

    public func setEnableLog4jDebug(_ enabled: Bool) {
        config.enableLog4jDebug = enabled
        saveConfig()
    }
    
    /// 搜索最适合的 Java。
    /// - Parameters:
    ///   - arch: 目标 Java 架构。
    /// - Returns: 搜到的 Java。
    @discardableResult
    public func searchJava(arch: Architecture? = nil) -> JavaRuntime? {
        let javaRange = manifest.supportedJavaMajorRange(for: version, modLoader: modLoader, modLoaderVersion: modLoaderVersion)

        func getScore(of runtime: JavaRuntime) -> Int {
            var score: Int = 0
            if shouldAvoidRuntimeForLaunch(runtime) { score -= 100 }
            if runtime.architecture == preferredArchitectureForLaunch() { score += 3 }
            if runtime.majorVersion == manifest.requiredJavaMajorVersion(for: version) { score += 2 }
            if runtime.type == .jdk { score += 1 }
            if runtime.implementor?.contains("Azul") == true { score += 1 }
            return score
        }
        
        if let runtime: JavaRuntime = JavaManager.shared.javaRuntimes
            .filter({ $0.architecture == (arch ?? $0.architecture) })
            .filter({ $0.majorVersion >= manifest.requiredJavaMajorVersion(for: version) })
            .filter({ javaRange.contains($0.majorVersion) })
            .filter({ !shouldAvoidRuntimeForLaunch($0) })
            .max(by: { getScore(of: $0) < getScore(of: $1) }) {
            return runtime
        }
        warn("未找到 \(version) 可用的 Java")
        return nil
    }
    
    /// 获取实例使用的 `JavaRuntime` 对象。
    public func javaRuntime() -> JavaRuntime? {
        guard let javaURL = config.javaURL else {
            return nil
        }
        if let cachedJavaRuntime {
            return cachedJavaRuntime
        }
        do {
            let runtime: JavaRuntime = try JavaSearcher.load(from: javaURL)
            cachedJavaRuntime = runtime
            return runtime
        } catch {
            err("加载 Java 失败")
            setJava(url: nil)
            return nil
        }
    }

    private func resolveJavaForLaunch(persistSelection: Bool) -> JavaRuntime? {
        let minVersion: Int = manifest.requiredJavaMajorVersion(for: version)
        let javaRange = manifest.supportedJavaMajorRange(for: version, modLoader: modLoader, modLoaderVersion: modLoaderVersion)

        if config.autoSelectJava {
            guard let runtime: JavaRuntime = searchJava() else {
                return nil
            }
            if persistSelection, config.javaURL != runtime.executableURL {
                setJava(url: runtime.executableURL)
            }
            return runtime
        }

        guard let runtime: JavaRuntime = javaRuntime(), runtime.majorVersion >= minVersion, javaRange.contains(runtime.majorVersion), !shouldAvoidRuntimeForLaunch(runtime) else {
            return nil
        }
        return runtime
    }

    public func preferredArchitectureForLaunch() -> Architecture {
        if Architecture.systemArchitecture() == .arm64 && manifest.requiredJavaMajorVersion(for: version) >= 26 {
            return .x64
        }
        return version > .init("1.7.2") ? .systemArchitecture() : .x64
    }

    public func shouldAvoidRuntimeForLaunch(_ runtime: JavaRuntime) -> Bool {
        Architecture.systemArchitecture() == .arm64 && manifest.requiredJavaMajorVersion(for: version) >= 26 && runtime.architecture == .arm64
    }

    public func previewResolvedJavaForLaunch() -> JavaRuntime? {
        return resolveJavaForLaunch(persistSelection: false)
    }

    public func resolveJavaForLaunch() -> JavaRuntime? {
        return resolveJavaForLaunch(persistSelection: true)
    }
    
    private func saveConfig() {
        let url: URL = runningDirectory.appending(path: Self.configFileName)
        do {
            let data: Data = try JSONEncoder.shared.encode(config)
            try data.write(to: url)
        } catch {
            err("保存配置失败：\(error.localizedDescription)")
        }
    }
    
    /// 从磁盘加载实例。
    ///
    /// 对于老版本（如 `1.8.9`），可能无法正确检测 Minecraft 版本，所以请在安装完成时调用 `MinecraftInstance.init` 而不是本函数。
    /// - Parameters:
    ///   - runningDirectory: 实例运行目录。
    ///   - version: （可选）缓存的版本号。
    /// - Returns: 实例对象。
    public static func load(from runningDirectory: URL) throws -> MinecraftInstance {
        if FileManager.default.fileExists(atPath: runningDirectory.appending(path: ".incomplete").path) {
            throw MinecraftError.incomplete
        }
        // 加载客户端清单
        let manifestURL: URL = runningDirectory.appending(path: "\(runningDirectory.lastPathComponent).json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { throw MinecraftError.missingManifest }
        let (manifest, modLoader, modLoaderVersion): (ClientManifest, ModLoader?, String?) = try ClientManifest.load(at: manifestURL)
        // 获取版本
        let version: MinecraftVersion
        if let cachedVersion = VersionCache.version(of: manifestURL) {
            version = cachedVersion
        } else {
            let jarURL: URL = runningDirectory.appending(path: "\(runningDirectory.lastPathComponent).jar")
            if FileManager.default.fileExists(atPath: jarURL.path),
               try ArchiveUtils.hasEntry(url: jarURL, path: "version.json"),
               let json: JSON = try? JSON(data: ArchiveUtils.getEntry(url: jarURL, path: "version.json")) {
                log("成功解析 version.json")
                version = .init(json["id"].stringValue)
            } else if let clVersion: String = manifest.version {
                version = .init(clVersion)
            } else {
                warn("\(jarURL.lastPathComponent)!/version.json 不存在或解析失败，使用客户端清单中的 id 作为版本号")
                version = .init(manifest.id)
            }
            VersionCache.add(version: version.id, for: manifestURL)
        }
        
        let configURL: URL = runningDirectory.appending(path: configFileName)
        var config: Config? = nil
        if FileManager.default.fileExists(atPath: configURL.path) {
            do {
                config = try JSONDecoder.shared.decode(Config.self, from: Data(contentsOf: configURL))
            } catch {
                err("加载实例配置失败：\(error.localizedDescription)")
            }
        }
        
        let instance: MinecraftInstance = .init(
            runningDirectory: runningDirectory,
            version: version,
            manifest: manifest,
            config: config ?? .init(),
            modLoader: modLoader,
            modLoaderVersion: modLoaderVersion
        )
        return instance
    }
    
    public static func == (lhs: MinecraftInstance, rhs: MinecraftInstance) -> Bool {
        lhs.runningDirectory == rhs.runningDirectory
    }
    
    public class Config: Codable {
        public enum MemoryMode: String, Codable, CaseIterable {
            case global
            case auto
            case custom

            public var title: String {
                switch self {
                case .global: "跟随全局设置"
                case .auto: "自动配置"
                case .custom: "自定义"
                }
            }
        }

        public var jvmHeapSize: UInt64
        public var memoryMode: MemoryMode
        public var versionIsolationEnabled: Bool
        public var autoSelectJava: Bool
        public var javaURL: URL?
        public var windowTitle: String?
        public var autoJoinServer: String?
        public var jvmArguments: String
        public var gameArguments: String
        public var classpathPrefix: String
        public var preLaunchCommand: String
        public var followProxySettings: Bool
        public var disableResourceValidation: Bool
        public var enableLog4jDebug: Bool

        public var requestedMemoryMB: UInt64 {
            switch memoryMode {
            case .custom:
                max(1024, jvmHeapSize)
            case .global, .auto:
                4096
            }
        }
        
        public init() {
            self.jvmHeapSize = 4096
            self.memoryMode = .custom
            self.versionIsolationEnabled = true
            self.autoSelectJava = true
            self.javaURL = nil
            self.windowTitle = nil
            self.autoJoinServer = nil
            self.jvmArguments = ""
            self.gameArguments = ""
            self.classpathPrefix = ""
            self.preLaunchCommand = ""
            self.followProxySettings = true
            self.disableResourceValidation = false
            self.enableLog4jDebug = false
        }
        
        private enum CodingKeys: String, CodingKey {
            case jvmHeapSize, memoryMode, versionIsolationEnabled, autoSelectJava, javaURL, windowTitle, autoJoinServer, jvmArguments, gameArguments, classpathPrefix, preLaunchCommand, followProxySettings, disableResourceValidation, enableLog4jDebug
        }
        
        public required init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.jvmHeapSize = try container.decodeIfPresent(UInt64.self, forKey: .jvmHeapSize) ?? 4096
            self.memoryMode = try container.decodeIfPresent(MemoryMode.self, forKey: .memoryMode) ?? .custom
            self.versionIsolationEnabled = try container.decodeIfPresent(Bool.self, forKey: .versionIsolationEnabled) ?? true
            self.autoSelectJava = try container.decodeIfPresent(Bool.self, forKey: .autoSelectJava) ?? true
            self.javaURL = try container.decodeIfPresent(URL.self, forKey: .javaURL)
            self.windowTitle = try container.decodeIfPresent(String.self, forKey: .windowTitle)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            self.autoJoinServer = try container.decodeIfPresent(String.self, forKey: .autoJoinServer)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            self.jvmArguments = try container.decodeIfPresent(String.self, forKey: .jvmArguments) ?? ""
            self.gameArguments = try container.decodeIfPresent(String.self, forKey: .gameArguments) ?? ""
            self.classpathPrefix = try container.decodeIfPresent(String.self, forKey: .classpathPrefix) ?? ""
            self.preLaunchCommand = try container.decodeIfPresent(String.self, forKey: .preLaunchCommand) ?? ""
            self.followProxySettings = try container.decodeIfPresent(Bool.self, forKey: .followProxySettings) ?? true
            self.disableResourceValidation = try container.decodeIfPresent(Bool.self, forKey: .disableResourceValidation) ?? false
            self.enableLog4jDebug = try container.decodeIfPresent(Bool.self, forKey: .enableLog4jDebug) ?? false
        }
        
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(jvmHeapSize, forKey: .jvmHeapSize)
            try container.encode(memoryMode, forKey: .memoryMode)
            try container.encode(versionIsolationEnabled, forKey: .versionIsolationEnabled)
            try container.encode(autoSelectJava, forKey: .autoSelectJava)
            try container.encodeIfPresent(javaURL, forKey: .javaURL)
            try container.encodeIfPresent(windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty, forKey: .windowTitle)
            try container.encodeIfPresent(autoJoinServer?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty, forKey: .autoJoinServer)
            try container.encode(jvmArguments, forKey: .jvmArguments)
            try container.encode(gameArguments, forKey: .gameArguments)
            try container.encode(classpathPrefix, forKey: .classpathPrefix)
            try container.encode(preLaunchCommand, forKey: .preLaunchCommand)
            try container.encode(followProxySettings, forKey: .followProxySettings)
            try container.encode(disableResourceValidation, forKey: .disableResourceValidation)
            try container.encode(enableLog4jDebug, forKey: .enableLog4jDebug)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
