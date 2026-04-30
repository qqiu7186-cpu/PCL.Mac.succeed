//
//  ResourceInstallPage.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/19.
//

import SwiftUI
import Core

struct ResourceInstallPage: View {
    @StateObject private var viewModel: ResourceInstallViewModel
    @StateObject private var favoritesStore: FavoriteProjectsStore = .shared
    @State private var selectedGameVersionLine: String?
    @State private var selectedLoader: ModLoader?
    
    init(target: ProjectInstallTarget) {
        self._viewModel = StateObject(wrappedValue: .init(target: target))
    }
    
    var body: some View {
        CardContainer {
            headerCard

            if viewModel.loaded, let versionList = viewModel.versionList {
                filtersCard(versionList: versionList)

                if filteredVersionGroups(from: versionList).isEmpty {
                    MyCard("版本列表", foldable: false) {
                        MyText("当前筛选条件下没有可用版本。", color: .colorGray3)
                    }
                } else {
                    ForEach(Array(filteredVersionGroups(from: versionList).enumerated()), id: \.element.0.id) { index, versionGroup in
                        versionCard(
                            versionGroup: versionGroup,
                            isSelected: viewModel.selectedVersionGroup.map { $0.0 == versionGroup.0 } ?? false,
                            folded: true
                        )
                        .cardIndex(index + 1)
                    }
                }
            } else {
                MyLoading(viewModel: viewModel.loadingVM)
                    .cardIndex(1)
            }
        }
        .task(id: viewModel.target) {
            do {
                try await viewModel.load(selectedInstance: InstanceManager.shared.currentInstance)
            } catch is CancellationError {
            } catch {
                err("加载\(viewModel.target.type) \(viewModel.target.title) 版本列表失败：\(error)")
                viewModel.loadingVM.fail(with: "加载版本列表失败：\(error.localizedDescription)")
            }
        }
    }

