import SwiftUI
import Core
import AppKit

struct InstanceOverviewPage: View {
    let id: String
    @State private var instance: MinecraftInstance?
    @State private var localDesc: String = ""
    @State private var isFavorite: Bool = false

    var body: some View {
        InstanceSettingsScrollPage {
            if let instance {
                InstanceSettingsHeaderCard(instance: instance, subtitle: instance.version.description)

                InstanceSettingsSectionCard("实例信息") {
                    HStack(spacing: 28) {
                        infoItem(icon: .iconBlock, title: "启动次数", value: "暂无记录")
                        infoItem(icon: instance.modLoader?.icon ?? .iconGrassBlock, title: instance.modLoader?.description ?? "Minecraft", value: instance.version.description)
                        Spacer(minLength: 0)
                    }
                }

                InstanceSettingsSectionCard("个性化") {
                    VStack(alignment: .leading, spacing: 12) {
                        InstanceSettingsFieldRow("图标") {
                            InstanceSettingsInputBox(text: "自动", showsChevron: true)
                        }
                        InstanceSettingsFieldRow("分类") {
                            InstanceSettingsInputBox(text: isFavorite ? "收藏夹" : "自动", showsChevron: true)
                        }
                        HStack(spacing: 16) {
                            MyButton("修改实例名") {
                                rename(instance)
                            }
                            .frame(width: 112)
                            MyButton("修改实例描述") {
                                editDescription()
                            }
                            .frame(width: 112)
                            MyButton(isFavorite ? "取消收藏夹" : "加入收藏夹") {
                                isFavorite.toggle()
                                InstanceMetadataService.setFavorite(isFavorite, for: id)
                            }
                            .frame(width: 112)
                            Spacer(minLength: 0)
                        }
                        .frame(height: 35)
                    }
                }

                InstanceSettingsSectionCard("快捷方式") {
                    HStack(spacing: 16) {
                        quickButton("实例文件夹") {
                            NSWorkspace.shared.open(instance.runningDirectory)
                        }
                        quickButton("存档文件夹") {
                            try? InstancePageActionService.openManagedFolder(instance.runningDirectory.appending(path: "saves"))
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: 35)
                }

                InstanceSettingsSectionCard("高级管理") {
                    HStack(spacing: 16) {
                        quickButton("导出启动脚本") { exportLaunchScript(instance) }
                        quickButton("测试游戏") { testLaunch(instance) }
                        quickButton("补全文件") { checkGameFiles(instance) }
                        quickButton("重置") { resetConfig(instance) }
                        MyButton("删除实例", type: .red) {
                            deleteInstance(instance)
                        }
                        .frame(width: 112)
                        quickButton("修补核心") {
                            NSWorkspace.shared.open(instance.manifestURL)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: 35)
                }
            } else {
                MyLoading(viewModel: .init(text: "未找到可配置的实例"), showCard: false)
            }
        }
        .task(id: id) {
            instance = InstancePageLoader.loadInstance(id)
            localDesc = InstanceMetadataService.description(for: id)
            isFavorite = InstanceMetadataService.isFavorite(instanceID: id)
        }
    }

    private func infoItem(icon: ImageResource, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                MyText(title, size: 12, color: .colorGray2)
                MyText(value, size: 12)
            }
        }
    }

    private func quickButton(_ title: String, action: @escaping () -> Void) -> some View {
        MyButton(title) { action() }
            .frame(width: 112)
    }

    private func rename(_ instance: MinecraftInstance) {
        MessageBoxManager.shared.showInput(title: "修改实例名", initialContent: instance.name) { text in
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            do {
                let oldID = instance.name
                let renamed = try InstanceManager.shared.renameInstance(instance, to: text)
                self.instance = renamed
                InstanceMetadataService.migrate(from: oldID, to: renamed.name)
                AppRouter.shared.replaceInstanceID(from: oldID, to: renamed.name)
                hint("实例名已修改", type: .finish)
            } catch {
                hint("修改失败：\(error.localizedDescription)", type: .critical)
            }
        }
    }

    private func editDescription() {
        MessageBoxManager.shared.showInput(title: "修改实例描述", initialContent: localDesc, placeholder: "输入描述") { text in
            localDesc = text ?? ""
            InstanceMetadataService.setDescription(localDesc, for: id)
        }
    }

    private func exportLaunchScript(_ instance: MinecraftInstance) {
        guard let repository = InstanceManager.shared.currentRepository else {
            hint("未找到实例仓库，无法导出脚本", type: .critical)
            return
        }
        guard let account = AccountViewModel().currentAccount else {
            hint("缺少账号，无法导出启动脚本", type: .critical)
            return
        }
        guard let runtime = instance.resolveJavaForLaunch() else {
            hint("没有可用 Java，无法导出启动脚本", type: .critical)
            return
        }
        do {
            try InstancePageActionService.exportLaunchScript(instance: instance, repository: repository, account: account, runtime: runtime)
            hint("启动脚本导出成功", type: .finish)
        } catch {
            hint("导出启动脚本失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func testLaunch(_ instance: MinecraftInstance) {
        guard let repository = InstanceManager.shared.currentRepository,
              let account = AccountViewModel().currentAccount else {
            hint("缺少可用账号或实例，无法测试启动", type: .critical)
            return
        }
        InstanceManager.shared.launch(instance, account, in: repository)
        AppRouter.shared.append(.tasks)
    }

    private func resetConfig(_ instance: MinecraftInstance) {
        MessageBoxManager.shared.showText(
            title: "确认重置",
            content: "重置将删除该实例的 .clconfig 配置文件，确定继续吗？",
            level: .error,
            .no(),
            .yes(type: .red)
        ) { result in
            guard result == 1 else { return }
            let configURL = instance.runningDirectory.appending(path: ".clconfig.json")
            do {
                if FileManager.default.fileExists(atPath: configURL.path) {
                    try FileManager.default.removeItem(at: configURL)
                }
                hint("已重置实例配置", type: .finish)
            } catch {
                hint("重置失败：\(error.localizedDescription)", type: .critical)
            }
        }
    }

    private func deleteInstance(_ instance: MinecraftInstance) {
        MessageBoxManager.shared.showText(
            title: "确认删除",
            content: "删除实例后不可恢复，确定继续？",
            level: .error,
            .no(),
            .yes(type: .red)
        ) { result in
            guard result == 1 else { return }
            do {
                try InstanceManager.shared.deleteInstance(instance)
                AppRouter.shared.removeLast()
            } catch {
                hint("删除失败：\(error.localizedDescription)", type: .critical)
            }
        }
    }

    private func checkGameFiles(_ instance: MinecraftInstance) {
        guard let repository = InstanceManager.shared.currentRepository else {
            hint("未找到实例仓库，无法检查文件", type: .critical)
            return
        }
        let task: MyTask<EmptyModel> = .init(
            name: "检查资源文件 - \(instance.name)",
            model: .init(),
            .init(0, "校验并补全资源") { task, _ in
                try await MinecraftInstallTask.completeResources(
                    runningDirectory: instance.runningDirectory,
                    manifest: instance.manifest,
                    repository: repository,
                    progressHandler: task.setProgress(_:)
                )
            }
        )
        TaskManager.shared.execute(task: task) { error in
            if let error {
                hint("文件检查失败：\(error.localizedDescription)", type: .critical)
            } else {
                hint("资源文件检查完成", type: .finish)
            }
        }
        AppRouter.shared.append(.tasks)
    }
}
