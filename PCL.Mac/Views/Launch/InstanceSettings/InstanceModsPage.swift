import SwiftUI
import Core
import UniformTypeIdentifiers
import AppKit

private struct ModFileItem: Identifiable {
    let id: URL
    let url: URL

    var name: String { url.lastPathComponent }
    var isDisabled: Bool { url.pathExtension.lowercased() == "disabled" }
}

struct InstanceModsPage: View {
    let id: String
    @State private var instance: MinecraftInstance?
    @State private var files: [ModFileItem] = []

    var body: some View {
        CardContainer {
            if let instance {
                if instance.modLoader == nil {
                    MyCard("模组", foldable: false) {
                        VStack(alignment: .leading, spacing: 10) {
                            MyText("该实例不可使用模组，请先安装 Forge/Fabric 等加载器。", color: .colorGray3)
                            HStack(spacing: 15) {
                                MyButton("下载 Forge") {
                                    AppRouter.shared.setRoot(.download)
                                    AppRouter.shared.append(.installerForgeDownload)
                                }
                                .frame(width: 120)
                                MyButton("下载 NeoForge") {
                                    AppRouter.shared.setRoot(.download)
                                    AppRouter.shared.append(.installerNeoForgeDownload)
                                }
                                .frame(width: 120)
                                MyButton("下载 Fabric") {
                                    AppRouter.shared.setRoot(.download)
                                    AppRouter.shared.append(.installerFabricDownload)
                                }
                                .frame(width: 120)
                                Spacer()
                            }
                            .frame(height: 35)
                        }
                    }
                } else {
                    if !files.isEmpty {
                        MyCard("模组", foldable: false) {
                            HStack(spacing: 15) {
                                MyButton("打开 mods 文件夹") {
                                    NSWorkspace.shared.open(instance.runningDirectory.appending(path: "mods"))
                                }
                                .frame(width: 120)
                                MyButton("从文件安装") {
                                    `import`(instance)
                                }
                                .frame(width: 120)
                                MyButton("下载模组") {
                                    AppRouter.shared.setRoot(.download)
                                    AppRouter.shared.append(.modDownload)
                                }
                                .frame(width: 120)
                                Spacer()
                            }
                            .frame(height: 35)
                        }
                    }

                    MyCard(modListTitle(), foldable: false) {
                        if files.isEmpty {
                            VStack(spacing: 10) {
                                MyText("你还没有安装任何模组！", size: 18, color: .colorGray3)
                                HStack(spacing: 15) {
                                    Spacer()
                                    MyButton("打开 mods 文件夹") {
                                        NSWorkspace.shared.open(instance.runningDirectory.appending(path: "mods"))
                                    }
                                    .frame(width: 120)
                                    MyButton("下载 Mod") {
                                        AppRouter.shared.setRoot(.download)
                                        AppRouter.shared.append(.modDownload)
                                    }
                                    .frame(width: 120)
                                    Spacer()
                                }
                                .frame(height: 35)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(files) { item in
                                    MyListItem {
                                        HStack {
                                            MyText(item.name, color: item.isDisabled ? .colorGray3 : .color1)
                                                .lineLimit(1)
                                            Spacer()
                                            MyButton(item.isDisabled ? "启用" : "禁用") {
                                                toggle(item)
                                            }
                                            .frame(width: 90)
                                            MyButton("打开") {
                                                NSWorkspace.shared.open(item.url)
                                            }
                                            .frame(width: 90)
                                            MyButton("删除", type: .red) {
                                                remove(item)
                                            }
                                            .frame(width: 90)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .cardIndex(1)
                }
            } else {
                MyLoading(viewModel: .init(text: "未找到可配置的实例"))
            }
        }
        .task(id: id) {
            instance = InstancePageLoader.loadInstance(id)
            reloadMods()
        }
    }

    private func reloadMods() {
        guard let instance else { return }
        let modsURL = instance.runningDirectory.appending(path: "mods")
        try? FileManager.default.createDirectory(at: modsURL, withIntermediateDirectories: true)
        let list = InstanceFileBrowserService.listDirectory(at: modsURL)
        files = list
            .filter { ["jar", "disabled"].contains($0.pathExtension.lowercased()) }
            .map { .init(id: $0, url: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func modListTitle() -> String {
        files.isEmpty ? "已安装" : "已安装（\(files.count)）"
    }

    private func toggle(_ item: ModFileItem) {
        let newURL: URL = item.isDisabled ? item.url.deletingPathExtension() : item.url.appendingPathExtension("disabled")
        do {
            try FileManager.default.moveItem(at: item.url, to: newURL)
            reloadMods()
        } catch {
            hint("切换 Mod 状态失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func `import`(_ instance: MinecraftInstance) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType(filenameExtension: "jar") ?? .data]
        panel.title = "选择要安装的 Mod 文件"
        guard panel.runModal() == .OK else { return }
        let modsURL = instance.runningDirectory.appending(path: "mods")
        do {
            try FileManager.default.createDirectory(at: modsURL, withIntermediateDirectories: true)
            var importedCount = 0
            var skippedCount = 0
            for source in panel.urls {
                guard source.pathExtension.lowercased() == "jar" else {
                    skippedCount += 1
                    continue
                }
                let destination = modsURL.appending(path: source.lastPathComponent)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: source, to: destination)
                importedCount += 1
            }
            if importedCount > 0 {
                hint("Mod 安装完成：成功 \(importedCount) 个", type: .finish)
            }
            if skippedCount > 0 {
                hint("已跳过 \(skippedCount) 个非 .jar 文件", type: .info)
            }
            if importedCount == 0 {
                hint("未导入任何 Mod，请选择 .jar 文件", type: .critical)
            }
            reloadMods()
        } catch {
            hint("Mod 安装失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func remove(_ item: ModFileItem) {
        do {
            try FileManager.default.removeItem(at: item.url)
            hint("已删除 \(item.name)", type: .finish)
            reloadMods()
        } catch {
            hint("删除失败：\(error.localizedDescription)", type: .critical)
        }
    }
}
