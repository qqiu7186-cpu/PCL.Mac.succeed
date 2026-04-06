//
//  MinecraftLaunchManager.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/2/6.
//

import Foundation
import Core
import Combine
import ZIPFoundation
import AppKit

class MinecraftLaunchManager: ObservableObject {
    public static let shared: MinecraftLaunchManager = .init()
    
    @Published public var isLaunching: Bool = false
    @Published public var progress: Double = 0
    @Published public var currentStage: String? = nil
    @Published public var instanceName: String?
    @Published private var gameProcess: Process?
    public var isRunning: Bool { gameProcess != nil }
    public let loadingModel: MyLoadingViewModel = .init(text: "正在启动游戏")
    
    private var task: MyTask<MinecraftLaunchTask.Model>? {
        didSet {
            isLaunching = task != nil
            subscribeToTask()
        }
    }
    private var cancellables: [AnyCancellable] = []
    private let terminationStateQueue: DispatchQueue = .init(label: "PCL.Mac.Launch.TerminationState")
    private var handledTerminations: Set<ObjectIdentifier> = []
    
    /// 开始启动游戏。
    /// - Parameters:
    ///   - instance: 目标游戏实例。
    ///   - account: 使用的账号。
    ///   - repository: 实例所在的游戏仓库。
    /// - Returns: 一个布尔值，表示是否成功添加任务。
    @MainActor
    public func launch(
        _ instance: MinecraftInstance,
        using account: Account,
        in repository: MinecraftRepository
    ) -> Bool {
        if isLaunching { return false }
        self.loadingModel.text = "正在启动游戏"
        let task: MyTask<MinecraftLaunchTask.Model> = MinecraftLaunchTask.create(for: instance, using: account, in: repository) { launcher, process in
            self.gameProcess = process
            process.terminationHandler = { [weak self] process in
                self?.handleProcessTermination(process, instance: instance, options: launcher.options, logURL: launcher.logURL)
            }
            if !process.isRunning {
                self.handleProcessTermination(process, instance: instance, options: launcher.options, logURL: launcher.logURL)
            }
            self.loadingModel.text = "已启动游戏"
        }
        TaskManager.shared.execute(task: task, display: false) { _ in
            self.task = nil
            self.currentStage = nil
            self.instanceName = nil
            self.progress = 0
        }
        self.instanceName = instance.name
        self.task = task
        return true
    }
    
    /// 取消当前启动任务。
    public func cancel() {
        if let task {
            TaskManager.shared.cancel(task.id)
        }
    }
    
    public func stop() {
        if let gameProcess {
            gameProcess.terminate()
            self.gameProcess = nil
        }
    }
    
    private func onGameCrash(instance: MinecraftInstance, options: LaunchOptions, logURL: URL) {
        let analysis = analyzeClientCrash(instance: instance, logURL: logURL)
        hint("检测到 Minecraft 发生崩溃，崩溃分析已开始……", type: .critical)
        MessageBoxManager.shared.showText(
            title: "Minecraft 发生崩溃",
            content: "你的游戏发生了一些问题，无法继续运行。\n\n\(analysis.dialogText)\n\n若要寻求帮助，请点击“导出崩溃报告”并将导出的文件发给他人，而不是发送关于此页面的图片！！！",
            level: .error,
            .no(label: "返回"),
            .yes(label: "导出崩溃报告")
        ) { result in
            if result == 1 {
                let dateFormatter: DateFormatter = .init()
                dateFormatter.dateFormat = "yyyy_MM_dd_HH_mm_SS"
                let fileName: String = "崩溃报告-\(dateFormatter.string(from: .now)).zip"
                let panel = NSSavePanel()
                panel.title = "选择报告位置"
                panel.allowedContentTypes = [.zip]
                panel.canCreateDirectories = true
                panel.nameFieldStringValue = fileName
                panel.beginSheetModal(for: NSApplication.shared.windows.first!) { result in
                    guard let url: URL = panel.url else { return }
                    do {
                        try self.exportCrashReport(for: instance, to: url, with: fileName, options: options, logURL: logURL, analysis: analysis)
                        log("导出崩溃报告成功")
                    } catch {
                        err("导出崩溃报告失败：\(error.localizedDescription)")
                        hint("导出崩溃报告失败：\(error.localizedDescription)", type: .critical)
                    }
                }
            }
        }
    }

