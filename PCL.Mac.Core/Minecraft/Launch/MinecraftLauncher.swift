//
//  MinecraftLauncher.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/11/26.
//

import Foundation

public class MinecraftLauncher {
    private static let gameLogQueue: DispatchQueue = .init(label: "PCL.Mac.GameLog")
    public let options: LaunchOptions
    public let logURL: URL
    private let manifest: ClientManifest
    private let runningDirectory: URL
    private let librariesURL: URL
    private let effectiveMemoryMB: UInt64
    private let effectiveMinMemoryMB: UInt64
    private var values: [String: String]
    
    public init(options: LaunchOptions) {
        self.manifest = options.manifest
        self.runningDirectory = options.runningDirectory
        self.librariesURL = options.repository.librariesURL
        self.options = options
        self.logURL = URLConstants.tempURL.appending(path: "game-log-\(UUID().uuidString.lowercased()).log")
        let tunedMemory: UInt64 = Self.tuneMemoryMB(requested: options.memory)
        self.effectiveMemoryMB = tunedMemory
        self.effectiveMinMemoryMB = max(512, min(1024, tunedMemory / 4))
        self.values = [
            "natives_directory": runningDirectory.appending(path: "natives").path,
            "launcher_name": "PCL.Mac",
            "launcher_version": Metadata.appVersion,
            "classpath_separator": ":",
            "library_directory": librariesURL.path,
            "max_memory": "\(self.effectiveMemoryMB)M",
            "min_memory": "\(self.effectiveMinMemoryMB)M",
            "maxMemory": "\(self.effectiveMemoryMB)M",
            "minMemory": "\(self.effectiveMinMemoryMB)M",
            
            "auth_player_name": options.profile.name,
            "version_name": options.runningDirectory.lastPathComponent,
            "game_directory": runningDirectory.path,
            "assets_root": librariesURL.deletingLastPathComponent().appending(path: "assets").path,
            "assets_index_name": manifest.assetIndex.id,
            "auth_uuid": UUIDUtils.string(of: options.profile.id, withHyphens: false),
            "auth_access_token": options.accessToken,
            "clientid": "",
            "auth_xuid": "",
            "xuid": "",
            "user_type": "msa",
            "version_type": "PCL.Mac",
            "user_properties": "{}"
        ]
    }
    
    /// 启动 Minecraft。
    /// - Returns: 游戏进程。
    public func launch() throws -> Process {
        values["classpath"] = buildClasspath()
        let process: Process = .init()
        process.executableURL = options.javaRuntime.executableURL
        process.currentDirectoryURL = runningDirectory
        
        var arguments: [String] = []
        arguments.append(contentsOf: manifest.jvmArguments.flatMap { $0.rules.allSatisfy { $0.test(with: options) } ? $0.value : [] })
        arguments.append(manifest.mainClass)
        arguments.append(contentsOf: manifest.gameArguments.flatMap { $0.rules.allSatisfy { $0.test(with: options) } ? $0.value : [] })
        arguments = arguments.map { Utils.replace($0, withValues: values) }
        arguments = arguments.map(sanitizeUnresolvedPlaceholders)
        arguments = removeEmptyOptionalArguments(arguments)
        arguments = filterKnownUnsafeRuntimeArguments(arguments)
        applyRuntimePerformanceDefaults(arguments: &arguments)
        process.arguments = arguments
        process.environment = sanitizedLaunchEnvironment()
        
        let pipe: Pipe = .init()
        process.standardOutput = pipe
        process.standardError = pipe
        
        log("正在使用以下参数启动 Minecraft：\(arguments.map { $0 == options.accessToken ? "🥚" : $0 })")
        try process.run()
        Self.gameLogQueue.async {
            FileManager.default.createFile(atPath: self.logURL.path, contents: nil)
            let handle: FileHandle?
            do {
                handle = try .init(forWritingTo: self.logURL)
            } catch {
                err("开启日志 FileHandle 失败：\(error.localizedDescription)")
                handle = nil
            }
            defer { try? handle?.close() }
            
            while process.isRunning {
                let data: Data = pipe.fileHandleForReading.availableData
                if data.isEmpty { break }
                try? handle?.write(contentsOf: data)
            }
        }
        return process
    }
    
    private func buildClasspath() -> String {
        var urls: [URL] = []
        for library in manifest.getLibraries() {
            if let artifact = library.artifact {
                urls.append(librariesURL.appending(path: artifact.path))
            }
        }
        urls.append(runningDirectory.appending(path: "\(runningDirectory.lastPathComponent).jar"))
        return urls.map(\.path).joined(separator: ":")
    }

