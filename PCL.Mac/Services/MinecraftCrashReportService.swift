import Foundation
import Core
import ZIPFoundation

struct MinecraftCrashReportService {
    struct LauncherInfo: Codable {
        let launcher: String
        let launcherVersion: String
        let minecraftVersion: String
        let javaVersion: String
        let javaArchitecture: String
        let javaVendor: String
        let javaReleaseType: JavaRuntime.JavaReleaseType
        let javaFallbackPolicy: LaunchOptions.JavaFallbackPolicy
        let finalJvmArguments: [String]
        let instanceName: String
    }

    struct ClientCrashRule {
        let title: String
        let keywords: [String]
        let suggestion: String
    }

    struct ClientCrashMatch {
        let title: String
        let score: Int
        let suggestion: String
    }

    struct ClientCrashAnalysis {
        let matches: [ClientCrashMatch]
        let generatedAt: Date

        var dialogText: String {
            guard !matches.isEmpty else {
                return "常见客户端崩溃分类：未命中高频特征。\n你仍可导出崩溃报告给他人进一步排查。"
            }
            let lines = matches.enumerated().map { index, item in
                "\(index + 1). \(item.title)（匹配分：\(item.score)）\n   建议：\(item.suggestion)"
            }
            return "常见客户端崩溃分类（仅高频规则）：\n\(lines.joined(separator: "\n"))"
        }

        var exportText: String {
            let formatter = ISO8601DateFormatter()
            var rows: [String] = [
                "# Client Crash Analysis",
                "generated_at=\(formatter.string(from: generatedAt))",
                "mode=rule-based-frequent-client-errors",
                ""
            ]
            if matches.isEmpty {
                rows.append("no_frequent_category_matched=true")
            } else {
                for (index, item) in matches.enumerated() {
                    rows.append("[\(index + 1)] \(item.title)")
                    rows.append("score=\(item.score)")
                    rows.append("suggestion=\(item.suggestion)")
                    rows.append("")
                }
            }
            return rows.joined(separator: "\n")
        }
    }

    func analyzeClientCrash(instance: MinecraftInstance, logURL: URL) -> ClientCrashAnalysis {
        let context = buildCrashContext(instance: instance, logURL: logURL)
        guard !context.isEmpty else {
            return .init(matches: [], generatedAt: .now)
        }

        let normalized = context.lowercased()
        let rules: [ClientCrashRule] = [
            .init(title: "Java 版本或运行时不匹配", keywords: ["unsupportedclassversionerror", "unsupported class file major version", "open j9 is not supported", "openj9 is incompatible"], suggestion: "切换到启动器自动选择 Java；1.17+ 使用 Java 17+，低版本 Mod 组合优先 Java 8u312/11。"),
            .init(title: "内存不足 / 堆空间不足", keywords: ["outofmemoryerror", "could not reserve enough space", "java heap space", "gc overhead limit exceeded"], suggestion: "降低后台占用并调整内存；优先使用自动内存配置，避免手动给过高或过低值。"),
            .init(title: "显卡驱动 / OpenGL 环境异常", keywords: ["opengl", "pixel format not accelerated", "the driver does not appear to support opengl", "glfw error", "couldn't set pixel format"], suggestion: "更新显卡驱动并检查光影/材质/渲染类 Mod 兼容性；macOS 建议优先关闭高风险渲染 Mod 后复现。"),
            .init(title: "Mod 缺失前置或依赖冲突", keywords: ["missing or unsupported mandatory dependencies", "which is missing!", "mod resolution encountered an incompatible mod set", "duplicate mod", "duplicatemodsfoundexception"], suggestion: "按日志提示补齐前置或移除冲突 Mod；同名/重复 Mod 仅保留一个。"),
            .init(title: "Mixin / 注入阶段崩溃", keywords: ["org.spongepowered.asm.mixin", "mixin apply failed", "mixintransformererror", "serviceinitialisationexception"], suggestion: "这是高频客户端崩溃来源。优先二分排查最近新增 Mod，重点检查核心库/优化类 Mod。"),
            .init(title: "Mod 文件损坏或解压错误", keywords: ["zip end header not found", "extracted mod jars found", "the directories below appear to be extracted jar files"], suggestion: "删除损坏或解压后的 Mod，重新下载原始 .jar 文件。"),
            .init(title: "会话/网络认证问题", keywords: ["invalid session", "failed to verify username", "sslhandshakeexception", "unknownhostexception"], suggestion: "刷新账号令牌后重试；检查网络可用性与系统时间是否准确。")
        ]

        let matches = rules.compactMap { rule -> ClientCrashMatch? in
            let score = rule.keywords.reduce(0) { partial, keyword in
                partial + occurrenceCount(of: keyword, in: normalized)
            }
            guard score > 0 else { return nil }
            return .init(title: rule.title, score: score, suggestion: rule.suggestion)
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.title < rhs.title }
            return lhs.score > rhs.score
        }