    private func handleProcessTermination(_ process: Process, instance: MinecraftInstance, options: LaunchOptions, logURL: URL) {
        guard markTerminationHandled(process) else { return }

        log("游戏进程已退出，退出代码：\(process.terminationStatus)")
        if ![0, 9, 15, 128 + 9, 128 + 15].contains(process.terminationStatus) {
            log("游戏非正常退出")
            DispatchQueue.main.async {
                self.onGameCrash(instance: instance, options: options, logURL: logURL)
            }
        } else {
            try? FileManager.default.removeItem(at: logURL)
        }

        DispatchQueue.main.async {
            self.cancel()
            self.gameProcess = nil
        }
    }

    private func markTerminationHandled(_ process: Process) -> Bool {
        terminationStateQueue.sync {
            let key = ObjectIdentifier(process)
            if handledTerminations.contains(key) {
                return false
            }
            handledTerminations.insert(key)
            return true
        }
    }
    
    private func exportCrashReport(for instance: MinecraftInstance, to destination: URL, with fileName: String, options: LaunchOptions, logURL: URL, analysis: ClientCrashAnalysis) throws {
        let reportURL: URL = URLConstants.tempURL.appending(path: fileName)
        try FileManager.default.createDirectory(at: reportURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: reportURL) }
        
        let launcherInfo: LauncherInfo = .init(
            launcher: "PCL.Mac.Refactor",
            launcherVersion: Metadata.appVersion,
            minecraftVersion: instance.version.id,
            javaVersion: options.javaRuntime.version,
            javaArchitecture: options.javaRuntime.architecture.rawValue,
            javaVendor: options.javaRuntime.vendorName,
            javaReleaseType: options.javaReleaseType ?? options.javaRuntime.releaseType,
            javaFallbackPolicy: options.javaFallbackPolicy,
            finalJvmArguments: MinecraftLauncher.buildLaunchArguments(
                manifest: options.manifest,
                values: buildLauncherInfoValues(instance: instance, options: options),
                options: options
            ),
            instanceName: instance.name
        )
        
        try JSONEncoder.shared.encode(launcherInfo).write(to: reportURL.appending(path: "launcher-info.json"))
        try analysis.exportText.write(to: reportURL.appending(path: "crash-analysis.txt"), atomically: true, encoding: .utf8)
        
        if FileManager.default.fileExists(atPath: logURL.path) {
            try FileManager.default.moveItem(at: logURL, to: reportURL.appending(path: "game-log.log"))
        }
        
