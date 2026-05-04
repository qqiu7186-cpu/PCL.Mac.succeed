import SwiftUI
import Core
import ZIPFoundation
import AppKit

private struct SaveItem: Identifiable {
    let id: URL
    let url: URL
    let createdAt: Date?
    let modifiedAt: Date?
    let byteSize: Int64

    var name: String { url.lastPathComponent }
    var iconURL: URL { url.appending(path: "icon.png") }
}

struct InstanceSavesPage: View {
    private enum SaveSortOption: String, CaseIterable, Identifiable {
        case fileName = "文件名"
        case createdAt = "创建时间"
        case modifiedAt = "修改时间"

        var id: String { rawValue }
        var label: String { rawValue }
    }

    let id: String
    @State private var instance: MinecraftInstance?
    @State private var saves: [SaveItem] = []
    @State private var saveQuery: String = ""
    @State private var sortOption: SaveSortOption = .fileName

    private var trimmedSaveQuery: String {
        saveQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasActiveSearch: Bool {
        !trimmedSaveQuery.isEmpty
    }

    private var displayedSaves: [SaveItem] {
        let keyword = trimmedSaveQuery.lowercased()
        let filtered = keyword.isEmpty ? saves : saves.filter { $0.name.lowercased().contains(keyword) }
        return filtered.sorted(by: compareSaves(lhs:rhs:))
    }

    var body: some View {
        InstanceSettingsBackground {
            if let instance {
                if saves.isEmpty {
                    InstanceSettingsEmptyStateCard(
                        title: "暂时没有存档文件",
                        description: "可以在此处查看当前实例的存档",
                        primaryTitle: "打开存档文件夹",
                        secondaryTitle: "粘贴剪贴板文件",
                        primaryAction: { openSavesFolder(instance) },
                        secondaryAction: { pasteSaveFromClipboard() }
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            searchBar

                            InstanceSettingsSectionCard("快捷操作") {
                                HStack(spacing: 16) {
                                    MyButton("打开存档文件夹") { openSavesFolder(instance) }
                                        .frame(width: 112)
                                    MyButton("粘贴剪贴板文件") { pasteSaveFromClipboard() }
                                        .frame(width: 112)
                                    MyButton("导入存档压缩包") { importSaveArchive() }
                                        .frame(width: 112)
                                    Spacer(minLength: 0)
                                }
                                .frame(height: 35)
                            }

                            InstanceSettingsSectionCard("存档列表（\(displayedSaves.count)）") {
                                VStack(spacing: 0) {
                                    HStack {
                                        Spacer()
                                        Menu {
                                            ForEach(SaveSortOption.allCases) { option in
                                                Button {
                                                    sortOption = option
                                                } label: {
                                                    if sortOption == option {
                                                        Label(option.label, systemImage: "checkmark")
                                                    } else {
                                                        Text(option.label)
                                                    }
                                                }
                                            }
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "arrow.up.arrow.down")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(Color.color1)
                                                MyText("排序：\(sortOption.label)", size: 12, color: .color1)
                                            }
                                            .padding(.horizontal, 10)
                                            .frame(height: 28)
                                            .background(
                                                RoundedRectangle(cornerRadius: 5)
                                                    .fill(Color.white.opacity(0.82))
                                                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.color6, lineWidth: 1))
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.bottom, 8)

                                    if displayedSaves.isEmpty {
                                        VStack(alignment: .leading, spacing: 6) {
                                            MyText("没有找到匹配的存档。", size: 13)
                                            MyText("试试搜索其它名称，或者检查存档文件夹中的目录名是否正确。", size: 11.5, color: .colorGray3)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 12)
                                    } else {
                                        ForEach(displayedSaves) { save in
                                            SaveListRow(
                                                save: save,
                                                openAction: { NSWorkspace.shared.open(save.url) },
                                                deleteAction: { Task { await deleteSave(save) } },
                                                copyAction: { copySavePath(save) },
                                                detailsAction: { Task { await showSaveDetails(save) } },
                                                quickLaunchAction: { quickLaunch(instance) }
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 28)
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
        .onAppear {
            reloadSaves()
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(.iconSearch)
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
                .foregroundStyle(Color.color1)
            ZStack(alignment: .leading) {
                TextField("", text: $saveQuery)
                    .textFieldStyle(.plain)
                    .font(.custom("PCLEnglish", size: 14))
                    .foregroundStyle(Color.color1)
                if saveQuery.isEmpty {
                    Text("搜索存档名称")
                        .font(.custom("PCLEnglish", size: 14))
                        .foregroundStyle(Color.colorGray3)
                        .allowsHitTesting(false)
                }
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
        let savesURL = effectiveGameDirectory(for: instance).appending(path: "saves")
        let list = InstanceFileBrowserService.saveDirectoryURLs(at: savesURL)
        saves = list.map { entry in
            let size = DirectorySizeService.cachedSize(for: entry.url) ?? InstancePageLoader.folderSize(at: entry.url)
            return SaveItem(id: entry.url, url: entry.url, createdAt: entry.createdAt, modifiedAt: entry.modifiedAt, byteSize: size)
        }
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
            let savesURL = effectiveGameDirectory(for: instance).appending(path: "saves")
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
        let savesURL = effectiveGameDirectory(for: instance).appending(path: "saves")
        do {
            try FileManager.default.createDirectory(at: savesURL, withIntermediateDirectories: true)
            NSWorkspace.shared.open(savesURL)
        } catch {
            hint("打开存档文件夹失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func copySavePath(_ save: SaveItem) {
        do {
            try SaveClipboardService.copySave(at: save.url)
            hint("已复制存档，可前往其它实例粘贴", type: .finish)
        } catch {
            hint("复制存档失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func pasteSaveFromClipboard() {
        guard let instance else { return }
        let saveSources = SaveClipboardService.copiedSaves().filter {
            let values = try? $0.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory == true
        }

        guard !saveSources.isEmpty else {
            hint("当前没有可粘贴的存档，请先在其它实例中点击复制", type: .info)
            return
        }

        do {
            let savesURL = effectiveGameDirectory(for: instance).appending(path: "saves")
            try FileManager.default.createDirectory(at: savesURL, withIntermediateDirectories: true)
            for source in saveSources {
                let destination = uniqueSaveDestination(for: source.lastPathComponent, in: savesURL)
                try FileManager.default.copyItem(at: source, to: destination)
            }
            hint("已从剪贴板粘贴 \(saveSources.count) 个存档", type: .finish)
            reloadSaves()
        } catch {
            hint("粘贴存档失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func quickLaunch(_ instance: MinecraftInstance) {
        guard let repository = InstanceManager.shared.currentRepository else {
            hint("未找到当前仓库，无法快捷启动", type: .critical)
            return
        }
        guard let account = AccountViewModel().currentAccount else {
            hint("请先添加一个账号", type: .critical)
            return
        }
        InstanceManager.shared.switchInstance(to: instance, repository)
        InstanceManager.shared.launch(instance, account, in: repository)
    }

    private func showSaveDetails(_ save: SaveItem) async {
        let content = [
            "名称：\(save.name)",
            "路径：\(save.url.path)",
            "大小：\(InstancePageLoader.fileSizeString(save.byteSize))",
            "创建时间：\(save.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知")",
            "最后修改：\(save.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知")"
        ].joined(separator: "\n")
        await MessageBoxManager.shared.showAlertAsync(title: "存档详情", content: content)
    }

    private func effectiveGameDirectory(for instance: MinecraftInstance) -> URL {
        if instance.config.versionIsolationEnabled {
            return instance.runningDirectory
        }
        return InstanceManager.shared.currentRepository?.url ?? instance.runningDirectory
    }

    private func uniqueSaveDestination(for originalName: String, in savesURL: URL) -> URL {
        let initialURL = savesURL.appending(path: originalName)
        guard FileManager.default.fileExists(atPath: initialURL.path) else {
            return initialURL
        }

        var index = 2
        while true {
            let candidate = savesURL.appending(path: "\(originalName) (\(index))")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func compareSaves(lhs: SaveItem, rhs: SaveItem) -> Bool {
        switch sortOption {
        case .fileName:
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        case .createdAt:
            return compareDatesDescending(lhs.createdAt, rhs.createdAt, lhsName: lhs.name, rhsName: rhs.name)
        case .modifiedAt:
            return compareDatesDescending(lhs.modifiedAt, rhs.modifiedAt, lhsName: lhs.name, rhsName: rhs.name)
        }
    }

    private func compareDatesDescending(_ lhs: Date?, _ rhs: Date?, lhsName: String, rhsName: String) -> Bool {
        switch (lhs, rhs) {
        case let (lhsDate?, rhsDate?):
            if lhsDate != rhsDate { return lhsDate > rhsDate }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }
        return lhsName.localizedStandardCompare(rhsName) == .orderedAscending
    }

    private func deleteSave(_ save: SaveItem) async {
        let confirmed = await MessageBoxManager.shared.showConfirmAsync(
            title: "确认删除",
            content: "确定要删除存档 \(save.name) 吗？此操作不可恢复。",
            level: .error,
            cancelLabel: "取消",
            confirmLabel: "删除",
            confirmType: .red
        )
        guard confirmed else { return }
        do {
            try FileManager.default.removeItem(at: save.url)
            hint("已删除存档 \(save.name)", type: .finish)
            reloadSaves()
        } catch {
            hint("删除失败：\(error.localizedDescription)", type: .critical)
        }
    }
}

private struct SaveListRow: View {
    let save: SaveItem
    let openAction: () -> Void
    let deleteAction: () -> Void
    let copyAction: () -> Void
    let detailsAction: () -> Void
    let quickLaunchAction: () -> Void

    var body: some View {
        MyListItem { hovered in
            HStack(spacing: 10) {
                InstanceSettingsLocalImage(
                    url: save.iconURL,
                    size: .init(width: 28, height: 28),
                    cornerRadius: 4,
                    fallbackIcon: "iconGrassBlock"
                )

                VStack(alignment: .leading, spacing: 2) {
                    MyText(save.name, size: 13)
                    MyText(
                        "大小：\(InstancePageLoader.fileSizeString(save.byteSize)) · 创建：\(save.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知") · 修改：\(save.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知")",
                        size: 11,
                        color: .colorGray3
                    )
                }

                Spacer(minLength: 0)

                if hovered {
                    HStack(spacing: 12) {
                        hoverAction("folder", color: .color3, action: openAction)
                        hoverAction("trash", color: .red, action: deleteAction)
                        hoverAction("doc.on.doc", color: .color3, action: copyAction)
                        hoverAction("info.circle", color: .color3, action: detailsAction)
                        hoverAction("play.circle", color: .color3, action: quickLaunchAction)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.vertical, 8)
        }
        .onTapGesture(perform: openAction)
    }

    private func hoverAction(_ systemImage: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
        }
        .help(helpText(for: systemImage))
        .buttonStyle(.plain)
    }

    private func helpText(for systemImage: String) -> String {
        switch systemImage {
        case "folder": "打开"
        case "trash": "删除"
        case "doc.on.doc": "复制"
        case "info.circle": "详情"
        case "play.circle": "快捷启动"
        default: ""
        }
    }
}
