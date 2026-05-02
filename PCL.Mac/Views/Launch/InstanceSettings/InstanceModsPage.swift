import SwiftUI
import Core
import UniformTypeIdentifiers
import AppKit

private struct ModFileItem: Identifiable {
    let id: URL
    let url: URL
    let modifiedAt: Date?
    let byteSize: Int64
    let metadataTitle: String?
    let metadataDescription: String?
    let icon: NSImage?
    let remoteIconURL: URL?

    var name: String { url.lastPathComponent }
    var isDisabled: Bool { url.pathExtension.lowercased() == "disabled" }

    func withRemoteIconURL(_ remoteIconURL: URL?) -> Self {
        .init(
            id: id,
            url: url,
            modifiedAt: modifiedAt,
            byteSize: byteSize,
            metadataTitle: metadataTitle,
            metadataDescription: metadataDescription,
            icon: icon,
            remoteIconURL: remoteIconURL
        )
    }
}

struct InstanceModsPage: View {
    private enum ModSortOption: String, CaseIterable, Identifiable {
        case fileName = "Mod 名称"
        case modifiedAt = "修改时间"

        var id: String { rawValue }
        var label: String { rawValue }
    }

    let id: String
    @State private var instance: MinecraftInstance?
    @State private var files: [ModFileItem] = []
    @State private var query: String = ""
    @State private var sortOption: ModSortOption = .fileName
    @State private var selectedFiles: Set<URL> = []
    @State private var reloadGeneration: Int = 0

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedFiles: [ModFileItem] {
        let keyword = trimmedQuery.lowercased()
        let filtered = keyword.isEmpty ? files : files.filter { $0.name.lowercased().contains(keyword) }
        return filtered.sorted { compareMods(lhs: $0, rhs: $1) }
    }