        let crashReportDirectory: URL = instance.runningDirectory.appending(path: "crash-reports")
        if FileManager.default.fileExists(atPath: crashReportDirectory.path) {
            let crashReports: [URL] = try FileManager.default.contentsOfDirectory(at: crashReportDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
            if let latestCrashReport: URL = crashReports
                .filter({ (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false })
                .max(by: { lhs, rhs in
                    let lDate: Date? = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    let rDate: Date? = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    return (lDate ?? .distantPast) < (rDate ?? .distantPast)
                }) {
                try FileManager.default.copyItem(at: latestCrashReport, to: reportURL.appending(path: "crash-report.txt"))
            }
        }
        try FileManager.default.zipItem(at: reportURL, to: destination, shouldKeepParent: false)
    }

    private func analyzeClientCrash(instance: MinecraftInstance, logURL: URL) -> ClientCrashAnalysis {
        let context = buildCrashContext(instance: instance, logURL: logURL)
        guard !context.isEmpty else {
            return .init(matches: [], generatedAt: .now)
        }

        let normalized = context.lowercased()
        let rules: [ClientCrashRule] = [
            .init(
                title: "Java 版本或运行时不匹配",
                keywords: [
                    "unsupportedclassversionerror",
                    "unsupported class file major version",
                    "open j9 is not supported",
                    "openj9 is incompatible"
                ],
                suggestion: "切换到启动器自动选择 Java；1.17+ 使用 Java 17+，低版本 Mod 组合优先 Java 8u312/11。"
            ),
            .init(
                title: "内存不足 / 堆空间不足",
                keywords: [
                    "outofmemoryerror",
                    "could not reserve enough space",
                    "java heap space",
                    "gc overhead limit exceeded"
                ],
                suggestion: "降低后台占用并调整内存；优先使用自动内存配置，避免手动给过高或过低值。"
            ),
            .init(
                title: "显卡驱动 / OpenGL 环境异常",
                keywords: [
                    "opengl",
                    "pixel format not accelerated",
                    "the driver does not appear to support opengl",
                    "glfw error",
                    "couldn't set pixel format"
                ],
                suggestion: "更新显卡驱动并检查光影/材质/渲染类 Mod 兼容性；macOS 建议优先关闭高风险渲染 Mod 后复现。"
            ),
            .init(
                title: "Mod 缺失前置或依赖冲突",
                keywords: [
                    "missing or unsupported mandatory dependencies",
                    "which is missing!",
                    "mod resolution encountered an incompatible mod set",
                    "duplicate mod",
                    "duplicatemodsfoundexception"
                ],
                suggestion: "按日志提示补齐前置或移除冲突 Mod；同名/重复 Mod 仅保留一个。"
            ),
            .init(
                title: "Mixin / 注入阶段崩溃",
                keywords: [
                    "org.spongepowered.asm.mixin",
                    "mixin apply failed",
                    "mixintransformererror",
                    "serviceinitialisationexception"
                ],
                suggestion: "这是高频客户端崩溃来源。优先二分排查最近新增 Mod，重点检查核心库/优化类 Mod。"
            ),
            .init(
                title: "Mod 文件损坏或解压错误",
                keywords: [
                    "zip end header not found",
                    "extracted mod jars found",
                    "the directories below appear to be extracted jar files"
                ],
                suggestion: "删除损坏或解压后的 Mod，重新下载原始 .jar 文件。"
            ),
            .init(
                title: "会话/网络认证问题",
                keywords: [
                    "invalid session",
                    "failed to verify username",
                    "sslhandshakeexception",
                    "unknownhostexception"
                ],
                suggestion: "刷新账号令牌后重试；检查网络可用性与系统时间是否准确。"
            )
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

    private func buildCrashContext(instance: MinecraftInstance, logURL: URL) -> String {
        var chunks: [String] = []

        if let gameLog = readTextFile(at: logURL, maxBytes: 600_000) {
            chunks.append(gameLog)
        }

        let crashReportDirectory = instance.runningDirectory.appending(path: "crash-reports")
        if
            FileManager.default.fileExists(atPath: crashReportDirectory.path),
            let crashReports = try? FileManager.default.contentsOfDirectory(at: crashReportDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
        {
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
    
    private func subscribeToTask() {
        cancellables.removeAll()
        guard let task else { return }
        task.$currentTaskOrdinal
            .map { [weak self] ordinal in
                guard let ordinal else {
                    return nil
                }
                return self?.stageString(for: ordinal)
            }
            .receive(on: DispatchQueue.main)
            .assign(to: \.currentStage, on: self)
            .store(in: &cancellables)
        
        task.$progress
            .receive(on: DispatchQueue.main)
            .assign(to: \.progress, on: self)
            .store(in: &cancellables)
    }
    
    private func stageString(for ordinal: Int) -> String {
        switch ordinal {
        case 0: "检查 Java"
        case 1: "刷新账号"
        case 2: "预检查"
        case 3: "检查资源完整性"
        case 4: "启动游戏"
        case 5: "等待游戏窗口出现"
        default: "\(ordinal)"
        }
    }
    
    private init() {}
    
    private struct LauncherInfo: Codable {
        public let launcher: String
        public let launcherVersion: String
        public let minecraftVersion: String
        public let javaVersion: String
        public let javaArchitecture: String
        public let javaVendor: String
        public let javaReleaseType: JavaRuntime.JavaReleaseType
        public let javaFallbackPolicy: LaunchOptions.JavaFallbackPolicy
        public let finalJvmArguments: [String]
        public let instanceName: String
    }

    private struct ClientCrashRule {
        let title: String
        let keywords: [String]
        let suggestion: String
    }

    private struct ClientCrashMatch {
        let title: String
        let score: Int
        let suggestion: String
    }

    private struct ClientCrashAnalysis {
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
}
