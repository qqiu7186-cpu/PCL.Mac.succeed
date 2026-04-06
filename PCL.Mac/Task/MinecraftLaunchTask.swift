//
//  MinecraftLaunchTask.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/2/5.
//

import Foundation
import Core
import AppKit

/// Minecraft 启动任务生成器。
public enum MinecraftLaunchTask {
    private typealias SubTask = MyTask<Model>.SubTask
    private static let skipJavaRuntimePrecheck = true
    private static let skipLaunchPrecheck = true
    
    /// 创建 Minecraft 启动任务。
    /// - Parameters:
    ///   - instance: 启动的 Minecraft 实例。
    ///   - account: 启动时使用的账号。
    ///   - repository: 实例所在的游戏仓库。
    public static func create(
        for instance: MinecraftInstance,
        using account: Account,
        in repository: MinecraftRepository,
        onProcessStarted: @escaping (MinecraftLauncher, Process) -> Void
    ) -> MyTask<Model> {
        return .init(
            name: "启动游戏 - \(instance.name)",
            model: .init(instance: instance, account: account, repository: repository, onProcessStarted: onProcessStarted),
            .init(0, "检查 Java", checkJava(task:model:)),
            .init(1, "刷新账号", refreshAccount(task:model:)),
            .init(2, "预检查", precheck(task:model:)),
            .init(3, "检查资源完整性", checkResources(task:model:)),
            .init(4, "启动游戏", launch(task:model:)),
            .init(5, "等待游戏窗口出现", display: false, waitForWindow(task:model:))
        )
    }
    
    private static func checkJava(task: SubTask, model: Model) async throws {
        var runtime: JavaRuntime?
        let minVersion: Int = model.instance.manifest.requiredJavaMajorVersion(for: model.instance.version)
        
        if let resolvedRuntime: JavaRuntime = model.instance.resolveJavaForLaunch() {
            runtime = resolvedRuntime
        } else if model.instance.config.autoSelectJava {
            runtime = await JavaRuntimeSelectionService.autoInstallJavaIfNeeded(minVersion: minVersion, instance: model.instance)
            if runtime == nil {
                await MinecraftLaunchPreparationService.showNoUsableJavaPrompt(minVersion: minVersion, diagnostics: MinecraftLaunchPreparationService.noUsableJavaDiagnostics(for: model.instance, minVersion: minVersion))
                try task.cancel()
            }
        } else if let javaRuntime: JavaRuntime = JavaRuntimeSelectionService.bestHealthyRuntime(for: model.instance, minVersion: minVersion) {
            if await MessageBoxManager.shared.showTextAsync(
                title: "当前 Java 不可用",
                content: "手动模式下未设置可用 Java。\nPCL.Mac 找到了一个可用的 Java：\(javaRuntime.version)，是否切换并继续启动？",
                level: .info,
                .no(),
                .yes(label: "切换", type: .highlight)
            ) == 1 {
                model.instance.setJava(url: javaRuntime.executableURL)
                runtime = javaRuntime
            } else {
                try task.cancel()
            }
        } else if let autoInstalled = await JavaRuntimeSelectionService.autoInstallJavaIfNeeded(minVersion: minVersion, instance: model.instance) {
            runtime = autoInstalled
        } else {
            await MinecraftLaunchPreparationService.showNoUsableJavaPrompt(minVersion: minVersion, diagnostics: MinecraftLaunchPreparationService.noUsableJavaDiagnostics(for: model.instance, minVersion: minVersion))
            try task.cancel()
        }

        if let selectedRuntime = runtime {
            let health = JavaRuntimeSelectionService.checkRuntimeHealth(selectedRuntime)
            if !health.isHealthy {
                JavaRuntimeSelectionService.markRuntimeUnhealthy(selectedRuntime)
                warn("Java 预检失败：\(selectedRuntime.executableURL.path) - \(health.reason)")
                if let fallback = JavaRuntimeSelectionService.bestHealthyRuntime(for: model.instance, minVersion: minVersion, excluding: [JavaRuntimeSelectionService.normalizedRuntimePath(selectedRuntime)]) {
                    runtime = fallback
                    model.instance.setJava(url: fallback.executableURL)
                    hint("检测到当前 Java 运行时异常，已自动切换到 \(fallback.version)。", type: .critical)
                } else if let autoInstalled = await JavaRuntimeSelectionService.autoInstallJavaIfNeeded(minVersion: minVersion, instance: model.instance, excluding: [JavaRuntimeSelectionService.normalizedRuntimePath(selectedRuntime)]) {
                    runtime = autoInstalled
                    model.instance.setJava(url: autoInstalled.executableURL)
                    hint("检测到当前 Java 运行时异常，已自动下载并切换到 \(autoInstalled.version)。", type: .critical)
                } else {
                    _ = await MessageBoxManager.shared.showTextAsync(
                        title: "Java 运行时异常",
                        content: "当前 Java 在启动前自检中失败（\(health.reason)），且未找到可用替代运行时。\n请在设置中更换 Java 后重试。",
                        level: .error
                    )
                    try task.cancel()
                }
            }
        }

        if let runtime {
            model.options.javaRuntime = runtime
            model.options.javaReleaseType = runtime.releaseType
            model.manifest = NativesMapper.map(model.manifest, to: runtime.architecture)
        }
    }

