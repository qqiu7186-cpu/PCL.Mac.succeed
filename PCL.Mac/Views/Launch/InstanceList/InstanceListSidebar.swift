//
//  InstanceListSidebar.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/12/27.
//

import SwiftUI
import Core

struct InstanceListSidebar: Sidebar {
    @EnvironmentObject private var instanceViewModel: InstanceManager
    @EnvironmentObject private var viewModel: InstanceListViewModel
    @ObservedObject private var router: AppRouter = .shared
    
    let width: CGFloat = 205
    private let modpackViewModel: ModpackViewModel = .init()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MyText("文件夹列表", size: 11.5, color: .colorGray3)
                .padding(.leading, 12)
                .padding(.top, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if instanceViewModel.repositories.isEmpty {
                        MyText("暂无目录", color: .colorGray3)
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                    } else {
                        ForEach(instanceViewModel.repositories, id: \.url) { repository in
                            RepositoryRow(
                                repository: repository,
                                selected: isSelected(repository)
                            ) {
                                open(repository)
                            }
                        }
                    }

                    MyText("添加或导入", size: 11.5, color: .colorGray3)
                        .padding(.leading, 12)
                        .padding(.top, 18)
                        .padding(.bottom, 6)

                    VStack(spacing: 2) {
                        ImportButton("IconAdd", "添加已有文件夹") {
                            try instanceViewModel.requestAddRepository()
                        }
                        ImportButton("IconImportModpack", "导入整合包", perform: onImportModpackClicked)
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: instanceViewModel.repositories) { newValue in
            if let repository = newValue.first, AppRouter.shared.getLast() == .noInstanceRepository {
                AppRouter.shared.removeLast()
                AppRouter.shared.append(.instanceList(instanceViewModel.repositoryTarget(for: repository)))
            }
        }
    }

    private func isSelected(_ repository: MinecraftRepository) -> Bool {
        guard case .instanceList(let target) = router.getLast() else {
            return false
        }
        return target.repositoryPath == repository.url.standardizedFileURL.path
    }

    private func open(_ repository: MinecraftRepository) {
        let route: AppRoute = .instanceList(instanceViewModel.repositoryTarget(for: repository))
        if router.getLast() != route {
            router.removeLast()
            router.append(route)
        }
        viewModel.reloadAsync(repository)
    }
    
    private func onImportModpackClicked() {
        guard let repository: MinecraftRepository = instanceViewModel.currentRepository else {
            hint("请先选择一个游戏目录！", type: .critical)
            return
        }
        
        let panel: NSOpenPanel = .init()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .zip,
            .init(filenameExtension: "mrpack")!
        ]
        
        if panel.runModal() == .OK {
            guard let url = panel.url else { return }
            Task(priority: .userInitiated) {
                await importModpack(url, repository: repository)
            }
        }
    }
    
    private func importModpack(_ url: URL, repository: MinecraftRepository) async {
        do {
            guard let result: ModpackViewModel.ModpackLoadResult = try modpackViewModel.loadModpack(at: url) else {
                _ = await MessageBoxManager.shared.showTextAsync(
                    title: "不支持的整合包格式",
                    content: "很抱歉，PCL.Mac 目前只支持导入 Modrinth 格式的整合包，不支持这个整合包使用的格式……",
                    level: .error
                )
                return
            }
            guard await MessageBoxManager.shared.showTextAsync(
                title: "整合包信息",
                content: "格式：\(result.format)\n名称：\(result.name)\n版本：\(result.version)\n描述：\(result.summary)\n依赖：\(result.dependencyInfo)\n\n是否继续安装？",
                level: .info,
                .no(),
                .yes(label: "继续")
            ) == 1 else { return }
            
            guard var name: String = await MessageBoxManager.shared.showInputAsync(
                title: "导入整合包 - 输入实例名",
                initialContent: result.name
            ) else { return }
            
            do {
                name = try repository.checkInstanceName(name)
            } catch {
                hint(AppError.wrap(error, category: .configuration, action: "该名称不可用").localizedDescription, type: .critical)
                return
            }
            
            switch result.index {
            case .modrinth(let index):
                let task = try ModrinthModpackInstallTask.create(
                    url: url,
                    index: index,
                    repository: repository,
                    name: name
                ) { instance in
                    instanceViewModel.switchInstance(to: instance, repository)
                    if AppRouter.shared.getLast() == .tasks {
                        AppRouter.shared.removeLast()
                        if case .minecraftInstallOptions = AppRouter.shared.getLast() {
                            AppRouter.shared.removeLast()
                        }
                    }
                }
                
                TaskManager.shared.execute(task: task)
                AppRouter.shared.append(.tasks)
            }
        } catch {
            err("导入整合包失败：\(error)")
            hint(AppError.wrap(error, category: .fileSystem, action: "导入整合包失败").localizedDescription, type: .critical)
        }
    }
}

private struct RepositoryRow: View {
    private let repository: MinecraftRepository
    private let selected: Bool
    private let onTap: () -> Void
    @State private var hovered: Bool = false

    init(repository: MinecraftRepository, selected: Bool, onTap: @escaping () -> Void) {
        self.repository = repository
        self.selected = selected
        self.onTap = onTap
    }

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Rectangle()
                .fill(selected ? Color.color3 : .clear)
                .frame(width: 3, height: 26)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                MyText(repository.name, size: 12.5, color: selected ? .color3 : .color1)
                    .lineLimit(1)
                Text(repository.url.path)
                    .font(.custom("PCLEnglish", size: 9.5))
                    .foregroundStyle(Color.colorGray3)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.trailing, 4)

            Spacer(minLength: 0)
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .frame(minHeight: 50)
        .background(hovered || selected ? Color.color2.opacity(selected ? 0.10 : 0.06) : .clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(perform: onTap)
        .animation(.easeInOut(duration: 0.12), value: hovered)
        .animation(.easeInOut(duration: 0.12), value: selected)
    }
}

private struct ImportButton: View {
    private let image: String
    private let label: String
    private let perform: () throws -> Void
    
    public init(_ image: String, _ label: String, perform: @escaping () throws -> Void) {
        self.image = image
        self.label = label
        self.perform = perform
    }
    
    var body: some View {
        MyListItem {
            HStack(spacing: 8) {
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Color.color1)
                MyText(label, size: 13)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .onTapGesture {
            try? perform()
        }
    }
}
