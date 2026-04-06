import Foundation
import Core
import AppKit

enum MinecraftLaunchPreparationService {
    static func showNoUsableJavaPrompt(minVersion: Int, diagnostics: String? = nil) async {
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

    static func noUsableJavaDiagnostics(for instance: MinecraftInstance, minVersion: Int) -> String? {
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

    static func precheck(model: MinecraftLaunchTask.Model, skipLaunchPrecheck: Bool) async throws {
        model.options.manifest = model.manifest
        try model.options.validate()

        if skipLaunchPrecheck {
            log("已临时跳过启动前预检查")
            return
        }

        let entries: [LaunchPrecheck.Entry] = LaunchPrecheck.check(for: model.instance, with: model.options, hasMicrosoftAccount: LauncherConfig.shared.hasMicrosoftAccount)
        log("共 \(entries.count) 个问题：\(entries)")
        for entry in entries {
            switch entry {
            case .javaVersionTooLow(let min):
                _ = await MessageBoxManager.shared.showTextAsync(
                    title: "Java 版本过低",
                    content: "你正在使用 Java \(model.options.javaRuntime.majorVersion) 启动游戏，但这个版本需要 \(min)！",
                    level: .error
                )
                throw CancellationError()
            case .javaVersionOutOfRange(let min, let max):
                _ = await MessageBoxManager.shared.showTextAsync(
                    title: "Java 版本不兼容",
                    content: "你正在使用 Java \(model.options.javaRuntime.majorVersion) 启动游戏，但这个版本只支持 Java \(min)-\(max)。",
                    level: .error
                )
                throw CancellationError()
            case .noMicrosoftAccount:
                if AccountViewModel().accounts.reduce(false, { $0 || ($1.type == .microsoft || $1.type == .thirdParty) }) {
                    LauncherConfig.mutate { $0.hasMicrosoftAccount = true }
                    continue
                }
                if LocaleUtils.isSystemLocaleChinese() {
                    if [3, 8, 15, 30, 50, 70, 90, 110, 130, 180, 220, 280, 330, 380, 450, 550, 660, 750, 880, 950, 1100, 1300, 1500, 1700, 1900].contains(LauncherConfig.shared.launchCount) {
                        Task {
                            if await MessageBoxManager.shared.showTextAsync(
                                title: "考虑一下正版？",
                                content: "你已经启动了 \(LauncherConfig.shared.launchCount) 次 Minecraft 啦！\n如果觉得 Minecraft 还不错，可以购买正版支持一下，毕竟开发游戏也真的很不容易……不要一直白嫖啦。\n\n在登录一次正版账号后，就不会再出现这个提示了！",
                                level: .info,
                                .yes(label: "支持正版游戏！", type: .highlight),
                                .no(label: "下次一定")
                            ) == 1 {
                                NSWorkspace.shared.open(URL(string: "https://www.xbox.com/zh-cn/games/store/minecraft-java-bedrock-edition-for-pc/9nxp44l49shj")!)
                            }
                        }
                    }
                } else {
                    let result: Int = await MessageBoxManager.shared.showTextAsync(
                        title: "正版验证",
                        content: "你必须先登录正版账号，才能进行离线登录！",
                        level: .info,
                        .init(id: 0, label: "购买正版", type: .highlight),
                        .yes(label: "试玩"),
                        .init(id: 2, label: "返回", type: .normal)
                    )
                    switch result {
                    case 0:
                        NSWorkspace.shared.open(URL(string: "https://www.xbox.com/zh-cn/games/store/minecraft-java-bedrock-edition-for-pc/9nxp44l49shj")!)
                        throw CancellationError()
                    case 1:
                        hint("游戏将以试玩模式启动！", type: .critical)
                        model.options.demo = true
                    case 2:
                        throw CancellationError()
                    default:
                        break
                    }
                }
            case .armNotSupported:
                if let runtime: JavaRuntime = model.instance.searchJava(arch: .x64) {
                    if await MessageBoxManager.shared.showTextAsync(
                        title: "不支持的 Java 架构",
                        content: "你正在启动的版本（\(model.instance.version)）不支持使用 ARM64 架构的 Java！\nPCL.Mac 找到了一个可用的 Java，是否切换并继续启动？",
                        level: .error,
                        .no(),
                        .yes(label: "切换并继续", type: .highlight)
                    ) == 0 {
                        throw CancellationError()
                    }
                    model.instance.setJava(url: runtime.executableURL)
                    model.options.javaRuntime = runtime
                    model.manifest = model.instance.manifest
                }
            }
        }
    }

    static func checkResources(model: MinecraftLaunchTask.Model, progressHandler: @escaping (Double) -> Void) async throws {
        let nativesURL: URL = model.instance.runningDirectory.appending(path: "natives")
        if FileManager.default.fileExists(atPath: nativesURL.path) {
            do {
                try FileManager.default.removeItem(at: nativesURL)
                log("删除本地库目录成功")
            } catch {
                err("删除本地库目录失败：\(error.localizedDescription)")
            }
        }

        try await MinecraftInstallTask.completeResources(
            runningDirectory: model.instance.runningDirectory,
            manifest: model.manifest,
            repository: model.repository,
            progressHandler: progressHandler
        )
    }
}