    private static func showNoUsableJavaPrompt(minVersion: Int, diagnostics: String? = nil) async {
        var content = "这个实例需要 Java \(minVersion) 才能启动，但你的电脑上没有安装可用版本，且自动下载失败。\n"
        if let diagnostics, !diagnostics.isEmpty {
            content += "\n\(diagnostics)\n"
        }
        content += "\n点击下方按钮可以跳转到安装页面！"

        if await MessageBoxManager.shared.showTextAsync(
            title: "没有可用的 Java",
            content: content,
            level: .error,
            .no(),
            .yes(label: "去安装")
        ) == 1 {
            await AppRouter.shared.setRoot(.settings)
            await AppRouter.shared.append(.javaSettings)
        }
    }

    private static func noUsableJavaDiagnostics(for instance: MinecraftInstance, minVersion: Int) -> String? {
        let allRuntimes: [JavaRuntime]
        do {
            allRuntimes = try JavaManager.shared.allJavaRuntimes()
        } catch {
            err("读取 Java 运行时列表失败：\(error.localizedDescription)")
            return nil
        }

        let candidates = allRuntimes
            .filter { $0.majorVersion >= minVersion }
            .sorted { lhs, rhs in
                if lhs.majorVersion != rhs.majorVersion { return lhs.majorVersion > rhs.majorVersion }
                return lhs.version.compare(rhs.version, options: .numeric) == .orderedDescending
            }

        guard !candidates.isEmpty else { return nil }

        let lines: [String] = candidates.prefix(3).map { runtime in
            let path = runtime.executableURL.path
            if JavaManager.shared.isBrokenRuntime(runtime) {
                return "• Java \(runtime.version)（\(path)）已标记为不可用（此前预检失败）"
            }

            let health = JavaRuntimeSelectionService.checkRuntimeHealth(runtime)
            if health.isHealthy {
                return "• Java \(runtime.version)（\(path)）可用"
            }
            return "• Java \(runtime.version)（\(path)）预检失败：\(health.reason)"
        }

        return "已检测到 Java，但运行时不可用：\n\(lines.joined(separator: "\n"))"
    }
    
    private static func refreshAccount(task: SubTask, model: Model) async throws {
        if model.account.shouldRefresh() {
            do {
                try await model.account.refresh()
                log("刷新 accessToken 成功")
            } catch is CancellationError {
            } catch {
                err("刷新 accessToken 失败")
                if await MessageBoxManager.shared.showTextAsync(
                    title: "刷新访问令牌失败",
                    content: "在刷新访问令牌时发生错误：\(error.localizedDescription)\n\n如果继续启动，可能会导致无法加入部分需要正版验证的服务器！\n是否继续启动？\n\n若要寻求帮助，请将完整日志发送给他人，而不是发送此页面相关的图片。",
                    level: .error,
                    .no(),
                    .yes(label: "继续", type: .red)
                ) == 0 {
                    try task.cancel()
                }
            }
        }
        model.options.accessToken = model.account.accessToken()
        try await model.account.configureLaunchOptions(&model.options)
    }
    
