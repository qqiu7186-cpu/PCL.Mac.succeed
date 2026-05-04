import SwiftUI
import Core
import ZIPFoundation
import AppKit

struct InstanceModifyPage: View {
    let id: String
    @State private var instance: MinecraftInstance?

    private var modifyContext: InstanceModifyContext {
        .init(instanceID: id)
    }

    var body: some View {
        InstanceSettingsScrollPage {
            if let instance {
                InstanceSettingsHeaderCard(
                    instance: instance,
                    subtitle: "\(instance.version.description)\(instance.modLoader.map { "，已附加安装 \($0.description)" } ?? "")"
                )

                modifyRow(title: "Minecraft", value: instance.version.description, icon: "iconGrassBlock", actionTitle: "修改") {
                    AppRouter.shared.setRoot(.download)
                    AppRouter.shared.activeModifyContext = modifyContext
                    AppRouter.shared.append(.minecraftDownload)
                }

                modifyRow(title: "Forge", value: "可以添加", actionTitle: nil) {
                    openCurrentVersionInstallOptions(for: instance)
                }

                modifyRow(title: "NeoForge", value: "无可用版本", actionTitle: nil) {
                    openCurrentVersionInstallOptions(for: instance)
                }

                modifyRow(title: "Fabric", value: "可以添加", actionTitle: nil) {
                    openCurrentVersionInstallOptions(for: instance)
                }

                modifyRow(title: "Quilt", value: "可以添加", actionTitle: nil) {
                    AppRouter.shared.setRoot(.download)
                    AppRouter.shared.append(.installerQuiltDownload)
                }

                modifyRow(title: "LabyMod", value: "可以添加", actionTitle: nil) {
                    AppRouter.shared.setRoot(.download)
                    AppRouter.shared.append(.installerLabyModDownload)
                }

                modifyRow(title: "OptiFine", value: "无可用版本", actionTitle: nil) {
                    AppRouter.shared.setRoot(.download)
                    AppRouter.shared.append(.installerOptiFineDownload)
                }

                InstanceSettingsCenterActionButton(title: "开始重置", systemImage: "arrow.clockwise") {
                    AppRouter.shared.setRoot(.download)
                    AppRouter.shared.activeModifyContext = modifyContext
                    AppRouter.shared.append(.minecraftDownload)
                }
            } else {
                MyLoading(viewModel: .init(text: "未找到可配置的实例"), showCard: false)
            }
        }
        .task(id: id) {
            instance = InstancePageLoader.loadInstance(id)
        }
    }

