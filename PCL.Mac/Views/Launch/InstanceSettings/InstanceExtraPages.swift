import SwiftUI
import Core
import ZIPFoundation
import UniformTypeIdentifiers
import AppKit

private enum InstancePageLoader {
    static func loadInstance(_ id: String) -> MinecraftInstance? {
        return try? InstanceManager.shared.loadInstance(id)
    }

    static func fileSizeString(_ byteSize: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }

    static func folderSize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }
}

struct InstanceOverviewPage: View {
    let id: String
    @State private var instance: MinecraftInstance?
    @State private var localDesc: String = ""
    @State private var isFavorite: Bool = false

    var body: some View {
        CardContainer {
            if let instance {
                MyCard("", titled: false, padding: 10) {
                    MyListItem(.init(
                        image: instance.modLoader?.icon ?? "GrassBlock",
                        name: instance.name,
                        description: "\(instance.version.description)\(instance.modLoader.map { "，\($0)" } ?? "")"
                    ))
                }

                MyCard("", titled: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        MyText("你可以在这里管理实例名称、描述和常用目录。", size: 12, color: .colorGray3)
                        HStack(spacing: 15) {
                            MyButton("修改实例名") {
                                MessageBoxManager.shared.showInput(title: "修改实例名", initialContent: instance.name) { text in
                                    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                                    do {
                                        let oldID = instance.name
                                        let renamed = try InstanceManager.shared.renameInstance(instance, to: text)
                                        self.instance = renamed
                                        migrateInstanceMeta(from: oldID, to: renamed.name)
                                        AppRouter.shared.replaceInstanceID(from: oldID, to: renamed.name)
                                        hint("实例名已修改", type: .finish)
                                    } catch {
                                        hint("修改失败：\(error.localizedDescription)", type: .critical)
                                    }
                                }
                            }
                            .frame(width: 120)
                            MyButton("修改实例描述") {
                                MessageBoxManager.shared.showInput(title: "修改实例描述", initialContent: localDesc, placeholder: "输入描述") { text in
                                    localDesc = text ?? ""
                                    UserDefaults.standard.set(localDesc, forKey: "instance.meta.desc.\(id)")
                                }
                            }
                            .frame(width: 120)
                            MyButton(isFavorite ? "取消收藏" : "加入收藏夹") {
                                isFavorite.toggle()
                                UserDefaults.standard.set(isFavorite, forKey: "instance.meta.favorite.\(id)")
                            }
                            .frame(width: 120)
                            Spacer()
                        }
                        .frame(height: 35)
                        HStack(spacing: 15) {
                            MyButton("打开实例文件夹") {
                                NSWorkspace.shared.open(instance.runningDirectory)
                            }
                            .frame(width: 120)
                            MyButton("打开存档文件夹") {
                                openManagedFolder(instance.runningDirectory.appending(path: "saves"))
                            }
                            .frame(width: 120)
                            MyButton("打开 mods 文件夹") {
                                openManagedFolder(instance.runningDirectory.appending(path: "mods"))
                            }
                            .frame(width: 120)
                            Spacer()
                        }
                        .frame(height: 35)
                    }
                }
                .cardIndex(1)

                MyCard("实例管理", foldable: false) {
                    MyText("以下操作会影响当前实例配置与文件，请谨慎执行。", size: 12, color: .colorGray3)
                    HStack(spacing: 15) {
                        MyButton("检查资源文件") {
                            checkGameFiles(instance)
                        }
                        .frame(width: 120)
                        MyButton("导出启动脚本") {
                            exportLaunchScript(instance)
                        }
                        .frame(width: 120)
                        MyButton("测试游戏") {
                            guard let current = self.instance,
                                  let repository = InstanceManager.shared.currentRepository,
                                  let account = AccountViewModel().currentAccount else {
                                hint("缺少可用账号或实例，无法测试启动", type: .critical)
                                return
                            }
                            InstanceManager.shared.launch(current, account, in: repository)
                            AppRouter.shared.append(.tasks)
                        }
                        .frame(width: 120)
                        MyButton("重置", type: .red) {
                            MessageBoxManager.shared.showText(
                                title: "确认重置",
                                content: "重置将删除该实例的 .clconfig 配置文件，确定继续吗？",
                                level: .error,
                                .no(),
                                .yes(type: .red)
                            ) { result in
                                guard result == 1 else { return }
                                guard let current = self.instance else { return }
                                let configURL = current.runningDirectory.appending(path: ".clconfig.json")
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
                        .frame(width: 120)
                        MyButton("删除实例", type: .red) {
                            MessageBoxManager.shared.showText(
                                title: "确认删除",
                                content: "删除实例后不可恢复，确定继续？",
                                level: .error,
                                .no(),
                                .yes(type: .red)
                            ) { result in
                                guard result == 1 else { return }
                                guard let current = self.instance else { return }
                                do {
                                    try InstanceManager.shared.deleteInstance(current)
                                    AppRouter.shared.removeLast()
                                } catch {
                                    hint("删除失败：\(error.localizedDescription)", type: .critical)
                                }
                            }
                        }
                        .frame(width: 120)
                        Spacer()
                    }
                    .frame(height: 35)
                }
                .cardIndex(2)
            } else {
                MyLoading(viewModel: .init(text: "未找到可配置的实例"))
            }
        }
        .task(id: id) {
            instance = InstancePageLoader.loadInstance(id)
            localDesc = UserDefaults.standard.string(forKey: "instance.meta.desc.\(id)") ?? ""
            isFavorite = UserDefaults.standard.bool(forKey: "instance.meta.favorite.\(id)")
        }
    }

    private func migrateInstanceMeta(from oldID: String, to newID: String) {
        guard oldID != newID else { return }
        let defaults = UserDefaults.standard
        let oldDescKey = "instance.meta.desc.\(oldID)"
        let oldFavoriteKey = "instance.meta.favorite.\(oldID)"
        let newDescKey = "instance.meta.desc.\(newID)"
        let newFavoriteKey = "instance.meta.favorite.\(newID)"

        if let desc = defaults.string(forKey: oldDescKey) {
            defaults.set(desc, forKey: newDescKey)
            defaults.removeObject(forKey: oldDescKey)
        }
        if defaults.object(forKey: oldFavoriteKey) != nil {
            defaults.set(defaults.bool(forKey: oldFavoriteKey), forKey: newFavoriteKey)
            defaults.removeObject(forKey: oldFavoriteKey)
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

    private func openManagedFolder(_ url: URL) {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.open(url)
        } catch {
            hint("打开文件夹失败：\(error.localizedDescription)", type: .critical)
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

        let panel = NSSavePanel()
        panel.title = "导出启动脚本"
        panel.nameFieldStringValue = "启动-\(instance.name).command"
        panel.allowedContentTypes = [.shellScript]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            let script = buildLaunchScript(instance: instance, account: account, repository: repository, runtime: runtime)
            guard let scriptData = script.data(using: .utf8) else {
                hint("导出启动脚本失败：无法编码脚本内容", type: .critical)
                return
            }
            try scriptData.write(to: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
            hint("启动脚本导出成功", type: .finish)
            NSWorkspace.shared.open(destination.deletingLastPathComponent())
        } catch {
            hint("导出启动脚本失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func buildLaunchScript(
        instance: MinecraftInstance,
        account: Account,
        repository: MinecraftRepository,
        runtime: JavaRuntime
    ) -> String {
        let manifest = instance.manifest
        let classpath = (manifest.getLibraries().compactMap { $0.artifact?.path }.map { repository.librariesURL.appending(path: $0).path }
            + [instance.runningDirectory.appending(path: "\(instance.runningDirectory.lastPathComponent).jar").path])
            .joined(separator: ":")
        let accessToken = account.accessToken()
        var launchOptions: LaunchOptions = .init()
        launchOptions.profile = account.profile
        launchOptions.accessToken = accessToken
        launchOptions.runningDirectory = instance.runningDirectory
        launchOptions.repository = repository
        launchOptions.manifest = manifest
        launchOptions.javaRuntime = runtime
        launchOptions.javaReleaseType = runtime.releaseType
        launchOptions.memory = instance.config.jvmHeapSize
        let values: [String: String] = [
            "natives_directory": instance.runningDirectory.appending(path: "natives").path,
            "launcher_name": "PCL.Mac",
            "launcher_version": Metadata.appVersion,
            "classpath_separator": ":",
            "library_directory": repository.librariesURL.path,
            "auth_player_name": account.profile.name,
            "version_name": instance.runningDirectory.lastPathComponent,
            "game_directory": instance.runningDirectory.path,
            "assets_root": repository.assetsURL.path,
            "assets_index_name": manifest.assetIndex.id,
            "auth_uuid": UUIDUtils.string(of: account.profile.id, withHyphens: false),
            "auth_access_token": accessToken,
            "user_type": launchOptions.userType,
            "version_type": "PCL.Mac",
            "user_properties": launchOptions.userProperties,
            "classpath": classpath
        ]
        let args = MinecraftLauncher.buildLaunchArguments(
            manifest: manifest,
            values: values,
            options: launchOptions
        )

        let escapedArgs = args.map(shellEscape).joined(separator: " ")
        return "#!/bin/zsh\ncd \(shellEscape(instance.runningDirectory.path))\n\(shellEscape(runtime.executableURL.path)) \(escapedArgs)\n"
    }

    private func shellEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}

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

                    MyCard(modListTitle(), foldable: false)
                    {
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
        let list = (try? FileManager.default.contentsOfDirectory(at: modsURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
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

private struct SaveItem: Identifiable {
    let id: URL
    let url: URL
    let modifiedAt: Date?
    let byteSize: Int64

    var name: String { url.lastPathComponent }
}

private struct SaveBackupItem: Identifiable {
    let id: URL
    let url: URL
    let modifiedAt: Date?
    let byteSize: Int64

    var name: String { url.lastPathComponent }
}

private struct DatapackItem: Identifiable {
    let id: URL
    let url: URL
    let modifiedAt: Date?
    let byteSize: Int64

    var name: String { url.lastPathComponent }
}

private enum SaveConflictPolicy {
    case replace
    case skip
    case rename
}

private enum SaveSortOption: CaseIterable {
    case nameAsc
    case nameDesc
    case modifiedDesc
    case modifiedAsc

    var title: String {
        switch self {
        case .nameAsc: "名称（A-Z）"
        case .nameDesc: "名称（Z-A）"
        case .modifiedDesc: "修改时间（新→旧）"
        case .modifiedAsc: "修改时间（旧→新）"
        }
    }
}

struct InstanceSavesPage: View {
    let id: String
    @State private var instance: MinecraftInstance?
    @State private var saves: [SaveItem] = []
    @State private var backups: [SaveBackupItem] = []
    @State private var saveQuery: String = ""
    @State private var saveSortOption: SaveSortOption = .modifiedDesc
    @State private var selectedDatapackSaveURL: URL?
    @State private var datapacks: [DatapackItem] = []

    private var displayedSaves: [SaveItem] {
        let keyword = saveQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = keyword.isEmpty ? saves : saves.filter { $0.name.lowercased().contains(keyword) }
        return filtered.sorted { lhs, rhs in
            switch saveSortOption {
            case .nameAsc:
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .nameDesc:
                lhs.name.localizedStandardCompare(rhs.name) == .orderedDescending
            case .modifiedDesc:
                (lhs.modifiedAt ?? .distantPast) > (rhs.modifiedAt ?? .distantPast)
            case .modifiedAsc:
                (lhs.modifiedAt ?? .distantPast) < (rhs.modifiedAt ?? .distantPast)
            }
        }
    }

    var body: some View {
        CardContainer {
            if let instance {
                MySearchBox(placeholder: "搜索存档") { keyword in
                    saveQuery = keyword
                }

                MyCard("存档", foldable: false) {
                    HStack(spacing: 15) {
                        MyButton("打开 saves 文件夹") {
                            openSavesFolder(instance)
                        }
                        .frame(width: 120)
                        MyButton("导入存档压缩包") {
                            importSaveArchive()
                        }
                        .frame(width: 120)
                        MyButton("下载数据包") {
                            AppRouter.shared.setRoot(.download)
                            AppRouter.shared.append(.datapackDownload)
                        }
                        .frame(width: 120)
                        MyButton("排序：\(saveSortOption.title)") {
                            chooseSaveSortOption()
                        }
                        .frame(width: 120)
                        Spacer()
                    }
                    .frame(height: 35)
                }

                MyCard("存档列表（\(displayedSaves.count)/\(saves.count)）", foldable: false) {
                    if displayedSaves.isEmpty {
                        MyText("没有找到存档。", color: .colorGray3)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(displayedSaves) { save in
                                MyListItem {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            MyText(save.name)
                                            MyText("\(InstancePageLoader.fileSizeString(save.byteSize)) · \(save.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知时间")", size: 12, color: .colorGray3)
                                        }
                                        Spacer()
                                        MyButton("备份") {
                                            backup(save)
                                        }
                                        .frame(width: 90)
                                        MyButton("导出") {
                                            exportSave(save)
                                        }
                                        .frame(width: 90)
                                        MyButton("数据包") {
                                            selectSaveForDatapacks(save)
                                        }
                                        .frame(width: 90)
                                    }
                                }
                            }
                        }
                    }
                }
                .cardIndex(1)

                MyCard(datapackCardTitle(), foldable: false) {
                    if let selectedSave = selectedDatapackSave() {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 15) {
                                MyButton("打开数据包文件夹") {
                                    openDatapacksFolder(for: selectedSave)
                                }
                                .frame(width: 120)
                                MyButton("从文件导入") {
                                    importDatapack(for: selectedSave)
                                }
                                .frame(width: 120)
                                MyButton("刷新") {
                                    reloadDatapacks(for: selectedSave)
                                }
                                .frame(width: 90)
                                Spacer()
                            }
                            .frame(height: 35)
                            if datapacks.isEmpty {
                                MyText("该存档暂无数据包。", color: .colorGray3)
                            } else {
                                LazyVStack(spacing: 0) {
                                    ForEach(datapacks) { datapack in
                                        MyListItem {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    let modifiedText = datapack.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知时间"
                                                    MyText(datapack.name)
                                                    MyText("\(InstancePageLoader.fileSizeString(datapack.byteSize)) · \(modifiedText)", size: 12, color: .colorGray3)
                                                }
                                                Spacer()
                                                MyButton("打开") {
                                                    NSWorkspace.shared.open(datapack.url)
                                                }
                                                .frame(width: 90)
                                                MyButton("删除", type: .red) {
                                                    removeDatapack(datapack, for: selectedSave)
                                                }
                                                .frame(width: 90)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        MyText("请先在上方存档列表中点击“数据包”。", color: .colorGray3)
                    }
                }
                .cardIndex(2)

                MyCard("备份列表（\(backups.count)）", foldable: false) {
                    if backups.isEmpty {
                        MyText("没有备份。", color: .colorGray3)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(backups) { backup in
                                MyListItem {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            MyText(backup.name)
                                            MyText("\(InstancePageLoader.fileSizeString(backup.byteSize)) · \(backup.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知时间")", size: 12, color: .colorGray3)
                                        }
                                        Spacer()
                                        MyButton("恢复") {
                                            restore(backup)
                                        }
                                        .frame(width: 90)
                                        MyButton("导出") {
                                            exportBackup(backup)
                                        }
                                        .frame(width: 90)
                                    }
                                }
                            }
                        }
                    }
                }
                .cardIndex(2)
            } else {
                MyLoading(viewModel: .init(text: "未找到可配置的实例"))
            }
        }
        .task(id: id) {
            instance = InstancePageLoader.loadInstance(id)
            reloadSaves()
            if let selectedSave = selectedDatapackSave() {
                reloadDatapacks(for: selectedSave)
            }
        }
    }

    private func reloadSaves() {
        guard let instance else { return }
        let savesURL = instance.runningDirectory.appending(path: "saves")
        let list = (try? FileManager.default.contentsOfDirectory(at: savesURL, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        saves = list.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            guard values?.isDirectory == true else { return nil }
            return SaveItem(id: url, url: url, modifiedAt: values?.contentModificationDate, byteSize: InstancePageLoader.folderSize(at: url))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let backupsURL = instance.runningDirectory.appending(path: "PCL.Mac-backups").appending(path: "saves")
        let backupsList = (try? FileManager.default.contentsOfDirectory(at: backupsURL, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles])) ?? []
        backups = backupsList
            .filter { $0.pathExtension.lowercased() == "zip" }
            .map { url in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                return SaveBackupItem(id: url, url: url, modifiedAt: values?.contentModificationDate, byteSize: Int64(values?.fileSize ?? 0))
            }
            .sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }

        if let selectedDatapackSaveURL {
            if let selectedSave = saves.first(where: { $0.url == selectedDatapackSaveURL }) {
                reloadDatapacks(for: selectedSave)
            } else {
                self.selectedDatapackSaveURL = nil
                datapacks = []
            }
        }
    }

    private func backup(_ save: SaveItem) {
        guard let instance else { return }
        let backupsURL = instance.runningDirectory.appending(path: "PCL.Mac-backups").appending(path: "saves")
        do {
            try FileManager.default.createDirectory(at: backupsURL, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let fileName = "\(save.name.replacingOccurrences(of: "/", with: "_"))-\(formatter.string(from: Date())).zip"
            let zipURL = backupsURL.appending(path: fileName)
            if FileManager.default.fileExists(atPath: zipURL.path) {
                try FileManager.default.removeItem(at: zipURL)
            }
            try FileManager.default.zipItem(at: save.url, to: zipURL, shouldKeepParent: true)
            hint("已备份：\(fileName)", type: .finish)
            reloadSaves()
        } catch {
            hint("备份失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func exportSave(_ save: SaveItem) {
        let panel = NSSavePanel()
        panel.title = "导出存档"
        panel.nameFieldStringValue = "\(save.name).zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.zipItem(at: save.url, to: destination, shouldKeepParent: true)
            hint("导出成功", type: .finish)
        } catch {
            hint("导出失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func selectSaveForDatapacks(_ save: SaveItem) {
        selectedDatapackSaveURL = save.url
        reloadDatapacks(for: save)
    }

    private func selectedDatapackSave() -> SaveItem? {
        guard let selectedDatapackSaveURL else { return nil }
        return saves.first(where: { $0.url == selectedDatapackSaveURL })
    }

    private func datapackCardTitle() -> String {
        if let selectedSave = selectedDatapackSave() {
            return "数据包（\(selectedSave.name)）"
        }
        return "数据包"
    }

    private func datapacksDirectory(for save: SaveItem) -> URL {
        save.url.appending(path: "datapacks")
    }

    private func openDatapacksFolder(for save: SaveItem) {
        let datapacksURL = datapacksDirectory(for: save)
        do {
            try FileManager.default.createDirectory(at: datapacksURL, withIntermediateDirectories: true)
            NSWorkspace.shared.open(datapacksURL)
        } catch {
            hint("打开数据包文件夹失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func reloadDatapacks(for save: SaveItem) {
        let datapacksURL = datapacksDirectory(for: save)
        let list = (try? FileManager.default.contentsOfDirectory(
            at: datapacksURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        datapacks = list.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey])
            let isDirectory = values?.isDirectory == true
            let isZip = url.pathExtension.lowercased() == "zip"
            guard isDirectory || isZip else { return nil }
            let byteSize: Int64 = isDirectory ? InstancePageLoader.folderSize(at: url) : Int64(values?.fileSize ?? 0)
            return DatapackItem(id: url, url: url, modifiedAt: values?.contentModificationDate, byteSize: byteSize)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func importDatapack(for save: SaveItem) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.zip]
        panel.title = "导入数据包"
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let isDirectory = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        if !isDirectory, source.pathExtension.lowercased() != "zip" {
            hint("导入失败：仅支持 zip 文件或文件夹", type: .critical)
            return
        }

        let datapacksURL = datapacksDirectory(for: save)
        do {
            try FileManager.default.createDirectory(at: datapacksURL, withIntermediateDirectories: true)
            var destination = datapacksURL.appending(path: source.lastPathComponent)
            destination = uniqueDatapackDestination(base: destination)
            try FileManager.default.copyItem(at: source, to: destination)
            hint("导入数据包成功", type: .finish)
            reloadDatapacks(for: save)
        } catch {
            hint("导入数据包失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func removeDatapack(_ datapack: DatapackItem, for save: SaveItem) {
        MessageBoxManager.shared.showText(
            title: "确认删除",
            content: "删除后不可恢复，确定要删除数据包 \(datapack.name) 吗？",
            level: .error,
            .no(),
            .yes(type: .red)
        ) { result in
            guard result == 1 else { return }
            do {
                try FileManager.default.removeItem(at: datapack.url)
                hint("已删除数据包", type: .finish)
                reloadDatapacks(for: save)
            } catch {
                hint("删除失败：\(error.localizedDescription)", type: .critical)
            }
        }
    }

    private func uniqueDatapackDestination(base: URL) -> URL {
        let parent = base.deletingLastPathComponent()
        let fileName = base.deletingPathExtension().lastPathComponent
        let ext = base.pathExtension
        var index = 1
        var candidate = base
        while FileManager.default.fileExists(atPath: candidate.path) {
            let suffix = "-导入\(index)"
            if ext.isEmpty {
                candidate = parent.appending(path: "\(fileName)\(suffix)")
            } else {
                candidate = parent.appending(path: "\(fileName)\(suffix).\(ext)")
            }
            index += 1
        }
        return candidate
    }

    private func chooseSaveSortOption() {
        let options = SaveSortOption.allCases
        MessageBoxManager.shared.showList(
            title: "选择存档排序方式",
            items: options.map { .init(name: $0.title, description: nil) }
        ) { selectedIndex in
            guard let selectedIndex, options.indices.contains(selectedIndex) else { return }
            saveSortOption = options[selectedIndex]
        }
    }

    private func exportBackup(_ backup: SaveBackupItem) {
        let panel = NSSavePanel()
        panel.title = "导出备份"
        panel.nameFieldStringValue = backup.name
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: backup.url, to: destination)
            hint("导出成功", type: .finish)
        } catch {
            hint("导出失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func restore(_ backup: SaveBackupItem) {
        guard let instance else { return }
        let archiveURL = backup.url
        chooseConflictPolicy(for: archiveURL, operation: "恢复") { policy in
            guard let policy else { return }
            do {
                let savesURL = instance.runningDirectory.appending(path: "saves")
                try FileManager.default.createDirectory(at: savesURL, withIntermediateDirectories: true)
                let importedCount = try applySaveArchive(archiveURL, to: savesURL, policy: policy)
                if importedCount == 0 {
                    hint("恢复完成，但未发现可用存档目录", type: .info)
                } else {
                    hint("恢复成功：已处理 \(importedCount) 个存档", type: .finish)
                }
                reloadSaves()
            } catch {
                hint("恢复失败：\(error.localizedDescription)", type: .critical)
            }
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
        chooseConflictPolicy(for: source, operation: "导入") { policy in
            guard let policy else { return }
            do {
                let savesURL = instance.runningDirectory.appending(path: "saves")
                try FileManager.default.createDirectory(at: savesURL, withIntermediateDirectories: true)
                let importedCount = try applySaveArchive(source, to: savesURL, policy: policy)
                if importedCount == 0 {
                    hint("导入完成，但未发现可用存档目录", type: .info)
                } else {
                    hint("导入成功：已处理 \(importedCount) 个存档", type: .finish)
                }
                reloadSaves()
            } catch {
                hint("导入失败：\(error.localizedDescription)", type: .critical)
            }
        }
    }

    private func chooseConflictPolicy(
        for archiveURL: URL,
        operation: String,
        completion: @escaping (SaveConflictPolicy?) -> Void
    ) {
        let names = (try? detectSaveNames(in: archiveURL)) ?? []
        if names.isEmpty {
            completion(.replace)
            return
        }
        let preview = names.prefix(5).joined(separator: "、")
        let summary = names.count > 5 ? "\(preview) 等 \(names.count) 个" : preview
        MessageBoxManager.shared.showText(
            title: "\(operation)存档",
            content: "检测到压缩包内包含：\(summary)\n如果与现有存档重名，如何处理？",
            level: .info,
            buttons: [
                .init(id: 10, label: "覆盖", type: .red),
                .init(id: 11, label: "跳过重名", type: .normal),
                .init(id: 12, label: "自动重命名", type: .highlight),
                .no()
            ]
        ) { result in
            switch result {
            case 10: completion(.replace)
            case 11: completion(.skip)
            case 12: completion(.rename)
            default: completion(nil)
            }
        }
    }

    private func detectSaveNames(in archiveURL: URL) throws -> [String] {
        let archive = try Archive(url: archiveURL, accessMode: .read)
        let archiveBaseName = archiveURL.deletingPathExtension().lastPathComponent
        var topLevelNames: Set<String> = []
        var saveNamesFromSavesRoot: Set<String> = []
        var hasRootLevelDat = false
        for entry in archive {
            let normalized = entry.path.hasPrefix("/") ? String(entry.path.dropFirst()) : entry.path
            let components = normalized.split(separator: "/").map(String.init)
            guard let first = components.first, !first.isEmpty, first != "__MACOSX" else { continue }
            if components.count == 1, first.caseInsensitiveCompare("level.dat") == .orderedSame {
                hasRootLevelDat = true
            }
            if first.caseInsensitiveCompare("saves") == .orderedSame, components.count >= 2 {
                let saveName = components[1]
                if !saveName.isEmpty {
                    saveNamesFromSavesRoot.insert(saveName)
                    continue
                }
            }
            topLevelNames.insert(first)
        }
        if hasRootLevelDat { return [archiveBaseName] }
        if !saveNamesFromSavesRoot.isEmpty { return saveNamesFromSavesRoot.sorted() }
        return topLevelNames.sorted()
    }

    private func applySaveArchive(
        _ archiveURL: URL,
        to savesURL: URL,
        policy: SaveConflictPolicy
    ) throws -> Int {
        let tempRoot = URLConstants.tempURL.appending(path: "save-import-\(UUID().uuidString)")
        let extractionURL = tempRoot.appending(path: "extract")
        let backupURL = tempRoot.appending(path: "backup")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try FileManager.default.createDirectory(at: extractionURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: archiveURL, to: extractionURL)

        let candidates = try collectImportedSaveCandidates(from: extractionURL, archiveURL: archiveURL)
        if candidates.isEmpty { return 0 }

        var copiedTargets: [URL] = []
        var movedExistingPairs: [(backup: URL, original: URL)] = []

        do {
            for candidate in candidates {
                let source = candidate.sourceURL
                var destination = savesURL.appending(path: candidate.destinationName)
                let exists = FileManager.default.fileExists(atPath: destination.path)
                if exists {
                    switch policy {
                    case .skip:
                        continue
                    case .rename:
                        destination = uniqueSaveDestination(base: destination)
                    case .replace:
                        let movedBackup = backupURL.appending(path: "\(UUID().uuidString)-\(candidate.destinationName)")
                        try FileManager.default.moveItem(at: destination, to: movedBackup)
                        movedExistingPairs.append((backup: movedBackup, original: destination))
                    }
                }

                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: source, to: destination)
                copiedTargets.append(destination)
            }
            return copiedTargets.count
        } catch {
            for copied in copiedTargets {
                try? FileManager.default.removeItem(at: copied)
            }
            for pair in movedExistingPairs.reversed() {
                if FileManager.default.fileExists(atPath: pair.original.path) {
                    try? FileManager.default.removeItem(at: pair.original)
                }
                try? FileManager.default.moveItem(at: pair.backup, to: pair.original)
            }
            throw error
        }
    }

    private struct ImportedSaveCandidate {
        let sourceURL: URL
        let destinationName: String
    }

    private func collectImportedSaveCandidates(from extractionURL: URL, archiveURL: URL) throws -> [ImportedSaveCandidate] {
        let archiveBaseName = archiveURL.deletingPathExtension().lastPathComponent
        if FileManager.default.fileExists(atPath: extractionURL.appending(path: "level.dat").path) {
            return [.init(sourceURL: extractionURL, destinationName: archiveBaseName)]
        }

        let topLevel = try FileManager.default.contentsOfDirectory(
            at: extractionURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let filteredTopLevel = topLevel.filter { $0.lastPathComponent != "__MACOSX" }

        if filteredTopLevel.count == 1,
           let values = try? filteredTopLevel[0].resourceValues(forKeys: [.isDirectoryKey]),
           values.isDirectory == true,
           filteredTopLevel[0].lastPathComponent.caseInsensitiveCompare("saves") == .orderedSame {
            return try collectDirectories(from: filteredTopLevel[0]).map { .init(sourceURL: $0, destinationName: $0.lastPathComponent) }
        }

        return filteredTopLevel.filter { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory == true
        }.map { .init(sourceURL: $0, destinationName: $0.lastPathComponent) }
    }

    private func collectDirectories(from root: URL) throws -> [URL] {
        let children = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return children.filter { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory == true
        }
    }

    private func uniqueSaveDestination(base: URL) -> URL {
        let parent = base.deletingLastPathComponent()
        let name = base.lastPathComponent
        var index = 1
        var candidate = base
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parent.appending(path: "\(name)-导入\(index)")
            index += 1
        }
        return candidate
    }

    private func openSavesFolder(_ instance: MinecraftInstance) {
        let savesURL = instance.runningDirectory.appending(path: "saves")
        do {
            try FileManager.default.createDirectory(at: savesURL, withIntermediateDirectories: true)
            NSWorkspace.shared.open(savesURL)
        } catch {
            hint("打开 saves 文件夹失败：\(error.localizedDescription)", type: .critical)
        }
    }
}

struct InstanceServersPage: View {
    let id: String
    private let serverButtonWidth: CGFloat = 130
    @State private var instance: MinecraftInstance?
    @State private var errorMessage: String?
    @State private var hasServersDat: Bool = false

    var body: some View {
        CardContainer {
            if let instance {
                let serversDat = instance.runningDirectory.appending(path: "servers.dat")
                MyCard(hasServersDat ? "快捷操作" : "服务器", foldable: false) {
                    if hasServersDat {
                        VStack(alignment: .leading, spacing: 12) {
                            MyText("暂时没有找到服务器时，可先在游戏内添加，或在此处导入 servers.dat。", size: 12, color: .colorGray3)
                                .lineLimit(3)
                            HStack(spacing: 15) {
                                MyButton("刷新服务器信息") {
                                    refreshServersDatState(serversDat)
                                }
                                .frame(width: serverButtonWidth)
                                MyButton("添加新服务器") {
                                    NSWorkspace.shared.open(instance.runningDirectory)
                                    errorMessage = "已打开实例目录，请在游戏内添加服务器，或使用“导入 servers.dat”。"
                                }
                                .frame(width: serverButtonWidth)
                                MyButton("导入 servers.dat") {
                                    importServersDat(to: serversDat)
                                }
                                .frame(width: serverButtonWidth)
                                Spacer(minLength: 0)
                            }
                            .frame(height: 35)
                            HStack(spacing: 15) {
                                MyButton("导出 servers.dat") {
                                    exportServersDat(from: serversDat)
                                }
                                .frame(width: serverButtonWidth)
                                MyButton("打开 servers.dat") {
                                    if FileManager.default.fileExists(atPath: serversDat.path) {
                                        NSWorkspace.shared.open(serversDat)
                                    } else {
                                        errorMessage = "未找到 servers.dat，请先在游戏内添加一个服务器。"
                                    }
                                }
                                .frame(width: serverButtonWidth)
                                MyButton("重置", type: .red) {
                                    resetServersDat(at: serversDat)
                                }
                                .frame(width: serverButtonWidth)
                                Spacer(minLength: 0)
                            }
                            .frame(height: 35)
                            if let errorMessage {
                                MyText(errorMessage, color: errorMessage.contains("已检测") ? .colorGray3 : .red)
                            }
                        }
                    } else {
                        VStack(spacing: 10) {
                            MyText("暂时没有服务器", size: 18, color: .colorGray3)
                            MyText("你可以先在游戏内添加，或在此处导入 servers.dat。", size: 12, color: .colorGray3)
                            HStack(spacing: 15) {
                                Spacer()
                                MyButton("导入 servers.dat") {
                                    importServersDat(to: serversDat)
                                }
                                .frame(width: serverButtonWidth)
                                MyButton("刷新") {
                                    refreshServersDatState(serversDat)
                                }
                                .frame(width: serverButtonWidth)
                                Spacer()
                            }
                            .frame(height: 35)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                }
            } else {
                MyLoading(viewModel: .init(text: "未找到可配置的实例"))
            }
        }
        .task(id: id) {
            instance = InstancePageLoader.loadInstance(id)
            if let instance {
                refreshServersDatState(instance.runningDirectory.appending(path: "servers.dat"))
            }
        }
    }

    private func refreshServersDatState(_ path: URL) {
        hasServersDat = FileManager.default.fileExists(atPath: path.path)
        if hasServersDat {
            errorMessage = "已检测到 servers.dat，可直接导出或打开。"
        } else {
            errorMessage = "暂时没有服务器，请在游戏内添加后再刷新。"
        }
    }

    private func exportServersDat(from path: URL) {
        guard FileManager.default.fileExists(atPath: path.path) else {
            errorMessage = "未找到 servers.dat。"
            return
        }
        let panel = NSSavePanel()
        panel.title = "导出 servers.dat"
        panel.nameFieldStringValue = "servers.dat"
        panel.allowedContentTypes = [.data]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: path, to: destination)
            hint("导出成功", type: .finish)
            errorMessage = nil
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func importServersDat(to path: URL) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.data]
        panel.title = "导入 servers.dat"
        guard panel.runModal() == .OK, let source = panel.url else { return }
        guard source.lastPathComponent.lowercased() == "servers.dat" else {
            errorMessage = "请选择名为 servers.dat 的文件。"
            hint("导入失败：请选择 servers.dat", type: .critical)
            return
        }
        do {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: path.path) {
                try FileManager.default.removeItem(at: path)
            }
            try FileManager.default.copyItem(at: source, to: path)
            hint("导入成功", type: .finish)
            hasServersDat = true
            errorMessage = nil
        } catch {
            errorMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    private func resetServersDat(at path: URL) {
        do {
            if FileManager.default.fileExists(atPath: path.path) {
                try FileManager.default.removeItem(at: path)
            }
            hint("已重置 servers.dat", type: .finish)
            hasServersDat = false
            errorMessage = nil
        } catch {
            errorMessage = "重置失败：\(error.localizedDescription)"
        }
    }
}

struct InstanceModifyPage: View {
    let id: String
    @State private var instance: MinecraftInstance?
    @State private var newName: String = ""
    @State private var message: String?
    @State private var messageIsError: Bool = false

    var body: some View {
        CardContainer {
            if let instance {
                MyCard("基础信息", foldable: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 15) {
                            MyText("实例名称")
                                .frame(width: 100, alignment: .leading)
                            MyTextField(text: $newName)
                            MyButton("重命名") {
                                rename(current: instance)
                            }
                            .frame(width: 100)
                        }
                        MyText("修改名称后会同步更新实例目录与版本文件名。", size: 12, color: .colorGray3)
                        if let message {
                            MyText(message, color: messageIsError ? .red : .colorGray3)
                        }
                    }
                }

                MyCard("快捷操作", foldable: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            MyButton("编辑版本配置（json）") {
                                NSWorkspace.shared.open(instance.manifestURL)
                            }
                            .frame(width: 160)
                            MyButton("打开实例目录") {
                                NSWorkspace.shared.open(instance.runningDirectory)
                            }
                            .frame(width: 120)
                            Spacer()
                        }
                        .frame(height: 35)
                        MyText("建议在游戏关闭状态下进行修改，避免文件占用。", size: 12, color: .colorGray3)
                    }
                }
                .cardIndex(1)

                MyCard("开始修改", foldable: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        MyText("可先下载所需安装器，再返回实例执行版本修改。", size: 12, color: .colorGray3)
                        HStack(spacing: 15) {
                            MyButton("Minecraft") {
                                AppRouter.shared.setRoot(.download)
                                AppRouter.shared.append(.minecraftDownload)
                            }
                            .frame(width: 120)
                            MyButton("Forge") {
                                AppRouter.shared.setRoot(.download)
                                AppRouter.shared.append(.installerForgeDownload)
                            }
                            .frame(width: 120)
                            MyButton("NeoForge") {
                                AppRouter.shared.setRoot(.download)
                                AppRouter.shared.append(.installerNeoForgeDownload)
                            }
                            .frame(width: 120)
                            MyButton("Fabric") {
                                AppRouter.shared.setRoot(.download)
                                AppRouter.shared.append(.installerFabricDownload)
                            }
                            .frame(width: 120)
                            Spacer()
                        }
                        .frame(height: 35)
                    }
                }
                .cardIndex(2)
            } else {
                MyLoading(viewModel: .init(text: "未找到可配置的实例"))
            }
        }
        .task(id: id) {
            instance = InstancePageLoader.loadInstance(id)
            newName = instance?.name ?? ""
        }
    }

    private func rename(current: MinecraftInstance) {
        let target = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, target != current.name else {
            message = "请输入新的实例名。"
            messageIsError = true
            return
        }
        do {
            let oldID = current.name
            let renamed = try InstanceManager.shared.renameInstance(current, to: target)
            instance = renamed
            newName = renamed.name
            message = "重命名成功。"
            messageIsError = false
            migrateInstanceMeta(from: oldID, to: renamed.name)
            AppRouter.shared.replaceInstanceID(from: oldID, to: renamed.name)
            hint("实例已重命名为 \(renamed.name)", type: .finish)
        } catch {
            message = "重命名失败：\(error.localizedDescription)"
            messageIsError = true
            hint("重命名失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func migrateInstanceMeta(from oldID: String, to newID: String) {
        guard oldID != newID else { return }
        let defaults = UserDefaults.standard
        let oldDescKey = "instance.meta.desc.\(oldID)"
        let oldFavoriteKey = "instance.meta.favorite.\(oldID)"
        let newDescKey = "instance.meta.desc.\(newID)"
        let newFavoriteKey = "instance.meta.favorite.\(newID)"

        if let desc = defaults.string(forKey: oldDescKey) {
            defaults.set(desc, forKey: newDescKey)
            defaults.removeObject(forKey: oldDescKey)
        }
        if defaults.object(forKey: oldFavoriteKey) != nil {
            defaults.set(defaults.bool(forKey: oldFavoriteKey), forKey: newFavoriteKey)
            defaults.removeObject(forKey: oldFavoriteKey)
        }
    }
}

struct InstanceExportPage: View {
    let id: String
    @State private var instance: MinecraftInstance?
    @State private var includeBasic: Bool = true
    @State private var includeMods: Bool = true
    @State private var includeResourcepacks: Bool = true
    @State private var includeShaderpacks: Bool = true
    @State private var includeSaves: Bool = false

    var body: some View {
        CardContainer {
            if let instance {
                MyCard("导出实例", foldable: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        MyText("可将整个实例目录导出为 zip 归档，方便备份或迁移。", color: .colorGray3)
                        HStack(spacing: 16) {
                            Toggle("基础文件", isOn: $includeBasic)
                            Toggle("模组", isOn: $includeMods)
                            Toggle("资源包", isOn: $includeResourcepacks)
                            Toggle("光影包", isOn: $includeShaderpacks)
                            Toggle("存档", isOn: $includeSaves)
                        }
                        HStack(spacing: 15) {
                            MyButton("导出实例压缩包") {
                                exportInstance(instance)
                            }
                            .frame(width: 160)
                            MyButton("打开实例目录") {
                                NSWorkspace.shared.open(instance.runningDirectory)
                            }
                            .frame(width: 120)
                            Spacer()
                        }
                        .frame(height: 35)
                        MyText("导出过程不会修改当前实例。", size: 12, color: .colorGray3)
                    }
                }
            } else {
                MyLoading(viewModel: .init(text: "未找到可配置的实例"))
            }
        }
        .task(id: id) {
            instance = InstancePageLoader.loadInstance(id)
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
        let list = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles])) ?? []
        files = list.map { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return ResourceFileItem(id: url, url: url, modifiedAt: values?.contentModificationDate, byteSize: Int64(values?.fileSize ?? 0))
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
