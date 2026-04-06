import Foundation
import Core
import Combine
import AppKit

final class MinecraftLaunchExecutionCoordinator {
    @Published private(set) var currentStage: String?
    @Published private(set) var progress: Double = 0
    @Published private(set) var instanceName: String?
    @Published private(set) var gameProcess: Process?

    private var cancellables: [AnyCancellable] = []
    private let terminationStateQueue: DispatchQueue = .init(label: "PCL.Mac.Launch.TerminationState")
    private var handledTerminations: Set<ObjectIdentifier> = []
    private let crashReportService = MinecraftCrashReportService()

    var isRunning: Bool { gameProcess != nil }

    func begin(instanceName: String, task: MyTask<MinecraftLaunchTask.Model>) {
        self.instanceName = instanceName
        subscribeToTask(task)
    }

    func reset() {
        cancellables.removeAll()
        currentStage = nil
        progress = 0
        instanceName = nil
    }

    func attachProcess(
        _ process: Process,
        instance: MinecraftInstance,
        options: LaunchOptions,
        logURL: URL,
        onCancellation: @escaping () -> Void,
        onCrash: @escaping () -> Void
    ) {
        gameProcess = process
        process.terminationHandler = { [weak self] process in
            self?.handleProcessTermination(process, instance: instance, options: options, logURL: logURL, onCancellation: onCancellation, onCrash: onCrash)
        }
        if !process.isRunning {
            handleProcessTermination(process, instance: instance, options: options, logURL: logURL, onCancellation: onCancellation, onCrash: onCrash)
        }
    }

    func stopProcess() {
        if let gameProcess {
            gameProcess.terminate()
            self.gameProcess = nil
        }
    }

    private func onGameCrash(instance: MinecraftInstance, options: LaunchOptions, logURL: URL) {
        let analysis = crashReportService.analyzeClientCrash(instance: instance, logURL: logURL)
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
                panel.beginSheetModal(for: NSApplication.shared.windows.first!) { _ in
                    guard let url: URL = panel.url else { return }
                    do {
                        try self.crashReportService.exportCrashReport(for: instance, to: url, with: fileName, options: options, logURL: logURL, analysis: analysis)
                        log("导出崩溃报告成功")
                    } catch {
                        err("导出崩溃报告失败：\(error.localizedDescription)")
                        hint("导出崩溃报告失败：\(error.localizedDescription)", type: .critical)
                    }
                }
            }
        }
    }

    private func handleProcessTermination(
        _ process: Process,
        instance: MinecraftInstance,
        options: LaunchOptions,
        logURL: URL,
        onCancellation: @escaping () -> Void,
        onCrash: @escaping () -> Void
    ) {
        guard markTerminationHandled(process) else { return }

        log("游戏进程已退出，退出代码：\(process.terminationStatus)")
        if ![0, 9, 15, 128 + 9, 128 + 15].contains(process.terminationStatus) {
            log("游戏非正常退出")
            DispatchQueue.main.async {
                onCrash()
                self.onGameCrash(instance: instance, options: options, logURL: logURL)
            }
        } else {
            try? FileManager.default.removeItem(at: logURL)
        }

        DispatchQueue.main.async {
            onCancellation()
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

    private func subscribeToTask(_ task: MyTask<MinecraftLaunchTask.Model>) {
        cancellables.removeAll()
        task.$currentTaskOrdinal
            .map { ordinal in
                guard let ordinal else { return nil }
                return Self.stageString(for: ordinal)
            }
            .receive(on: DispatchQueue.main)
            .assign(to: \ .currentStage, on: self)
            .store(in: &cancellables)

        task.$progress
            .receive(on: DispatchQueue.main)
            .assign(to: \ .progress, on: self)
            .store(in: &cancellables)
    }

    private static func stageString(for ordinal: Int) -> String {
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
}