        return .init(matches: Array(matches.prefix(4)), generatedAt: .now)
    }

    func exportCrashReport(for instance: MinecraftInstance, to destination: URL, with fileName: String, options: LaunchOptions, logURL: URL, analysis: ClientCrashAnalysis) throws {
        let reportURL = URLConstants.tempURL.appending(path: fileName)
        try FileManager.default.createDirectory(at: reportURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: reportURL) }

        let launcherInfo = LauncherInfo(
            launcher: "PCL.Mac.Refactor",
            launcherVersion: Metadata.appVersion,
            minecraftVersion: instance.version.id,
            javaVersion: options.javaRuntime.version,
            javaArchitecture: options.javaRuntime.architecture.rawValue,
            javaVendor: options.javaRuntime.vendorName,
            javaReleaseType: options.javaReleaseType ?? options.javaRuntime.releaseType,
            javaFallbackPolicy: options.javaFallbackPolicy,
            finalJvmArguments: MinecraftLauncher.buildLaunchArguments(manifest: options.manifest, values: buildLauncherInfoValues(instance: instance, options: options), options: options),
            instanceName: instance.name
        )

        try JSONEncoder.shared.encode(launcherInfo).write(to: reportURL.appending(path: "launcher-info.json"))
        try analysis.exportText.write(to: reportURL.appending(path: "crash-analysis.txt"), atomically: true, encoding: .utf8)

        if FileManager.default.fileExists(atPath: logURL.path) {
            try FileManager.default.moveItem(at: logURL, to: reportURL.appending(path: "game-log.log"))
        }

        let crashReportDirectory = instance.runningDirectory.appending(path: "crash-reports")
        if FileManager.default.fileExists(atPath: crashReportDirectory.path) {
            let crashReports = try FileManager.default.contentsOfDirectory(at: crashReportDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
            if let latestCrashReport = crashReports
                .filter({ (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false })
                .max(by: { lhs, rhs in
                    let lDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    let rDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    return (lDate ?? .distantPast) < (rDate ?? .distantPast)
                }) {
                try FileManager.default.copyItem(at: latestCrashReport, to: reportURL.appending(path: "crash-report.txt"))
            }
        }

        try FileManager.default.zipItem(at: reportURL, to: destination, shouldKeepParent: false)
    }

    private func buildCrashContext(instance: MinecraftInstance, logURL: URL) -> String {
        var chunks: [String] = []
        if let gameLog = readTextFile(at: logURL, maxBytes: 600_000) {
            chunks.append(gameLog)
        }

        let crashReportDirectory = instance.runningDirectory.appending(path: "crash-reports")
        if FileManager.default.fileExists(atPath: crashReportDirectory.path),
           let crashReports = try? FileManager.default.contentsOfDirectory(at: crashReportDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) {
            let latest = crashReports
                .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false }
                .max { lhs, rhs in
                    let lDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                    let rDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                    return lDate < rDate
                }
            if let latest, let report = readTextFile(at: latest, maxBytes: 300_000) {
                chunks.append(report)
            }
        }
        return chunks.joined(separator: "\n\n")
    }

    private func readTextFile(at url: URL, maxBytes: Int) -> String? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        let capped = data.prefix(maxBytes)
        return String(decoding: capped, as: UTF8.self)
    }

    private func occurrenceCount(of keyword: String, in text: String) -> Int {
        guard !keyword.isEmpty else { return 0 }
        return text.components(separatedBy: keyword).count - 1
    }

    private func buildLauncherInfoValues(instance: MinecraftInstance, options: LaunchOptions) -> [String: String] {
        let tunedMemory = max(UInt64(1024), min(options.memory, 16_384))
        let minMemory = max(UInt64(512), min(1024, tunedMemory / 4))
        let classpath = buildCrashReportClasspath(options: options, instance: instance)
        return [
            "natives_directory": instance.runningDirectory.appending(path: "natives").path,
            "launcher_name": "PCL.Mac",
            "launcher_version": Metadata.appVersion,
            "classpath_separator": ":",
            "library_directory": options.repository.librariesURL.path,
            "max_memory": "\(tunedMemory)M",
            "min_memory": "\(minMemory)M",
            "maxMemory": "\(tunedMemory)M",
            "minMemory": "\(minMemory)M",
            "auth_player_name": options.profile.name,
            "version_name": instance.runningDirectory.lastPathComponent,
            "game_directory": instance.runningDirectory.path,
            "assets_root": options.repository.assetsURL.path,
            "assets_index_name": options.manifest.assetIndex.id,
            "auth_uuid": UUIDUtils.string(of: options.profile.id, withHyphens: false),
            "auth_access_token": options.accessToken,
            "clientid": "",
            "auth_xuid": "",
            "xuid": "",
            "user_type": options.userType,
            "version_type": "PCL.Mac",
            "user_properties": options.userProperties,
            "classpath": classpath
        ]
    }

    private func buildCrashReportClasspath(options: LaunchOptions, instance: MinecraftInstance) -> String {
        var urls: [URL] = []
        for library in options.manifest.getLibraries() {
            if let artifact = library.artifact {
                urls.append(options.repository.librariesURL.appending(path: artifact.path))
            }
        }
        urls.append(instance.runningDirectory.appending(path: "\(instance.runningDirectory.lastPathComponent).jar"))
        return urls.map(\.path).joined(separator: ":")
    }
}
