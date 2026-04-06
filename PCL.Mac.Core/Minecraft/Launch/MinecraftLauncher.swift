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
            "user_type": options.userType,
            "version_type": "PCL.Mac",
            "user_properties": options.userProperties
        ]
    }
    
    /// 启动 Minecraft。
    /// - Returns: 游戏进程。
    public func launch() throws -> Process {
        values["classpath"] = buildClasspath()
        let process: Process = .init()
        process.executableURL = options.javaRuntime.executableURL
        process.currentDirectoryURL = runningDirectory

        let arguments = Self.buildLaunchArguments(
            manifest: manifest,
            values: values,
            options: options,
            effectiveMemoryMB: effectiveMemoryMB,
            effectiveMinMemoryMB: effectiveMinMemoryMB
        )
        process.arguments = arguments
        process.environment = sanitizedLaunchEnvironment()
        
        let pipe: Pipe = .init()
        process.standardOutput = pipe
        process.standardError = pipe
        
        log("正在使用以下参数启动 Minecraft：\(Self.redactedLaunchArguments(arguments, accessToken: options.accessToken))")
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

    public static func buildLaunchArguments(
        manifest: ClientManifest,
        values: [String: String],
        options: LaunchOptions,
        effectiveMemoryMB: UInt64? = nil,
        effectiveMinMemoryMB: UInt64? = nil
    ) -> [String] {
        let tunedMemory = effectiveMemoryMB ?? tuneMemoryMB(requested: options.memory)
        let tunedMinMemory = effectiveMinMemoryMB ?? max(512, min(1024, tunedMemory / 4))

        var arguments: [String] = []
        arguments.append(contentsOf: manifest.jvmArguments.flatMap { $0.rules.allSatisfy { $0.test(with: options) } ? $0.value : [] })
        arguments.append(manifest.mainClass)
        arguments.append(contentsOf: manifest.gameArguments.flatMap { $0.rules.allSatisfy { $0.test(with: options) } ? $0.value : [] })
        arguments = arguments.map { Utils.replace($0, withValues: values) }
        arguments = arguments.map(sanitizeUnresolvedPlaceholders)
        arguments = removeEmptyOptionalArguments(arguments)

        if let thirdPartyAuth = options.thirdPartyAuth {
            let metadataData = try? JSONEncoder.shared.encode(thirdPartyAuth.metadata)
            let encodedMetadata = metadataData?.base64EncodedString() ?? ""
            arguments.insert("-Dauthlibinjector.yggdrasil.prefetched=\(encodedMetadata)", at: 0)
            arguments.insert("-javaagent:\(thirdPartyAuth.injectorURL.path)=\(thirdPartyAuth.apiRoot.absoluteString)", at: 0)
        }

        if options.javaFallbackPolicy.sanitizeJvmArguments {
            arguments = sanitizeJVMArguments(arguments, options: options)
        }

        applyRuntimePerformanceDefaults(
            arguments: &arguments,
            options: options,
            effectiveMemoryMB: tunedMemory,
            effectiveMinMemoryMB: tunedMinMemory
        )
        return arguments
    }

    private static func redactedLaunchArguments(_ arguments: [String], accessToken: String) -> [String] {
        var redacted: [String] = []
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "-cp", "-classpath":
                let classpath = iterator.next() ?? ""
                let entryCount = classpath.isEmpty ? 0 : classpath.split(separator: ":").count
                redacted.append(argument)
                redacted.append("<已隐藏 classpath，共 \(entryCount) 项>")
            case "--accessToken":
                _ = iterator.next()
                redacted.append(argument)
                redacted.append("<已隐藏>")
            default:
                if argument == accessToken {
                    redacted.append("<已隐藏>")
                } else {
                    redacted.append(argument)
                }
            }
        }

        return redacted
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

    private static func applyRuntimePerformanceDefaults(
        arguments: inout [String],
        options: LaunchOptions,
        effectiveMemoryMB: UInt64,
        effectiveMinMemoryMB: UInt64
    ) {
        let lowered = arguments.map { $0.lowercased() }
        let usingOpenJ9 = isOpenJ9Runtime(options: options)
        let releaseType = options.javaReleaseType ?? options.javaRuntime.releaseType

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
                    "-XX:MaxGCPauseMillis=30"
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
            let hasReservedCodeCache = lowered.contains { $0.hasPrefix("-xx:reservedcodecachesize=") }
            if !hasReservedCodeCache {
                let reservedCodeCache = releaseType == .stableLTS ? "256M" : "192M"
                arguments.insert("-XX:ReservedCodeCacheSize=\(reservedCodeCache)", at: 0)
            }
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

    private static func isOpenJ9Runtime(options: LaunchOptions) -> Bool {
        if let implementor = options.javaRuntime.implementor?.lowercased() {
            if implementor.contains("ibm") || implementor.contains("semeru") || implementor.contains("openj9") {
                return true
            }
        }
        return options.javaRuntime.executableURL.path == "/usr/bin/java"
    }

    private static func sanitizeUnresolvedPlaceholders(_ argument: String) -> String {
        var value = argument
        while let start = value.range(of: "${"), let end = value[start.upperBound...].firstIndex(of: "}") {
            value.removeSubrange(start.lowerBound...end)
        }
        return value
    }

    private static func removeEmptyOptionalArguments(_ arguments: [String]) -> [String] {
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

    private static func sanitizeJVMArguments(_ arguments: [String], options: LaunchOptions) -> [String] {
        let releaseType = options.javaReleaseType ?? options.javaRuntime.releaseType
        let isHighRiskArm64 = options.javaRuntime.majorVersion >= 25 && options.javaRuntime.architecture == .arm64
        let blockedExact = Set([
            "-XX:+ParallelRefProcEnabled",
            "-XX:+AlwaysPreTouch"
        ] + (isHighRiskArm64 ? ["-XX:+UseCompactObjectHeaders"] : []))
        let blockedPrefixes = [
            "-xx:initialcodecachesize=",
            "-xx:codecacheexpansionsize=",
            "-xx:reservedcodecachesize=",
            "-xx:nonprofiledcodeheapsize=",
            "-xx:profiledcodeheapsize=",
            "-xx:nonnmethodcodeheapsize="
        ]

        let filtered = arguments.filter { argument in
            let lowered = argument.lowercased()
            if blockedExact.contains(argument) { return false }
            if blockedPrefixes.contains(where: { lowered.hasPrefix($0) }) { return false }
            if releaseType == .earlyAccess && lowered == "-xx:+parallelrefprocenabled" { return false }
            return true
        }

        return filtered
    }

    private func sanitizedLaunchEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        guard options.javaRuntime.majorVersion >= 25 && options.javaRuntime.architecture == .arm64 else {
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