    private var headerCard: some View {
        MyCard("", titled: false, limitHeight: false) {
            if let project = viewModel.project {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        Group {
                            if let iconURL = project.iconURL {
                                NetworkImage(url: iconURL, targetSize: .init(width: 52, height: 52))
                            } else {
                                Image(defaultProjectIcon(for: project.type))
                                    .resizable()
                                    .scaledToFit()
                                    .padding(10)
                                    .foregroundStyle(Color.color1)
                            }
                        }
                        .frame(width: 52, height: 52)
                        .background(Color.colorGray7)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 6) {
                            MyText(project.title, size: 18)
                            MyText(project.description, color: .colorGray3)
                                .lineLimit(2)

                            HStack(spacing: 18) {
                                HeaderInfoView(icon: .iconSettingsPage, text: project.supportDescription)
                                HeaderInfoView(icon: .iconDownloadPage, text: project.downloads)
                                HeaderInfoView(icon: .iconUpload, text: project.lastUpdate)
                                HeaderInfoView(icon: .iconAbout, text: "Modrinth")
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                    actionButton(icon: .iconAbout, text: "打开来源页", action: openProjectPage)
                    actionButton(icon: .iconCopy, text: "复制项目 ID", action: copyProjectID)
                    actionButton(icon: .iconCopy, text: "复制项目名", action: copyProjectName)
                    actionButton(icon: favoritesStore.contains(project.id) ? .iconFavoriteFilled : .iconFavorite, text: favoritesStore.contains(project.id) ? "取消收藏" : "收藏") {
                                    favoritesStore.toggle(project.id, name: project.title)
                                }
                            }
                        }
                    }
                }
            } else {
                MyLoading(viewModel: .init(text: "正在加载项目详情"), showCard: false)
            }
        }
    }

    private func filtersCard(versionList: ResourceInstallViewModel.VersionList) -> some View {
        let versions = availableGameVersions(from: versionList)
        let loaders = availableLoaders(from: versionList)

        return MyCard("", foldable: false, titled: false) {
            VStack(alignment: .leading, spacing: 14) {
                if !versions.isEmpty {
                    filterRow(title: "实例筛选") {
                        chip("全部", selected: selectedGameVersionLine == nil) {
                            selectedGameVersionLine = nil
                        }
                        ForEach(versions, id: \.self) { version in
                            chip(version, selected: selectedGameVersionLine == version) {
                                selectedGameVersionLine = version
                            }
                        }
                    }
                }

                if !loaders.isEmpty {
                    filterRow(title: "模组加载器筛选") {
                        chip("全部", selected: selectedLoader == nil) {
                            selectedLoader = nil
                        }
                        ForEach(loaders, id: \.rawValue) { loader in
                            chip(loader.description, selected: selectedLoader == loader) {
                                selectedLoader = loader
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func onVersionTap(_ version: ProjectVersionModel) async throws {
        if let message = try await viewModel.confirmVersionInstall(for: version) {
            hint(message, type: .critical)
        }
    }
    
    private func onModpackTap(_ version: ProjectVersionModel) async throws {
        if let message = try await viewModel.confirmModpackInstall(for: version) {
            hint(message, type: .critical)
        }
    }
    
    @ViewBuilder
    private func versionCard(versionGroup: ResourceInstallViewModel.VersionGroup, isSelected: Bool = false, folded: Bool = true) -> some View {
        MyCard((isSelected ? "推荐版本：" : "") + versionGroup.0.description, foldable: true, folded: folded) {
            let dependencies: [ProjectVersionModel.Dependency] = versionGroup.1[0].requiredDependencies
            HStack(spacing: 10) {
                if isSelected {
                    chipBadge("推荐", highlighted: true)
                }
                chipBadge(versionGroup.0.version.id, highlighted: false)
                if let loader = versionGroup.0.loader {
                    chipBadge(loader.description, highlighted: false)
                }
                Spacer()
                MyText("共 \(versionGroup.1.count) 个版本", size: 12, color: .colorGray2)
            }
            .padding(.bottom, 10)

            if !dependencies.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    MyText("前置资源", color: .colorGray2)
                    VStack(spacing: 0) {
                        ForEach(dependencies) { dependency in
                            ProjectListItemView(project: dependency.project)
                                .onTapGesture {
                                    viewModel.openDependencyProject(dependency.project)
                            }
                        }
                    }
                    MyText("版本列表", color: .colorGray2)
                }
                .padding(.bottom, 6)
            }
            VStack(spacing: 0) {
                ForEach(versionGroup.1) { version in
                    VersionListItemView(version: version)
                        .onTapGesture {
                            log("\(version.name) \(version.version) 被点击")
                            Task {
                                do {
                                    if viewModel.target.type == .modpack {
                                        try await onModpackTap(version)
                                    } else {
                                        try await onVersionTap(version)
                                    }
                                } catch {
                                    err("执行点击回调意外失败：\(error.localizedDescription)")
                                    hint("执行点击回调意外失败：\(error.localizedDescription)", type: .critical)
                                }
                            }
                        }
                }
            }
        }
    }
    
    private struct VersionListItemView: View {
        private let model: ListItem
        
        init(version: ProjectVersionModel) {
            self.model = .init(
                image: version.type.icon,
                name: version.name,
                description: [
                    version.version,
                    version.loader?.description,
                    version.gameVersion,
                    version.datePublished,
                    version.type.localizedName
                ]
                .compactMap { $0 }
                .joined(separator: "，")
            )
        }
        
        var body: some View {
            MyListItem(model)
        }
    }

    private struct HeaderInfoView: View {
        let icon: ImageResource?
        let text: String

        var body: some View {
            HStack(spacing: 5) {
                if let icon {
                    Image(icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 13)
                        .foregroundStyle(Color.colorGray3)
                }
                MyText(text, size: 12, color: .colorGray3)
            }
        }
    }

    @ViewBuilder
    private func filterRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            MyText("\(title)：", color: .colorGray2)
                .lineLimit(1)
                .frame(width: 126, alignment: .leading)
                .frame(minHeight: 28, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    content()
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            MyText(text, color: selected ? .white : .color3)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background {
                    Capsule()
                        .fill(selected ? Color.color3 : Color.color8)
                }
        }
        .buttonStyle(.plain)
    }

    private func chipBadge(_ text: String, highlighted: Bool) -> some View {
        MyText(text, size: 12, color: highlighted ? .white : .color2)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background {
                Capsule()
                    .fill(highlighted ? Color.color3 : Color.color8)
            }
    }

    private func actionButton(icon: ImageResource, text: String, action: @escaping () -> Void) -> some View {
        actionButton(icon: icon, systemIcon: nil, text: text, action: action)
    }

    private func actionButton(systemIcon: String, text: String, action: @escaping () -> Void) -> some View {
        actionButton(icon: nil, systemIcon: systemIcon, text: text, action: action)
    }

    private func actionButton(icon: ImageResource?, systemIcon: String?, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 13, height: 13)
                        .foregroundStyle(Color.color1)
                } else if let systemIcon {
                    Image(systemName: systemIcon)
                        .font(.system(size: 12, weight: .medium))
                }
                MyText(text, size: 12, color: .color1)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background {
                Capsule()
                    .fill(Color.white)
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.colorGray6, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private func availableGameVersions(from versionList: ResourceInstallViewModel.VersionList) -> [String] {
        Array(Set(versionList.map { versionLine(for: $0.0.version.id) })).sorted { lhs, rhs in
            MinecraftVersion(lhs) > MinecraftVersion(rhs)
        }
    }

    private func availableLoaders(from versionList: ResourceInstallViewModel.VersionList) -> [ModLoader] {
        Array(Set(versionList.compactMap { $0.0.loader })).sorted { $0.index < $1.index }
    }

    private func filteredVersionGroups(from versionList: ResourceInstallViewModel.VersionList) -> ResourceInstallViewModel.VersionList {
        versionList.filter { group in
            let matchesVersion = selectedGameVersionLine == nil || versionLine(for: group.0.version.id) == selectedGameVersionLine
            let matchesLoader = selectedLoader == nil || group.0.loader == selectedLoader
            return matchesVersion && matchesLoader
        }
    }

    private func versionLine(for version: String) -> String {
        let parts = version.split(separator: ".")
        guard parts.count >= 2 else { return version }
        return "\(parts[0]).\(parts[1])"
    }

    private func defaultProjectIcon(for type: ModrinthProjectType) -> ImageResource {
        switch type {
        case .mod: .iconMod
        case .modpack: .iconBox
        case .resourcepack: .iconPicture
        case .shader: .iconSun
        }
    }

    private func openProjectPage() {
        guard let url = URL(string: "https://modrinth.com/project/\(viewModel.target.id)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyProjectID() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(viewModel.target.id, forType: .string)
        hint("已复制项目 ID。", type: .finish)
    }

    private func copyProjectName() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(viewModel.target.title, forType: .string)
        hint("已复制项目名称。", type: .finish)
    }
}