    private static func precheck(task: SubTask, model: Model) async throws {
        do {
            try await MinecraftLaunchPreparationService.precheck(model: model, skipLaunchPrecheck: skipLaunchPrecheck)
        } catch is CancellationError {
            try task.cancel()
        }
    }
    
    private static func checkResources(task: SubTask, model: Model) async throws {
        try await MinecraftLaunchPreparationService.checkResources(model: model, progressHandler: task.setProgress(_:))
    }
    
    private static func launch(task: SubTask, model: Model) async throws {
        LauncherConfig.shared.launchCount += 1
        let launcher: MinecraftLauncher = .init(options: model.options)
        model.launcher = launcher
        do {
            let process: Process = try launcher.launch()
            model.process = process
            await MainActor.run {
                model.onProcessStarted(launcher, process)
            }
        } catch is CancellationError {
        } catch {
            err("启动游戏失败：\(error.localizedDescription)")
            _ = await MessageBoxManager.shared.showTextAsync(
                title: "启动游戏失败",
                content: "启动游戏时发生错误：\(error.localizedDescription)",
                level: .error
            )
        }
    }
    
    private static func waitForWindow(task: SubTask, model: Model) async throws {
        guard let process = model.process else {
            err("model.process 为 nil")
            return
        }
        try await withTaskCancellationHandler {
            while true {
                try Task.checkCancellation()
                if !process.isRunning {
                    log("进程已被关闭，停止检测窗口")
                    break
                }
                if checkWindows(for: process) {
                    break
                }
                try await Task.sleep(seconds: 1)
            }
        } onCancel: {
            process.terminate()
        }
    }
    
    private static func checkWindows(for process: Process) -> Bool {
        let option: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(option, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        for info in infoList {
            if let windowPID: Int = info[kCGWindowOwnerPID as String] as? Int,
               windowPID == process.processIdentifier {
                return true
            }
        }
        return false
    }

    private static func bestHealthyRuntime(for instance: MinecraftInstance, minVersion: Int, excluding: Set<String> = []) -> JavaRuntime? {
        let normalizedExcluding: Set<String> = Set(excluding.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path })
        let javaRange = instance.manifest.supportedJavaMajorRange(
            for: instance.version,
            modLoader: instance.modLoader,
            modLoaderVersion: instance.modLoaderVersion
        )

        func score(of runtime: JavaRuntime) -> Int {
            var score = 0
            if instance.shouldAvoidRuntimeForLaunch(runtime) { score -= 100 }
            if runtime.architecture == instance.preferredArchitectureForLaunch() { score += 3 }
            if runtime.majorVersion == minVersion { score += 2 }
            if runtime.type == .jdk { score += 1 }
            if runtime.implementor?.contains("Azul") == true { score += 1 }
            return score
        }

        let allRuntimes: [JavaRuntime]
        do {
            allRuntimes = try JavaManager.shared.allJavaRuntimes()
        } catch {
            err("读取 Java 运行时列表失败：\(error.localizedDescription)")
            allRuntimes = JavaManager.shared.javaRuntimes
        }

        let matchingRuntimes = allRuntimes
            .filter { $0.majorVersion >= minVersion }
            .filter { javaRange.contains($0.majorVersion) }
            .filter { !instance.shouldAvoidRuntimeForLaunch($0) }
            .filter { !normalizedExcluding.contains(normalizedRuntimePath($0)) }

        let candidates = matchingRuntimes
            .filter { !isRuntimeMarkedUnhealthy($0) }
            .sorted { score(of: $0) > score(of: $1) }

        for runtime in candidates {
            let health = checkRuntimeHealth(runtime)
            if health.isHealthy { return runtime }
            markRuntimeUnhealthy(runtime)
            warn("Java 预检失败：\(runtime.executableURL.path) - \(health.reason)")
        }

        let markedCandidates = matchingRuntimes
            .filter { isRuntimeMarkedUnhealthy($0) }
            .sorted { score(of: $0) > score(of: $1) }

        for runtime in markedCandidates {
            let health = checkRuntimeHealth(runtime)
            if health.isHealthy {
                JavaManager.shared.clearBrokenRuntime(runtime)
                log("已恢复此前标记不可用的 Java：\(runtime.executableURL.path)")
                return runtime
            }
        }
        return nil
    }

