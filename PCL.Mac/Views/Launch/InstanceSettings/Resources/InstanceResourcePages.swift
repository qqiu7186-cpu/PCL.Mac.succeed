import SwiftUI
import Core
import UniformTypeIdentifiers
import AppKit

private struct ResourceFileItem: Identifiable {
    let id: URL
    let url: URL
    let modifiedAt: Date?
    let byteSize: Int64
    let metadataDescription: String?
    let icon: NSImage?
    let remoteIconURL: URL?

    var name: String { url.lastPathComponent }
    var displayName: String { InstancePageLoader.friendlyArchiveDisplayName(for: url) }

    func withRemoteIconURL(_ remoteIconURL: URL?) -> Self {
        .init(
            id: id,
            url: url,
            modifiedAt: modifiedAt,
            byteSize: byteSize,
            metadataDescription: metadataDescription,
            icon: icon,
            remoteIconURL: remoteIconURL
        )
    }
}

struct InstanceFolderResourcePage: View {
    private enum ResourceSortOption: String, CaseIterable, Identifiable {
        case fileName = "资源名称"
        case modifiedAt = "修改时间"

        var id: String { rawValue }
        var label: String { rawValue }
    }

    let id: String
    let title: String
    let folderName: String
    let allowedTypes: [UTType]
    let quickOpenButtonText: String
    let importButtonText: String
    let emptyTitle: String
    let emptyDescription: String
    let showImportButton: Bool
    let showEmptyOpenFolderButton: Bool
    let hideTopCardWhenEmpty: Bool
    let hideListCountWhenEmpty: Bool
    let emptyDownloadButtonText: String
    let primaryButtonWidth: CGFloat
    let listActionButtonWidth: CGFloat
    let remoteProjectType: ModrinthProjectType?

    init(
        id: String,
        title: String,
        folderName: String,
        allowedTypes: [UTType],
        quickOpenButtonText: String = "打开文件夹",
        importButtonText: String = "从文件安装",
        emptyTitle: String = "暂无文件。",
        emptyDescription: String = "你可以从文件导入资源。",
        showImportButton: Bool = true,
        showEmptyOpenFolderButton: Bool = false,
        hideTopCardWhenEmpty: Bool = false,
        hideListCountWhenEmpty: Bool = false,
        emptyDownloadButtonText: String = "下载新资源",
        primaryButtonWidth: CGFloat = 120,
        listActionButtonWidth: CGFloat = 90,
        remoteProjectType: ModrinthProjectType? = nil
    ) {
        self.id = id
        self.title = title
        self.folderName = folderName
        self.allowedTypes = allowedTypes
        self.quickOpenButtonText = quickOpenButtonText
        self.importButtonText = importButtonText
        self.emptyTitle = emptyTitle
        self.emptyDescription = emptyDescription
        self.showImportButton = showImportButton
        self.showEmptyOpenFolderButton = showEmptyOpenFolderButton
        self.hideTopCardWhenEmpty = hideTopCardWhenEmpty
        self.hideListCountWhenEmpty = hideListCountWhenEmpty
        self.emptyDownloadButtonText = emptyDownloadButtonText
        self.primaryButtonWidth = primaryButtonWidth
        self.listActionButtonWidth = listActionButtonWidth
        self.remoteProjectType = remoteProjectType
    }

    @State private var instance: MinecraftInstance?
    @State private var files: [ResourceFileItem] = []
    @State private var selectedFiles: Set<URL> = []
    @State private var query: String = ""
    @State private var sortOption: ResourceSortOption = .fileName
    @State private var reloadGeneration: Int = 0

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedFiles: [ResourceFileItem] {
        let keyword = trimmedQuery.lowercased()
        let filtered = keyword.isEmpty ? files : files.filter { $0.name.lowercased().contains(keyword) }
        return filtered.sorted { compareFiles(lhs: $0, rhs: $1) }
    }

