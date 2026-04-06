import Foundation
import Core

enum JavaRuntimeSelectionService {
    private static let skipJavaRuntimePrecheck = true

    static func bestHealthyRuntime(for instance: MinecraftInstance, minVersion: Int, excluding: Set<String> = []) -> JavaRuntime? {
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

    static func autoInstallJavaIfNeeded(minVersion: Int, instance: MinecraftInstance, excluding: Set<String> = []) async -> JavaRuntime? {
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

    static func checkRuntimeHealth(_ runtime: JavaRuntime) -> RuntimeHealth {
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

    static func markRuntimeUnhealthy(_ runtime: JavaRuntime) {
        JavaManager.shared.markRuntimeAsBroken(runtime)
    }

    static func normalizedRuntimePath(_ runtime: JavaRuntime) -> String {
        runtime.executableURL.resolvingSymlinksInPath().standardizedFileURL.path
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

    struct RuntimeHealth {
        let isHealthy: Bool
        let reason: String
        let output: String

        init(isHealthy: Bool, reason: String, output: String = "") {
            self.isHealthy = isHealthy
            self.reason = reason
            self.output = output
        }
    }
}
