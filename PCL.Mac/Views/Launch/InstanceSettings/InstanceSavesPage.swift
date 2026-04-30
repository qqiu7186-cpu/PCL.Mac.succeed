import SwiftUI
import Core
import ZIPFoundation
import AppKit

private struct SaveItem: Identifiable {
    let id: URL
    let url: URL
    let modifiedAt: Date?
    let byteSize: Int64

    var name: String { url.lastPathComponent }
    var iconURL: URL { url.appending(path: "icon.png") }
}

struct InstanceSavesPage: View {
    let id: String
    @State private var instance: MinecraftInstance?
    @State private var saves: [SaveItem] = []
    @State private var saveQuery: String = ""

    private var displayedSaves: [SaveItem] {
        let keyword = saveQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if keyword.isEmpty { return saves }
        return saves.filter { $0.name.lowercased().contains(keyword) }
    }

    var body: some View {
        InstanceSettingsBackground {
            if let instance {
                if displayedSaves.isEmpty {
                    InstanceSettingsEmptyStateCard(
                        title: "暂时没有存档文件",
                        description: "可以在此处查看当前实例的存档",
                        primaryTitle: "打开存档文件夹",
                        secondaryTitle: "粘贴剪贴板文件",
                        primaryAction: { openSavesFolder(instance) },
                        secondaryAction: { importSaveArchive() }
                    )
                    .overlay(alignment: .bottomTrailing) {
                        InstanceSettingsFloatingActionButton(systemImage: "power") {
                            openSavesFolder(instance)
                        }
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            searchBar

                            InstanceSettingsSectionCard("快捷操作") {
                                HStack(spacing: 16) {
                                    MyButton("打开存档文件夹") { openSavesFolder(instance) }
                                        .frame(width: 112)
                                    MyButton("粘贴剪贴板文件") { importSaveArchive() }
                                        .frame(width: 112)
                                    Spacer(minLength: 0)
                                }
                                .frame(height: 35)
                            }

                            InstanceSettingsSectionCard("存档列表（\(displayedSaves.count)）") {
                                VStack(spacing: 0) {
                                    HStack {
                                        Spacer()
                                        HStack(spacing: 6) {
                                            Image(systemName: "arrow.up.arrow.down")
                                                .font(.system(size: 12))
                                            MyText("排序：文件名", size: 12, color: .colorGray2)
                                        }
                                    }
                                    .padding(.bottom, 8)

                                    ForEach(displayedSaves) { save in
                                        SaveListRow(save: save) {
                                            NSWorkspace.shared.open(save.url)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 28)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        InstanceSettingsFloatingActionButton(systemImage: "power") {
                            openSavesFolder(instance)
                        }
                    }
                }
            } else {
                MyLoading(viewModel: .init(text: "未找到可配置的实例"), showCard: false)
            }
        }
        .task(id: id) {
            instance = InstancePageLoader.loadInstance(id)
            reloadSaves()
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(.iconSearch)
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
            TextField("", text: $saveQuery)
                .textFieldStyle(.plain)
                .font(.custom("PCLEnglish", size: 14))
            if saveQuery.isEmpty {
                MyText("搜索存档名称", size: 12, color: .colorGray3)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.white.opacity(0.82))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.color6, lineWidth: 1))
        )
    }

    private func reloadSaves() {
        guard let instance else { return }
        let savesURL = instance.runningDirectory.appending(path: "saves")
        let list = InstanceFileBrowserService.saveDirectoryURLs(at: savesURL)
        saves = list.map { entry in
            let size = DirectorySizeService.cachedSize(for: entry.url) ?? InstancePageLoader.folderSize(at: entry.url)
            return SaveItem(id: entry.url, url: entry.url, modifiedAt: entry.modifiedAt, byteSize: size)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func importSaveArchive() {
        guard let instance else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.zip]
        panel.title = "导入存档压缩包"
        guard panel.runModal() == .OK, let source = panel.url else { return }
        do {
            let savesURL = instance.runningDirectory.appending(path: "saves")
            try FileManager.default.createDirectory(at: savesURL, withIntermediateDirectories: true)
            let tempRoot = URLConstants.tempURL.appending(path: "save-import-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tempRoot) }
            try FileManager.default.unzipItem(at: source, to: tempRoot)
            let contents = try FileManager.default.contentsOfDirectory(at: tempRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            for url in contents {
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                guard isDirectory else { continue }
                let destination = savesURL.appending(path: url.lastPathComponent)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: url, to: destination)
            }
            hint("导入成功", type: .finish)
            reloadSaves()
        } catch {
            hint("导入失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func openSavesFolder(_ instance: MinecraftInstance) {
        let savesURL = instance.runningDirectory.appending(path: "saves")
        do {
            try FileManager.default.createDirectory(at: savesURL, withIntermediateDirectories: true)
            NSWorkspace.shared.open(savesURL)
        } catch {
            hint("打开存档文件夹失败：\(error.localizedDescription)", type: .critical)
        }
    }
}

private struct SaveListRow: View {
    let save: SaveItem
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            InstanceSettingsLocalImage(
                url: save.iconURL,
                size: .init(width: 28, height: 28),
                cornerRadius: 4,
                fallbackIcon: "GrassBlock"
            )

            VStack(alignment: .leading, spacing: 2) {
                MyText(save.name, size: 13)
                MyText(
                    "创建时间：\(save.modifiedAt?.formatted(date: .numeric, time: .omitted) ?? "未知")，最后修改时间：\(save.modifiedAt?.formatted(date: .numeric, time: .omitted) ?? "未知")",
                    size: 11,
                    color: .colorGray3
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}
