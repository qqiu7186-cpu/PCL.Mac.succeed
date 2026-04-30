import SwiftUI
import Core
import UniformTypeIdentifiers
import AppKit

private struct ResourceFileItem: Identifiable {
    let id: URL
    let url: URL
    let modifiedAt: Date?
    let byteSize: Int64

    var name: String { url.lastPathComponent }
}

struct InstanceFolderResourcePage: View {
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
        listActionButtonWidth: CGFloat = 90
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
    }

    @State private var instance: MinecraftInstance?
    @State private var files: [ResourceFileItem] = []
    @State private var selectedFiles: Set<URL> = []

    var body: some View {
        CardContainer {
            if let instance {
                if !(hideTopCardWhenEmpty && files.isEmpty) {
                    MyCard(title, foldable: false) {
                        VStack(alignment: .leading, spacing: 10) {
                            MyText("你可以在这里管理当前实例的\(title)文件。", size: 12, color: .colorGray3)
                            HStack(spacing: 15) {
                                MyButton(quickOpenButtonText) {
                                    openFolder(instance)
                                }
                                .frame(width: primaryButtonWidth)
                                if showImportButton {
                                    MyButton(importButtonText) {
                                        `import`(instance)
                                    }
                                    .frame(width: primaryButtonWidth)
                                }
                                if let route = downloadRoute() {
                                    MyButton("下载新资源") {
                                        AppRouter.shared.setRoot(.download)
                                        AppRouter.shared.append(route)
                                    }
                                    .frame(width: primaryButtonWidth)
                                }
                                Spacer()
                            }
                            .frame(height: 35)
                            HStack(spacing: 15) {
                                MyButton("全选") {
                                    selectedFiles = Set(files.map(\.id))
                                }
                                .frame(width: 90)
                                MyButton("取消选择") {
                                    selectedFiles.removeAll()
                                }
                                .frame(width: 90)
                                MyButton("删除所选", type: .red) {
                                    removeSelected()
                                }
                                .frame(width: 90)
                                Spacer()
                            }
                            .frame(height: 35)
                        }
                    }
                }

                MyCard(listCardTitle(), foldable: false) {
                    if files.isEmpty {
                        VStack(spacing: 10) {
                            MyText(emptyTitle, size: 18, color: .colorGray3)
                            MyText(emptyDescription, size: 12, color: .colorGray3)
                            if showEmptyOpenFolderButton || downloadRoute() != nil {
                                HStack(spacing: 15) {
                                    Spacer()
                                    if showEmptyOpenFolderButton {
                                        MyButton(quickOpenButtonText) {
                                            openFolder(instance)
                                        }
                                        .frame(width: primaryButtonWidth)
                                    }
                                    if let route = downloadRoute() {
                                        MyButton(emptyDownloadButtonText) {
                                            AppRouter.shared.setRoot(.download)
                                            AppRouter.shared.append(route)
                                        }
                                        .frame(width: primaryButtonWidth)
                                    }
                                    Spacer()
                                }
                                .padding(.top, 8)
                                .frame(height: 35)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(files) { file in
                                MyListItem {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            MyText(file.name)
                                            MyText("\(InstancePageLoader.fileSizeString(file.byteSize)) · \(file.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知时间")", size: 12, color: .colorGray3)
                                        }
                                        Spacer()
                                        MyButton(selectedFiles.contains(file.id) ? "取消" : "选择") {
                                            toggleSelection(file)
                                        }
                                        .frame(width: listActionButtonWidth)
                                        MyButton("打开") {
                                            NSWorkspace.shared.open(file.url)
                                        }
                                        .frame(width: listActionButtonWidth)
                                        MyButton("删除", type: .red) {
                                            remove(file)
                                        }
                                        .frame(width: listActionButtonWidth)
                                    }
                                }
                            }
                        }
                    }
                }
                .cardIndex(1)
            } else {
                MyLoading(viewModel: .init(text: "未找到可配置的实例"))
            }
        }
        .task(id: id) {
            instance = InstancePageLoader.loadInstance(id)
            reloadFiles()
        }
    }

    private func folderURL(_ instance: MinecraftInstance) -> URL {
        instance.runningDirectory.appending(path: folderName)
    }

    private func openFolder(_ instance: MinecraftInstance) {
        let url = folderURL(instance)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    private func `import`(_ instance: MinecraftInstance) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = allowedTypes
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
            ResourceFileItem(id: entry.url, url: entry.url, modifiedAt: entry.modifiedAt, byteSize: entry.byteSize)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func remove(_ item: ResourceFileItem) {
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

    private func removeSelected() {
        guard !selectedFiles.isEmpty else {
            hint("请先选择文件", type: .info)
            return
        }
        for file in files where selectedFiles.contains(file.id) {
            try? FileManager.default.removeItem(at: file.url)
        }
        hint("已删除所选文件", type: .finish)
        selectedFiles.removeAll()
        reloadFiles()
    }

    private func downloadRoute() -> AppRoute? {
        switch title {
        case "模组": return .modDownload
        case "资源包": return .resourcepackDownload
        case "光影包": return .shaderpackDownload
        case "投影原理图": return .modDownload
        default: return nil
        }
    }

    private func listCardTitle() -> String {
        if hideListCountWhenEmpty, files.isEmpty {
            return "列表"
        }
        return "列表（\(files.count)）"
    }
}