    var body: some View {
        InstanceSettingsBackground {
            if let instance {
                if files.isEmpty {
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
            reloadFiles()
        }
    }

    private func emptyState(_ instance: MinecraftInstance) -> some View {
        InstanceSettingsEmptyStateCard(
            title: emptyTitle,
            description: emptyDescription,
            primaryTitle: emptyPrimaryActionTitle,
            secondaryTitle: emptySecondaryActionTitle,
            tertiaryTitle: emptyTertiaryActionTitle,
            primaryAction: { performEmptyPrimaryAction(instance) },
            secondaryAction: emptySecondaryActionTitle == nil ? nil : { performEmptySecondaryAction(instance) },
            tertiaryAction: emptyTertiaryActionTitle == nil ? nil : { openFolder(instance) }
        )
    }

    private func actionCard(_ instance: MinecraftInstance) -> some View {
        MyCard("", foldable: false, titled: false, padding: 14) {
            HStack(spacing: 12) {
                MyButton("打开文件夹") { openFolder(instance) }
                    .frame(width: primaryButtonWidth)
                if showImportButton {
                    MyButton("从文件安装") { `import`(instance) }
                        .frame(width: primaryButtonWidth)
                }
                if let route = downloadRoute() {
                    MyButton("下载新资源") {
                        AppRouter.shared.setRoot(.download)
                        AppRouter.shared.append(route)
                    }
                    .frame(width: primaryButtonWidth)
                }
                MyButton("全选") {
                    selectedFiles = Set(displayedFiles.map(\.id))
                    hint("已选中 \(displayedFiles.count) 个\(title)", type: .finish)
                }
                .frame(width: primaryButtonWidth)
                MyButton("导出信息") { exportInfo() }
                    .frame(width: primaryButtonWidth)
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
                        ForEach(ResourceSortOption.allCases) { option in
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
                        MyText("没有找到匹配的\(title)。", size: 13)
                        MyText("试试搜索其它名称，或者检查 \(folderName) 文件夹中的文件名是否正确。", size: 11.5, color: .colorGray3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                } else {
                    ForEach(displayedFiles) { file in
                        ResourceListRow(
                            file: file,
                            selected: selectedFiles.contains(file.id),
                            subtitle: resourceSubtitle(for: file),
                            showDetails: { Task { await showDetails(for: file) } },
                            revealInFinder: { revealInFinder(file) },
                            removeAction: { Task { await remove(file) } },
                            rowTapAction: { toggleSelection(file) }
                        )
                    }
                }
            }
        }
    }

    private var emptyPrimaryActionTitle: String {
        showImportButton ? importButtonText : quickOpenButtonText
    }

    private var emptySecondaryActionTitle: String? {
        if downloadRoute() != nil {
            return emptyDownloadButtonText
        }
        if showImportButton && showEmptyOpenFolderButton {
            return quickOpenButtonText
        }
        return nil
    }

    private var emptyTertiaryActionTitle: String? {
        if downloadRoute() != nil, showEmptyOpenFolderButton {
            return "打开文件夹"
        }
        return nil
    }

    private func performEmptyPrimaryAction(_ instance: MinecraftInstance) {
        if showImportButton {
            `import`(instance)
        } else {
            openFolder(instance)
        }
    }

    private func performEmptySecondaryAction(_ instance: MinecraftInstance) {
        if let route = downloadRoute() {
            AppRouter.shared.setRoot(.download)
            AppRouter.shared.append(route)
        } else {
            openFolder(instance)
        }
    }

    private func folderURL(_ instance: MinecraftInstance) -> URL {
        instance.runningDirectory.appending(path: folderName)
    }

    private func openFolder(_ instance: MinecraftInstance) {
        let url = folderURL(instance)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.open(url)
        } catch {
            hint("打开文件夹失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func `import`(_ instance: MinecraftInstance) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = allowedTypes
        panel.title = "选择要导入的\(title)文件"
        guard panel.runModal() == .OK else { return }
        let folder = folderURL(instance)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for source in panel.urls {
                let destination = folder.appending(path: source.lastPathComponent)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: source, to: destination)
            }
            hint("导入成功", type: .finish)
            reloadFiles()
        } catch {
            hint("导入失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func reloadFiles() {
        guard let instance else { return }
        let folder = folderURL(instance)
        let list = InstanceFileBrowserService.resourceFileEntries(at: folder)
        let items = list.map { entry in
            let metadata = InstancePageLoader.resourcePreviewMetadata(at: entry.url)
            return ResourceFileItem(
                id: entry.url,
                url: entry.url,
                modifiedAt: entry.modifiedAt,
                byteSize: entry.byteSize,
                metadataDescription: metadata.description,
                icon: metadata.icon,
                remoteIconURL: nil
            )
        }
        files = items
        selectedFiles = selectedFiles.intersection(Set(files.map(\.id)))
        guard let remoteProjectType else { return }
        reloadGeneration += 1
        let generation = reloadGeneration
        Task {
            await enrichRemoteIcons(for: items, generation: generation, expectedType: remoteProjectType)
        }
    }

    private func enrichRemoteIcons(for items: [ResourceFileItem], generation: Int, expectedType: ModrinthProjectType) async {
        let iconURLs = await InstanceRemoteProjectIconResolver.shared.iconURLs(for: items.map(\.url), expectedType: expectedType)
        guard !iconURLs.isEmpty else { return }
        await MainActor.run {
            guard reloadGeneration == generation else { return }
            files = files.map { item in
                item.withRemoteIconURL(iconURLs[item.url] ?? item.remoteIconURL)
            }
        }
    }

    private func remove(_ item: ResourceFileItem) async {
        let confirmed = await MessageBoxManager.shared.showConfirmAsync(
            title: "确认删除",
            content: "确定要删除\(title) \(item.name) 吗？此操作不可恢复。",
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
            reloadFiles()
        } catch {
            hint("删除失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func toggleSelection(_ item: ResourceFileItem) {
        if selectedFiles.contains(item.id) {
            selectedFiles.remove(item.id)
        } else {
            selectedFiles.insert(item.id)
        }
    }

    private func revealInFinder(_ item: ResourceFileItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    private func exportInfo() {
        let exportItems = selectedFiles.isEmpty ? displayedFiles : displayedFiles.filter { selectedFiles.contains($0.id) }
        guard !exportItems.isEmpty else {
            hint("当前没有可导出的\(title)信息", type: .info)
            return
        }

        let panel = NSSavePanel()
        panel.title = "导出\(title)信息"
        panel.nameFieldStringValue = "\(title)列表-\(instance?.name ?? id).txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let content = exportItems.map { item in
            [
                "名称：\(item.name)",
                "大小：\(InstancePageLoader.fileSizeString(item.byteSize))",
                "修改时间：\(item.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知")",
                "路径：\(item.url.path)"
            ].joined(separator: "\n")
        }.joined(separator: "\n\n") + "\n"

        do {
            try content.write(to: destination, atomically: true, encoding: .utf8)
            hint("已导出 \(exportItems.count) 个\(title)的信息", type: .finish)
        } catch {
            hint("导出失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func showDetails(for item: ResourceFileItem) async {
        let content = [
            "名称：\(item.name)",
            "大小：\(InstancePageLoader.fileSizeString(item.byteSize))",
            "最后修改：\(item.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知")",
            "路径：\(item.url.path)"
        ].joined(separator: "\n")
        await MessageBoxManager.shared.showAlertAsync(title: "\(title)详情", content: content)
    }

    private func downloadRoute() -> AppRoute? {
        switch title {
        case "模组": return .modDownload
        case "资源包": return .resourcepackDownload
        case "光影包": return .shaderpackDownload
        default: return nil
        }
    }

    private func resourceSubtitle(for file: ResourceFileItem) -> String {
        let detail = "\(InstancePageLoader.fileSizeString(file.byteSize)) · \(file.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知时间")"
        if let metadataDescription = file.metadataDescription, !metadataDescription.isEmpty {
            return "\(metadataDescription) · \(detail)"
        }
        return detail
    }

    private func compareFiles(lhs: ResourceFileItem, rhs: ResourceFileItem) -> Bool {
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

struct InstanceSchematicsPage: View {
    private enum ResourceSortOption: String, CaseIterable, Identifiable {
        case fileName = "资源名称"
        case modifiedAt = "修改时间"

        var id: String { rawValue }
        var label: String { rawValue }
    }

    let id: String
    @State private var instance: MinecraftInstance?
    @State private var files: [ResourceFileItem] = []
    @State private var selectedFiles: Set<URL> = []
    @State private var query: String = ""
    @State private var sortOption: ResourceSortOption = .fileName
    @State private var currentFolderURL: URL?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedFiles: [ResourceFileItem] {
        let keyword = trimmedQuery.lowercased()
        let filtered = keyword.isEmpty ? files : files.filter { $0.name.lowercased().contains(keyword) }
        return filtered.sorted { compareFiles(lhs: $0, rhs: $1) }
    }

    private var rootFolderURL: URL? {
        instance.map { $0.runningDirectory.appending(path: "schematics") }
    }

    private var isAtRootFolder: Bool {
        currentFolderURL == nil
    }

    private var currentDisplayFolderURL: URL? {
        currentFolderURL ?? rootFolderURL
    }

    private var schematicFolderExists: Bool {
        guard let rootFolderURL else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: rootFolderURL.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    var body: some View {
        InstanceSettingsBackground {
            if let instance {
                if !schematicFolderExists {
                    unavailableState
                } else if files.isEmpty {
                    emptyState(instance)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            InstanceSettingsSearchBar(placeholder: "搜索资源 名称 / 描述 / 标签", text: $query)
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
            reloadFiles()
        }
    }

    private var unavailableState: some View {
        InstanceSettingsEmptyStateCard(
            title: "该实例不可用投影原理图",
            description: "你可能需要先安装投影 Mod，如果已经安装过了投影 Mod 请先启动一次游戏。\n也可能是你选择错了实例，请点击实例选择按钮切换实例。",
            primaryTitle: "下载投影 Mod",
            secondaryTitle: "实例选择",
            tertiaryTitle: nil,
            primaryAction: {
                AppRouter.shared.setRoot(.download)
                AppRouter.shared.append(.modDownload)
            },
            secondaryAction: {
                openInstanceSelection()
            },
            tertiaryAction: nil
        )
    }

    private func emptyState(_ instance: MinecraftInstance) -> some View {
        InstanceSettingsEmptyStateCard(
            title: isAtRootFolder ? "尚未安装资源" : "该文件夹为空",
            description: isAtRootFolder ? "你可以从已经下载的文件安装资源。\n如果你已经安装了资源，可能是版本和隔离设置有误，请在设置中调整版本和隔离选项。" : "你可以从已经下载好的文件安装资源",
            primaryTitle: isAtRootFolder ? "从文件安装资源" : "返回上一级",
            secondaryTitle: isAtRootFolder ? "打开文件夹" : "从文件安装资源",
            tertiaryTitle: nil,
            primaryAction: {
                if isAtRootFolder {
                    `import`(instance)
                } else {
                    goBackToParentFolder()
                }
            },
            secondaryAction: {
                if isAtRootFolder {
                    openFolder(instance)
                } else {
                    `import`(instance)
                }
            },
            tertiaryAction: nil
        )
    }

    private func actionCard(_ instance: MinecraftInstance) -> some View {
        MyCard("", foldable: false, titled: false, padding: 14) {
            HStack(spacing: 12) {
                if !isAtRootFolder {
                    MyButton("返回上级") { goBackToParentFolder() }
                        .frame(width: 88)
                }
                MyButton("打开文件夹") { openFolder(instance) }
                    .frame(width: 88)
                MyButton("从文件安装") { `import`(instance) }
                    .frame(width: 88)
                MyButton("全选") {
                    selectedFiles = Set(displayedFiles.map(\.id))
                    hint("已选中 \(displayedFiles.count) 个投影原理图", type: .finish)
                }
                .frame(width: 88)
                MyButton("导出信息") { exportInfo() }
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
                        ForEach(ResourceSortOption.allCases) { option in
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
                        MyText("没有找到匹配的投影原理图。", size: 13)
                        MyText("试试搜索其它名称，或者检查 schematics 文件夹中的文件名是否正确。", size: 11.5, color: .colorGray3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                } else {
                    ForEach(displayedFiles) { file in
                        ResourceListRow(
                            file: file,
                            selected: selectedFiles.contains(file.id),
                            subtitle: schematicSubtitle(for: file),
                            showDetails: { Task { await showDetails(for: file) } },
                            revealInFinder: { revealInFinder(file) },
                            removeAction: { Task { await remove(file) } },
                            rowTapAction: { toggleSelection(file) }
                        )
                    }
                }
            }
        }
    }

    private func folderURL(_ instance: MinecraftInstance) -> URL {
        currentDisplayFolderURL ?? instance.runningDirectory.appending(path: "schematics")
    }

    private func openFolder(_ instance: MinecraftInstance) {
        let url = folderURL(instance)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.open(url)
        } catch {
            hint("打开文件夹失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func `import`(_ instance: MinecraftInstance) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.data, .zip]
        panel.title = "选择要导入的投影原理图文件"
        guard panel.runModal() == .OK else { return }
        let folder = folderURL(instance)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for source in panel.urls {
                let destination = folder.appending(path: source.lastPathComponent)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: source, to: destination)
            }
            hint("导入成功", type: .finish)
            reloadFiles()
        } catch {
            hint("导入失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func reloadFiles() {
        guard let instance else { return }
        let folder = folderURL(instance)
        let list = InstanceFileBrowserService.resourceFileEntries(at: folder)
        files = list.map { entry in
            let metadata = InstancePageLoader.resourcePreviewMetadata(at: entry.url)
            return ResourceFileItem(
                id: entry.url,
                url: entry.url,
                modifiedAt: entry.modifiedAt,
                byteSize: entry.byteSize,
                metadataDescription: metadata.description,
                icon: metadata.icon,
                remoteIconURL: nil
            )
        }
        selectedFiles = selectedFiles.intersection(Set(files.map(\.id)))
    }

    private func remove(_ item: ResourceFileItem) async {
        let confirmed = await MessageBoxManager.shared.showConfirmAsync(
            title: "确认删除",
            content: "确定要删除投影原理图 \(item.name) 吗？此操作不可恢复。",
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
            reloadFiles()
        } catch {
            hint("删除失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func toggleSelection(_ item: ResourceFileItem) {
        if isDirectory(item.url) {
            enterFolder(item.url)
            return
        }
        if selectedFiles.contains(item.id) {
            selectedFiles.remove(item.id)
        } else {
            selectedFiles.insert(item.id)
        }
    }

    private func revealInFinder(_ item: ResourceFileItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    private func exportInfo() {
        let exportItems = selectedFiles.isEmpty ? displayedFiles : displayedFiles.filter { selectedFiles.contains($0.id) }
        guard !exportItems.isEmpty else {
            hint("当前没有可导出的投影原理图信息", type: .info)
            return
        }

        let panel = NSSavePanel()
        panel.title = "导出投影原理图信息"
        panel.nameFieldStringValue = "投影原理图列表-\(instance?.name ?? id).txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let content = exportItems.map { item in
            [
                "名称：\(item.name)",
                "大小：\(InstancePageLoader.fileSizeString(item.byteSize))",
                "修改时间：\(item.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知")",
                "路径：\(item.url.path)"
            ].joined(separator: "\n")
        }.joined(separator: "\n\n") + "\n"

        do {
            try content.write(to: destination, atomically: true, encoding: .utf8)
            hint("已导出 \(exportItems.count) 个投影原理图的信息", type: .finish)
        } catch {
            hint("导出失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func showDetails(for item: ResourceFileItem) async {
        let content = [
            "名称：\(item.name)",
            "大小：\(InstancePageLoader.fileSizeString(item.byteSize))",
            "最后修改：\(item.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知")",
            "路径：\(item.url.path)"
        ].joined(separator: "\n")
        await MessageBoxManager.shared.showAlertAsync(title: "投影原理图详情", content: content)
    }

    private func schematicSubtitle(for file: ResourceFileItem) -> String {
        if isDirectory(file.url) {
            return "文件夹"
        }
        let typeName: String
        switch file.url.pathExtension.lowercased() {
        case "litematic": typeName = "Litematic"
        case "schem": typeName = "Schem"
        case "schematic": typeName = "Schematic"
        case "nbt": typeName = "原版结构"
        default: typeName = "原理图"
        }
        return "\(typeName)  \(file.displayName)"
    }

    private func compareFiles(lhs: ResourceFileItem, rhs: ResourceFileItem) -> Bool {
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

    private func openInstanceSelection() {
        AppRouter.shared.setRoot(.launch)
        if let repository = InstanceManager.shared.currentRepository {
            AppRouter.shared.append(.instanceList(.init(repository: repository)))
        }
    }

    private func enterFolder(_ url: URL) {
        currentFolderURL = url
        reloadFiles()
    }

    private func goBackToParentFolder() {
        guard let currentURL = currentFolderURL, let rootFolderURL else { return }
        let normalizedRoot = rootFolderURL.standardizedFileURL.path
        let parent = currentURL.deletingLastPathComponent().standardizedFileURL
        currentFolderURL = parent.path == normalizedRoot ? nil : parent
        reloadFiles()
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}

private struct ResourceListRow: View {
    let file: ResourceFileItem
    let selected: Bool
    let subtitle: String
    let showDetails: () -> Void
    let revealInFinder: () -> Void
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

                InstanceSettingsPreviewIcon(
                    image: file.icon,
                    remoteImageURL: file.remoteIconURL,
                    fileURL: file.url,
                    size: .init(width: 32, height: 32),
                    cornerRadius: 6,
                    fallbackImageResource: fallbackImageResource
                )

                VStack(alignment: .leading, spacing: 2) {
                    MyText(file.displayName, size: 13)
                        .lineLimit(1)
                    MyText(subtitle, size: 11, color: .colorGray3)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if hovered {
                    HStack(spacing: 12) {
                        InstanceSettingsHoverActionButton(systemImage: "info.circle", color: .color3, help: "详情", action: showDetails)
                        InstanceSettingsHoverActionButton(systemImage: "folder", color: .color3, help: "在访达中显示", action: revealInFinder)
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

private extension ResourceListRow {
    var fallbackImageResource: ImageResource {
        let path = file.url.path.lowercased()
        if path.contains("shaderpacks") {
            return .iconSun
        }
        if path.contains("schematics") {
            return .iconBox
        }
        return .iconPicture
    }
}