    var body: some View {
        InstanceSettingsBackground {
            if let instance {
                if instance.modLoader == nil {
                    unavailableState
                } else if files.isEmpty {
                    emptyState(instance)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            InstanceSettingsSearchBar(placeholder: "搜索资源名称 / 描述 / 标签", text: $query)
                            actionCard(instance)
                            listCard
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
            reloadMods()
        }
        .onAppear {
            reloadMods()
        }
    }

    private var unavailableState: some View {
        InstanceSettingsEmptyStateCard(
            title: "该实例不可使用 Mod",
            description: "你需要先安装 Forge、Fabric 等 Mod 加载器才能使用 Mod；请在下载页面安装这些实例。如果你已经安装过了 Mod 加载器，那么你很可能选择了错误的实例，请点击实例选择按钮切换实例。",
            primaryTitle: "转到下载页面",
            secondaryTitle: "实例选择",
            tertiaryTitle: nil,
            primaryAction: {
                AppRouter.shared.setRoot(.download)
            },
            secondaryAction: {
                openInstanceSelection()
            },
            tertiaryAction: nil
        )
    }

    private func emptyState(_ instance: MinecraftInstance) -> some View {
        InstanceSettingsEmptyStateCard(
            title: "尚未安装 Mod",
            description: "你可以下载新的 Mod，也可以从已经下载好的文件安装 Mod。",
            primaryTitle: "从文件安装",
            secondaryTitle: "下载新资源",
            tertiaryTitle: "打开文件夹",
            primaryAction: {
                `import`(instance)
            },
            secondaryAction: {
                AppRouter.shared.setRoot(.download)
                AppRouter.shared.append(.modDownload)
            },
            tertiaryAction: {
                openModsFolder(instance)
            }
        )
    }

    private func actionCard(_ instance: MinecraftInstance) -> some View {
        MyCard("", foldable: false, titled: false, padding: 14) {
            HStack(spacing: 12) {
                MyButton("打开文件夹") { openModsFolder(instance) }
                    .frame(width: 88)
                MyButton("从文件安装") { `import`(instance) }
                    .frame(width: 88)
                MyButton("下载新资源") {
                    AppRouter.shared.setRoot(.download)
                    AppRouter.shared.append(.modDownload)
                }
                .frame(width: 88)
                MyButton("全选") {
                    selectedFiles = Set(displayedFiles.map(\.id))
                    hint("已选中 \(displayedFiles.count) 个 Mod", type: .finish)
                }
                .frame(width: 88)
                MyButton("导出信息") { exportModInfo() }
                    .frame(width: 88)
                Spacer(minLength: 0)
            }
            .frame(height: 35)
        }
    }

    private var listCard: some View {
        MyCard("", foldable: false, titled: false, padding: 14) {
            VStack(spacing: 0) {
                HStack {
                    InstanceSettingsCountBadge(text: "全部(\(displayedFiles.count))")
                    Spacer(minLength: 0)
                    Menu {
                        ForEach(ModSortOption.allCases) { option in
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
                        InstanceSettingsSortChip(label: sortOption.label)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 8)

                if displayedFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        MyText("没有找到匹配的 Mod。", size: 13)
                        MyText("试试搜索其它名称，或者检查 mods 文件夹中的文件名是否正确。", size: 11.5, color: .colorGray3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                } else {
                    ForEach(displayedFiles) { item in
                        ModListRow(
                            item: item,
                            selected: selectedFiles.contains(item.id),
                            showDetails: { Task { await showDetails(for: item) } },
                            revealInFinder: { revealInFinder(item) },
                            toggleEnabled: { toggle(item) },
                            removeAction: { Task { await remove(item) } },
                            rowTapAction: { toggleSelection(item) }
                        )
                    }
                }
            }
        }
    }

    private func reloadMods() {
        guard let instance else { return }
        let modsURL = instance.runningDirectory.appending(path: "mods")
        try? FileManager.default.createDirectory(at: modsURL, withIntermediateDirectories: true)
        let list = InstanceFileBrowserService.listDirectory(at: modsURL)
        let items = list
            .filter {
                let lowercasedName = $0.lastPathComponent.lowercased()
                return lowercasedName.hasSuffix(".jar") ||
                    lowercasedName.hasSuffix(".zip") ||
                    lowercasedName.hasSuffix(".litemod") ||
                    lowercasedName.hasSuffix(".jar.disabled") ||
                    lowercasedName.hasSuffix(".zip.disabled") ||
                    lowercasedName.hasSuffix(".litemod.disabled")
            }
            .map { url in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let metadata = InstancePageLoader.modPreviewMetadata(at: url)
                return ModFileItem(
                    id: url,
                    url: url,
                    modifiedAt: values?.contentModificationDate,
                    byteSize: Int64(values?.fileSize ?? 0),
                    metadataTitle: metadata.title,
                    metadataDescription: metadata.description,
                    icon: metadata.icon,
                    remoteIconURL: nil
                )
            }
        files = items
        selectedFiles = selectedFiles.intersection(Set(files.map(\.id)))
        reloadGeneration += 1
        let generation = reloadGeneration
        Task {
            await enrichRemoteIcons(for: items, generation: generation)
        }
    }

    private func enrichRemoteIcons(for items: [ModFileItem], generation: Int) async {
        let iconURLs = await InstanceRemoteProjectIconResolver.shared.iconURLs(for: items.map(\.url), expectedType: .mod)
        guard !iconURLs.isEmpty else { return }
        await MainActor.run {
            guard reloadGeneration == generation else { return }
            files = files.map { item in
                item.withRemoteIconURL(iconURLs[item.url] ?? item.remoteIconURL)
            }
        }
    }

    private func toggle(_ item: ModFileItem) {
        let newURL: URL = item.isDisabled ? item.url.deletingPathExtension() : item.url.appendingPathExtension("disabled")
        do {
            try FileManager.default.moveItem(at: item.url, to: newURL)
            hint(item.isDisabled ? "已启用 \(item.name)" : "已禁用 \(item.name)", type: .finish)
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

    private func openModsFolder(_ instance: MinecraftInstance) {
        let modsURL = instance.runningDirectory.appending(path: "mods")
        do {
            try FileManager.default.createDirectory(at: modsURL, withIntermediateDirectories: true)
            NSWorkspace.shared.open(modsURL)
        } catch {
            hint("打开 mods 文件夹失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func openInstanceSelection() {
        AppRouter.shared.setRoot(.launch)
        if let repository = InstanceManager.shared.currentRepository {
            AppRouter.shared.append(.instanceList(.init(repository: repository)))
        }
    }

    private func revealInFinder(_ item: ModFileItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    private func toggleSelection(_ item: ModFileItem) {
        if selectedFiles.contains(item.id) {
            selectedFiles.remove(item.id)
        } else {
            selectedFiles.insert(item.id)
        }
    }

    private func exportModInfo() {
        let exportItems = selectedFiles.isEmpty ? displayedFiles : displayedFiles.filter { selectedFiles.contains($0.id) }
        guard !exportItems.isEmpty else {
            hint("当前没有可导出的 Mod 信息", type: .info)
            return
        }

        let panel = NSSavePanel()
        panel.title = "导出 Mod 信息"
        panel.nameFieldStringValue = "Mod 列表-\(instance?.name ?? id).txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let content = exportItems.map { item in
            [
                "名称：\(item.name)",
                "状态：\(item.isDisabled ? "已禁用" : "已启用")",
                "大小：\(InstancePageLoader.fileSizeString(item.byteSize))",
                "修改时间：\(item.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知")",
                "路径：\(item.url.path)"
            ].joined(separator: "\n")
        }.joined(separator: "\n\n") + "\n"

        do {
            try content.write(to: destination, atomically: true, encoding: .utf8)
            hint("已导出 \(exportItems.count) 个 Mod 的信息", type: .finish)
        } catch {
            hint("导出失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func showDetails(for item: ModFileItem) async {
        let content = [
            "名称：\(item.name)",
            "状态：\(item.isDisabled ? "已禁用" : "已启用")",
            "大小：\(InstancePageLoader.fileSizeString(item.byteSize))",
            "最后修改：\(item.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知")",
            "路径：\(item.url.path)"
        ].joined(separator: "\n")
        await MessageBoxManager.shared.showAlertAsync(title: "Mod 详情", content: content)
    }

    private func remove(_ item: ModFileItem) async {
        let confirmed = await MessageBoxManager.shared.showConfirmAsync(
            title: "确认删除",
            content: "确定要删除 Mod \(item.name) 吗？此操作不可恢复。",
            level: .error,
            cancelLabel: "取消",
            confirmLabel: "删除",
            confirmType: .red
        )
        guard confirmed else { return }

        do {
            try FileManager.default.removeItem(at: item.url)
            hint("已删除 \(item.name)", type: .finish)
            selectedFiles.remove(item.id)
            reloadMods()
        } catch {
            hint("删除失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func compareMods(lhs: ModFileItem, rhs: ModFileItem) -> Bool {
        switch sortOption {
        case .fileName:
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
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
}

private struct ModListRow: View {
    let item: ModFileItem
    let selected: Bool
    let showDetails: () -> Void
    let revealInFinder: () -> Void
    let toggleEnabled: () -> Void
    let removeAction: () -> Void
    let rowTapAction: () -> Void

    var body: some View {
        MyListItem { hovered in
            HStack(spacing: 10) {
                if selected {
                    Capsule()
                        .fill(Color.color3)
                        .frame(width: 4, height: 28)
                }

                InstanceSettingsPreviewIcon(image: item.icon, remoteImageURL: item.remoteIconURL, fileURL: item.url, size: .init(width: 32, height: 32), cornerRadius: 6, fallbackImageResource: .iconMod)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        MyText(item.displayName, size: 13, color: item.isDisabled ? .colorGray2 : .color1)
                            .lineLimit(1)
                        if item.isDisabled {
                            MyText("已禁用", size: 11, color: .color3)
                        }
                    }
                    MyText(
                        item.secondaryText,
                        size: 11,
                        color: .colorGray3
                    )
                    .lineLimit(1)
                }

                Spacer(minLength: 0)

                if hovered {
                    HStack(spacing: 12) {
                        InstanceSettingsHoverActionButton(systemImage: "info.circle", color: .color3, help: "详情", action: showDetails)
                        InstanceSettingsHoverActionButton(systemImage: "folder", color: .color3, help: "在访达中显示", action: revealInFinder)
                        InstanceSettingsHoverActionButton(systemImage: item.isDisabled ? "checkmark.circle" : "minus.circle", color: .color3, help: item.isDisabled ? "启用" : "禁用", action: toggleEnabled)
                        InstanceSettingsHoverActionButton(systemImage: "trash", color: .red, help: "删除", action: removeAction)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 2)
        }
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(selected ? Color.color3.opacity(0.08) : .clear)
        )
        .onTapGesture(perform: rowTapAction)
    }
}

private extension ModFileItem {
    var displayName: String {
        metadataTitle ?? (isDisabled ? url.deletingPathExtension().lastPathComponent : name)
    }

    var secondaryText: String {
        let detail = "\(InstancePageLoader.fileSizeString(byteSize)) · 修改于 \(modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知")"
        if let metadataDescription, !metadataDescription.isEmpty {
            return "\(metadataDescription) · \(detail)"
        }
        return detail
    }
}