    private static func autoInstallJavaIfNeeded(minVersion: Int, instance: MinecraftInstance, excluding: Set<String> = []) async -> JavaRuntime? {
        let javaRange = instance.manifest.supportedJavaMajorRange(
            for: instance.version,
            modLoader: instance.modLoader,
            modLoaderVersion: instance.modLoaderVersion
        )
        let downloads = await preferredJavaDownloads(minVersion: minVersion, maxVersion: javaRange.upperBound)
        guard !downloads.isEmpty else {
            return nil
        }

        for download in downloads {
            do {
                log("未找到可用 Java，开始自动安装 \(download.displaySourceName) \(download.version)")
                try await JavaInstallTask.create(download: download, replaceExisting: true).start()
            } catch {
                err("自动安装 Java 失败（\(download.displaySourceName) \(download.version)）：\(error.localizedDescription)")
                continue
            }

            if let runtime = bestHealthyRuntime(for: instance, minVersion: minVersion, excluding: excluding) {
                return runtime
            }

            warn("自动安装的 Java 预检失败，继续尝试其他可用下载源：\(download.displaySourceName) \(download.version)")
        }

        return nil
    }

    private static func preferredJavaDownloads(minVersion: Int, maxVersion: Int) async -> [JavaDownloadPackage] {
        do {
            let viewModel = JavaSettingsViewModel()
        let architectures = preferredDownloadArchitectures(for: minVersion)
            var downloads: [JavaDownloadPackage] = []
            for architecture in architectures {
                downloads += try await viewModel.javaDownloads(forArchitecture: architecture, preferredMajor: minVersion, includeAllProviders: true)
            }

            let rangedDownloads = downloads.filter { $0.majorVersion >= minVersion && $0.majorVersion <= maxVersion }
            guard !rangedDownloads.isEmpty else {
                return []
            }

            return rangedDownloads.sorted { lhs, rhs in
                let lhsArchitecturePriority = architecturePriority(lhs.architecture, minVersion: minVersion)
                let rhsArchitecturePriority = architecturePriority(rhs.architecture, minVersion: minVersion)
                if lhsArchitecturePriority != rhsArchitecturePriority {
                    return lhsArchitecturePriority < rhsArchitecturePriority
                }

                if lhs.majorVersion != rhs.majorVersion {
                    let lhsDistance = abs(lhs.majorVersion - minVersion)
                    let rhsDistance = abs(rhs.majorVersion - minVersion)
                    if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
                    return lhs.majorVersion < rhs.majorVersion
                }

                let lhsPre = isPrereleaseJavaVersion(lhs.version)
                let rhsPre = isPrereleaseJavaVersion(rhs.version)
                if lhsPre != rhsPre { return rhsPre }

                if lhs.provider != rhs.provider {
                    return lhs.provider == .azulZulu
                }

                return lhs.version.compare(rhs.version, options: .numeric) == .orderedDescending
            }
        } catch {
            err("拉取 Java 下载列表失败：\(error.localizedDescription)")
            return []
        }
    }

    private static func preferredDownloadArchitectures(for minVersion: Int) -> [Architecture] {
        let systemArchitecture = Architecture.systemArchitecture()
        guard systemArchitecture == .arm64, minVersion >= 26, supportsX64JavaFallback() else {
            return [systemArchitecture]
        }
        return [.x64, .arm64]
    }

    private static func architecturePriority(_ architecture: Architecture, minVersion: Int) -> Int {
        if Architecture.systemArchitecture() == .arm64 && minVersion >= 26 {
            switch architecture {
            case .x64:
                return 0
            case .arm64:
                return 1
            default:
                return 2
            }
        }

        switch architecture {
        case .arm64:
            return 0
        case .x64:
            return 1
        default:
            return 2
        }
    }