    private func applyRuntimePerformanceDefaults(arguments: inout [String]) {
        let lowered = arguments.map { $0.lowercased() }
        let usingOpenJ9 = isOpenJ9Runtime()

        if !lowered.contains(where: { $0.hasPrefix("-xmx") }) {
            arguments.insert("-Xmx\(effectiveMemoryMB)M", at: 0)
        }
        if !lowered.contains(where: { $0.hasPrefix("-xms") }) {
            arguments.insert("-Xms\(effectiveMinMemoryMB)M", at: 0)
        }

        let hasGCConfigured = lowered.contains {
            $0.contains("useg1gc") || $0.contains("usezgc") || $0.contains("useshenandoahgc") || $0.contains("useparallelgc") || $0.contains("useconcmarksweepgc") || $0.hasPrefix("-xgcpolicy:")
        }
        if !hasGCConfigured {
            if usingOpenJ9 {
                arguments.insert("-Xgcpolicy:gencon", at: 0)
            } else {
                arguments.insert(contentsOf: [
                    "-XX:+UseG1GC",
                    "-XX:MaxGCPauseMillis=20",
                    "-XX:+ParallelRefProcEnabled"
                ], at: 0)
            }
        }

        if usingOpenJ9 {
            let hasSoftMx = lowered.contains { $0.hasPrefix("-xsoftmx") }
            if !hasSoftMx {
                let softMx = max(1024, UInt64(Double(effectiveMemoryMB) * 0.85))
                arguments.insert("-Xsoftmx\(softMx)M", at: 0)
            }
        } else {
            let hasMinHeapFreeRatio = lowered.contains { $0.hasPrefix("-xx:minheapfreeratio=") }
            if !hasMinHeapFreeRatio {
                arguments.insert("-XX:MinHeapFreeRatio=10", at: 0)
            }
            let hasMaxHeapFreeRatio = lowered.contains { $0.hasPrefix("-xx:maxheapfreeratio=") }
            if !hasMaxHeapFreeRatio {
                arguments.insert("-XX:MaxHeapFreeRatio=30", at: 0)
            }
            if options.javaRuntime.majorVersion >= 12 {
                let hasG1PeriodicGCInterval = lowered.contains { $0.hasPrefix("-xx:g1periodicgcinterval=") }
                if !hasG1PeriodicGCInterval {
                    arguments.insert("-XX:G1PeriodicGCInterval=30000", at: 0)
                }
                let hasG1PeriodicGCConcurrent = lowered.contains { $0 == "-xx:+g1periodicgcinvokesconcurrent" }
                if !hasG1PeriodicGCConcurrent {
                    arguments.insert("-XX:+G1PeriodicGCInvokesConcurrent", at: 0)
                }
            }
        }
    }

    private func isOpenJ9Runtime() -> Bool {
        if let implementor = options.javaRuntime.implementor?.lowercased() {
            if implementor.contains("ibm") || implementor.contains("semeru") || implementor.contains("openj9") {
                return true
            }
        }
        return options.javaRuntime.executableURL.path == "/usr/bin/java"
    }

    private func sanitizeUnresolvedPlaceholders(_ argument: String) -> String {
        var value = argument
        while let start = value.range(of: "${"), let end = value[start.upperBound...].firstIndex(of: "}") {
            value.removeSubrange(start.lowerBound...end)
        }
        return value
    }

    private func removeEmptyOptionalArguments(_ arguments: [String]) -> [String] {
        let optionsWithValue: Set<String> = ["--clientId", "--xuid"]
        var result: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if let equalIndex = argument.firstIndex(of: "=") {
                let name = String(argument[..<equalIndex])
                if optionsWithValue.contains(name) {
                    let value = String(argument[argument.index(after: equalIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if value.isEmpty {
                        index += 1
                        continue
                    }
                }
            }

            if optionsWithValue.contains(argument) {
                let nextIndex = index + 1
                guard nextIndex < arguments.count else {
                    index += 1
                    continue
                }
                let value = arguments[nextIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                if value.isEmpty || value.hasPrefix("--") {
                    index += 2
                    continue
                }
                result.append(argument)
                result.append(value)
                index += 2
                continue
            }

            if !argument.isEmpty {
                result.append(argument)
            }
            index += 1
        }

        return result
    }

    private func filterKnownUnsafeRuntimeArguments(_ arguments: [String]) -> [String] {
        guard shouldDisableCompactObjectHeaders else {
            return arguments
        }

        let filtered = arguments.filter { $0.lowercased() != "-xx:+usecompactobjectheaders" }
        if filtered.count != arguments.count {
            warn("检测到 Java \(options.javaRuntime.version) 在当前 macOS/CPU 组合下启用 Compact Object Headers 可能导致崩溃，已自动移除该参数。")
        }
        return filtered
    }

    private var shouldDisableCompactObjectHeaders: Bool {
        options.javaRuntime.majorVersion >= 25 && options.javaRuntime.architecture == .arm64
    }

    private func sanitizedLaunchEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        guard shouldDisableCompactObjectHeaders else {
            return environment
        }

        let blockedKeys = ["JDK_JAVA_OPTIONS", "JAVA_TOOL_OPTIONS", "_JAVA_OPTIONS"]
        for key in blockedKeys {
            if let value = environment[key], value.localizedCaseInsensitiveContains("UseCompactObjectHeaders") {
                warn("检测到环境变量 \(key) 注入了 Compact Object Headers 相关参数，已在启动时清除。")
                environment.removeValue(forKey: key)
            }
        }
        return environment
    }

    private static func tuneMemoryMB(requested: UInt64) -> UInt64 {
        let physicalMB = max(UInt64(2048), ProcessInfo.processInfo.physicalMemory / 1024 / 1024)
        let maxSafeByDevice = max(UInt64(1536), UInt64(Double(physicalMB) * 0.5))
        let upperBound = min(UInt64(16384), maxSafeByDevice)
        let lowerBound: UInt64 = 1024
        return min(max(requested, lowerBound), upperBound)
    }
}