    private func modifyRow(title: String, value: String, icon: String? = nil, actionTitle: String?, action: @escaping () -> Void) -> some View {
        MyCard("", foldable: false, titled: false, padding: 12) {
            HStack(spacing: 12) {
                MyText(title, size: 13)
                    .frame(width: 90, alignment: .leading)
                if let icon {
                    Image(icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                }
                MyText(value, size: 12, color: .colorGray3)
                Spacer(minLength: 0)
                if let actionTitle {
                    Button(action: action) {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                            Text(actionTitle)
                                .font(.custom("PCLEnglish", size: 12))
                        }
                        .foregroundStyle(Color.colorGray2)
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.color1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
        }
    }

    private func openCurrentVersionInstallOptions(for instance: MinecraftInstance) {
        guard let version = CoreState.versionManifest?.version(for: instance.version.id) else {
            AppRouter.shared.setRoot(.download)
            AppRouter.shared.activeModifyContext = modifyContext
            AppRouter.shared.append(.minecraftDownload)
            hint("已进入版本管理，请选择与当前实例匹配的 Minecraft 版本后再添加加载器。", type: .info)
            return
        }
        AppRouter.shared.setRoot(.download)
        AppRouter.shared.activeModifyContext = modifyContext
        AppRouter.shared.append(.minecraftInstallOptions(version: version, modifyContext: modifyContext))
    }
}

struct InstanceExportPage: View {
    let id: String
    @State private var instance: MinecraftInstance?
    @State private var includeBasic = true
    @State private var includeMods = true
    @State private var includeResourcepacks = true
    @State private var includeShaderpacks = true
    @State private var includeSaves = false
    @State private var modpackName = ""
    @State private var modpackVersion = "1.0.0"
    @State private var includePCLConfig = true
    @State private var includePCLPersonalization = true

    var body: some View {
        InstanceSettingsScrollPage {
            if let instance {
                InstanceSettingsSectionCard("") {
                    HStack(spacing: 18) {
                        InstanceSettingsFieldRow("整合包名称") {
                            InstanceSettingsInputBox(text: modpackName)
                        }
                        .frame(maxWidth: .infinity)
                        InstanceSettingsFieldRow("整合包版本") {
                            InstanceSettingsInputBox(text: modpackVersion)
                        }
                        .frame(width: 220)
                    }
                }

                InstanceSettingsSectionCard("导出内容列表") {
                    VStack(alignment: .leading, spacing: 8) {
                        InstanceSettingsCheckboxRow(title: "游戏本体    正式版 \(instance.version.description)", isOn: $includeBasic)
                        InstanceSettingsCheckboxRow(title: "PCL 启动器程序    打包出现 PCL，以便没有启动器的玩家安装整合包", isOn: $includePCLConfig)
                        if includePCLConfig {
                            InstanceSettingsCheckboxRow(title: "PCL 个性化内容    功能隐藏设置、主页、背景音乐和图片等", isOn: $includePCLPersonalization)
                                .padding(.leading, 24)
                        }
                    }
                }

                InstanceSettingsSectionCard("高级选项", folded: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        InstanceSettingsCheckboxRow(title: "打包资源文件，以避免在导入时下载", isOn: $includeMods)
                        InstanceSettingsCheckboxRow(title: "Modrinth 上传模式", isOn: $includeShaderpacks)

                        InstanceSettingsInfoBanner(text: "配置文件中会有更多高级选项，例如精准控制导出的文件、设置整合包存放位置等。修改这些选项，请先点击“读取配置”，在编辑配置文件后再导入。")

                        HStack(spacing: 16) {
                            MyButton("读取配置") {}
                                .frame(width: 112)
                            MyButton("保存配置") {}
                                .frame(width: 112)
                            MyButton("整合包制作指南") {}
                                .frame(width: 112)
                            Spacer(minLength: 0)
                        }
                        .frame(height: 35)
                    }
                }

                InstanceSettingsCenterActionButton(title: "开始导出", systemImage: "shippingbox") {
                    exportInstance(instance)
                }
            } else {
                MyLoading(viewModel: .init(text: "未找到可配置的实例"), showCard: false)
            }
        }
        .task(id: id) {
            instance = InstancePageLoader.loadInstance(id)
            modpackName = instance?.name ?? ""
        }
    }

    private func exportInstance(_ instance: MinecraftInstance) {
        let panel = NSSavePanel()
        panel.title = "导出实例"
        panel.nameFieldStringValue = "\(instance.name).zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            let tempRoot = URLConstants.tempURL.appending(path: "instance-export-\(UUID().uuidString)")
            let exportRoot = tempRoot.appending(path: instance.name)
            defer { try? FileManager.default.removeItem(at: tempRoot) }
            try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)

            func copyIfExists(_ source: URL, _ target: URL) throws {
                guard FileManager.default.fileExists(atPath: source.path) else { return }
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.copyItem(at: source, to: target)
            }

            if includeBasic {
                try copyIfExists(instance.runningDirectory.appending(path: "\(instance.name).json"), exportRoot.appending(path: "\(instance.name).json"))
                try copyIfExists(instance.runningDirectory.appending(path: "\(instance.name).jar"), exportRoot.appending(path: "\(instance.name).jar"))
                try copyIfExists(instance.runningDirectory.appending(path: ".clconfig.json"), exportRoot.appending(path: ".clconfig.json"))
            }
            if includeMods {
                try copyIfExists(instance.runningDirectory.appending(path: "mods"), exportRoot.appending(path: "mods"))
            }
            if includeResourcepacks {
                try copyIfExists(instance.runningDirectory.appending(path: "resourcepacks"), exportRoot.appending(path: "resourcepacks"))
            }
            if includeShaderpacks {
                try copyIfExists(instance.runningDirectory.appending(path: "shaderpacks"), exportRoot.appending(path: "shaderpacks"))
            }
            if includeSaves {
                try copyIfExists(instance.runningDirectory.appending(path: "saves"), exportRoot.appending(path: "saves"))
            }

            try FileManager.default.zipItem(at: exportRoot, to: destination, shouldKeepParent: true)
            hint("实例导出成功", type: .finish)
        } catch {
            hint("导出失败：\(error.localizedDescription)", type: .critical)
        }
    }
}