    private static func supportsX64JavaFallback() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        process.arguments = ["-x86_64", "/usr/bin/true"]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func isPrereleaseJavaVersion(_ version: String) -> Bool {
        let lowered = version.lowercased()
        return lowered.contains("ea") || lowered.contains("beta") || lowered.contains("preview") || lowered.contains("rc")
    }

    private static func javaMajorVersion(of version: String) -> Int {
        let parts = version.split(separator: ".")
        guard let first = parts.first else { return 0 }
        if first == "1", parts.count > 1 {
            return leadingNumber(in: String(parts[1])) ?? 0
        }
        return leadingNumber(in: String(first)) ?? 0
    }

    private static func leadingNumber(in value: String) -> Int? {
        let digits = value.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    private static func checkRuntimeHealth(_ runtime: JavaRuntime) -> RuntimeHealth {
        if skipJavaRuntimePrecheck {
            return .init(isHealthy: true, reason: "已临时跳过 Java 预检")
        }

        var baseProbe = runJavaProbe(runtime, arguments: ["-version"])
        if !baseProbe.isHealthy, baseProbe.reason == "收到信号退出" {
            if attemptRuntimeSignalRecovery(runtime) {
                let recoveredProbe = runJavaProbe(runtime, arguments: ["-version"])
                if recoveredProbe.isHealthy {
                    warn("Java 预检信号退出，尝试修复运行时后恢复成功：\(runtime.executableURL.path)")
                    baseProbe = recoveredProbe
                } else {
                    baseProbe = recoveredProbe
                }
            }
        }
        guard baseProbe.isHealthy else {
            return .init(isHealthy: false, reason: baseProbe.reason)
        }

        let extendedArguments = probeArguments(for: runtime)
        guard extendedArguments != ["-version"] else {
            return .init(isHealthy: true, reason: "OK")
        }

        let extendedProbe = runJavaProbe(runtime, arguments: extendedArguments)
        if extendedProbe.isHealthy {
            return .init(isHealthy: true, reason: "OK")
        }

        if isJvmOptionCompatibilityIssue(extendedProbe.output) {
            warn("Java 高级参数预检失败，降级为基础预检：\(extendedProbe.reason)")
            return .init(isHealthy: true, reason: "基础预检通过")
        }

        return .init(isHealthy: false, reason: extendedProbe.reason)
    }

    private static func runJavaProbe(_ runtime: JavaRuntime, arguments: [String]) -> RuntimeHealth {
        let process: Process = .init()
        process.executableURL = runtime.executableURL
        process.arguments = arguments

        let pipe: Pipe = .init()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return .init(isHealthy: false, reason: "无法执行：\(error.localizedDescription)", output: "")
        }

        let start = Date()
        while process.isRunning {
            if Date().timeIntervalSince(start) > 8 {
                process.terminate()
                return .init(isHealthy: false, reason: "预检超时", output: "")
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outputData, as: UTF8.self)
        let lowered = output.lowercased()

        if process.terminationReason == .uncaughtSignal {
            return .init(isHealthy: false, reason: "收到信号退出", output: lowered)
        }
        if lowered.contains("fatal error has been detected by the java runtime environment") {
            return .init(isHealthy: false, reason: "JVM 自身致命错误", output: lowered)
        }
        if process.terminationStatus != 0 {
            return .init(isHealthy: false, reason: "退出码 \(process.terminationStatus)", output: lowered)
        }

        return .init(isHealthy: true, reason: "OK", output: lowered)
    }

    private static func probeArguments(for runtime: JavaRuntime) -> [String] {
        var arguments: [String] = [
            "-Xms256M",
            "-Xmx512M"
        ]

        if isOpenJ9(runtime) {
            arguments.append(contentsOf: [
                "-Xgcpolicy:gencon",
                "-Xsoftmx768M"
            ])
        } else {
            arguments.append(contentsOf: [
                "-XX:+UseG1GC",
                "-XX:MaxGCPauseMillis=20",
                "-XX:+ParallelRefProcEnabled",
                "-XX:MinHeapFreeRatio=10",
                "-XX:MaxHeapFreeRatio=30"
            ])
            if runtime.majorVersion >= 12 {
                arguments.append(contentsOf: [
                    "-XX:G1PeriodicGCInterval=30000",
                    "-XX:+G1PeriodicGCInvokesConcurrent"
                ])
            }
        }

        arguments.append("-version")
        return arguments
    }

    private static func isRuntimeMarkedUnhealthy(_ runtime: JavaRuntime) -> Bool {
        JavaManager.shared.isBrokenRuntime(runtime)
    }

    private static func markRuntimeUnhealthy(_ runtime: JavaRuntime) {
        JavaManager.shared.markRuntimeAsBroken(runtime)
    }

    private static func normalizedRuntimePath(_ runtime: JavaRuntime) -> String {
        runtime.executableURL.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func isOpenJ9(_ runtime: JavaRuntime) -> Bool {
        if let implementor = runtime.implementor?.lowercased() {
            if implementor.contains("ibm") || implementor.contains("semeru") || implementor.contains("openj9") {
                return true
            }
        }
        return runtime.executableURL.path == "/usr/bin/java"
    }

    private static func attemptRuntimeSignalRecovery(_ runtime: JavaRuntime) -> Bool {
        var repaired = false

        let executablePath = runtime.executableURL.path
        if runTool("/bin/chmod", arguments: ["u+x", executablePath]) {
            repaired = true
        }

        if let bundleRoot = javaBundleRoot(for: runtime.executableURL) {
            if runTool("/usr/bin/xattr", arguments: ["-dr", "com.apple.quarantine", bundleRoot.path]) {
                repaired = true
            }
        }

        return repaired
    }

    private static func javaBundleRoot(for executableURL: URL) -> URL? {
        let executablePath = executableURL.resolvingSymlinksInPath().standardizedFileURL.path
        guard executablePath.contains("/Contents/Home/bin/java") else {
            return nil
        }

        let root = executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        guard rootPath != "/" else {
            return nil
        }
        let lowercased = rootPath.lowercased()
        guard lowercased.hasSuffix(".jdk") || lowercased.hasSuffix(".jre") || lowercased.hasSuffix(".bundle") else {
            return nil
        }
        return root
    }

    @discardableResult
    private static func runTool(_ executablePath: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            warn("执行工具失败：\(executablePath) \(arguments.joined(separator: " "))，\(error.localizedDescription)")
            return false
        }

        if process.terminationStatus == 0 {
            return true
        }

        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !output.isEmpty {
            warn("工具执行失败：\(executablePath) \(arguments.joined(separator: " "))，\(output)")
        }
        return false
    }

    private static func isJvmOptionCompatibilityIssue(_ output: String) -> Bool {
        output.contains("unrecognized vm option")
            || output.contains("could not create the java virtual machine")
            || output.contains("a fatal exception has occurred. program will exit")
    }

    private struct RuntimeHealth {
        let isHealthy: Bool
        let reason: String
        let output: String

        init(isHealthy: Bool, reason: String, output: String = "") {
            self.isHealthy = isHealthy
            self.reason = reason
            self.output = output
        }
    }
    
    public class Model: TaskModel {
        public let instance: MinecraftInstance
        public let account: Account
        public let repository: MinecraftRepository
        public let onProcessStarted: (MinecraftLauncher, Process) -> Void
        public var manifest: ClientManifest
        public var launcher: MinecraftLauncher?
        public var options: LaunchOptions
        public var process: Process?
        
        init(instance: MinecraftInstance, account: Account, repository: MinecraftRepository, onProcessStarted: @escaping (MinecraftLauncher, Process) -> Void) {
            self.instance = instance
            self.account = account
            self.repository = repository
            self.onProcessStarted = onProcessStarted
            self.manifest = instance.manifest
            self.options = .init()
            
            self.options.profile = account.profile
            self.options.runningDirectory = instance.runningDirectory
            self.options.repository = repository
            self.options.memory = instance.config.jvmHeapSize
        }
    }
}
