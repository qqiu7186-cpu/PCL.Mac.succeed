//
//  ResourcesSearchPage.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/16.
//

import SwiftUI
import Core

struct ResourcesSearchPage: View {
    @StateObject private var viewModel: ResourcesSearchViewModel
    @State private var currentPage: Int = 0

    init(type: ModrinthProjectType) {
        self._viewModel = StateObject(wrappedValue: .init(type: type))
    }

    init(type: ModrinthProjectType, requiredCategories: [String]) {
        self._viewModel = StateObject(wrappedValue: .init(type: type, requiredCategories: requiredCategories))
    }

    var body: some View {
        CardContainer {
            if viewModel.type == .shader {
                MyTip(text: "光影包需要搭配光影加载器使用。\n详细教程：https://cylorine.studio/helps/shader", theme: .blue)
                    .onTapGesture {
                        NSWorkspace.shared.open(URL(string: "https://cylorine.studio/helps/shader")!)
                    }
            }

            MySearchBox(placeholder: "搜索\(pageTitle)") { query in
                currentPage = 0
                viewModel.submitSearch(query)
            }

            filtersCard

            switch viewModel.phase {
            case .loading:
                MyLoading(viewModel: viewModel.loadingVM)
            case .failure(let message):
                MyCard("搜索失败", foldable: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        MyText(message, color: .colorGray3)
                        MyButton("重试") {
                            viewModel.retry()
                        }
                        .frame(width: 100)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .empty:
                emptyStateView
            case .content:
                PaginatedContainer(currentPage: $currentPage, pageCount: viewModel.totalPages) { _ in
                    MyCard("", titled: false) {
                        VStack(alignment: .leading, spacing: 10) {
                            if viewModel.isRefreshing {
                                MyText("正在刷新结果，旧内容会保留到新结果返回。", size: 12, color: .colorGray3)
                            }
                            if viewModel.isLoadingNextPage {
                                MyText("正在加载下一页……", size: 12, color: .colorGray3)
                            }
                            if let inlineErrorMessage = viewModel.inlineErrorMessage {
                                MyTip(text: inlineErrorMessage, theme: .red)
                            }
                            LazyVStack(spacing: 0) {
                                ForEach(viewModel.searchResults) { project in
                                    ProjectListItemView(project: project)
                                        .onTapGesture {
                                            AppRouter.shared.append(.projectInstall(.init(project: project)))
                                        }
                                }
                            }
                        }
                    }
                }
                .onChange(of: currentPage) { newValue in
                    viewModel.submitPageChange(newValue)
                }
            }
        }
        .task {
            viewModel.loadInitialResults()
        }
    }

    private var filtersCard: some View {
        MyCard("", foldable: false, titled: false) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 14) {
                    compactFilterField(title: "来源", value: viewModel.selectedSource.localizedName, labelWidth: 32, fieldWidth: 230) {
                        ForEach(viewModel.availableSources) { source in
                            Button(source.localizedName) {
                                currentPage = 0
                                viewModel.updateSource(source)
                            }
                        }
                    }

                    compactFilterField(title: "排序方式", value: viewModel.selectedSort.localizedName, labelWidth: 56, fieldWidth: 230) {
                        ForEach(viewModel.availableSortOptions) { sort in
                            Button(sort.localizedName) {
                                currentPage = 0
                                viewModel.updateSort(sort)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }

                HStack(alignment: .top, spacing: 14) {
                    compactFilterField(title: "版本", value: viewModel.selectedVersion ?? "任意", labelWidth: 32, fieldWidth: 230) {
                        Button("任意") {
                            currentPage = 0
                            viewModel.updateVersion(nil)
                        }
                        ForEach(viewModel.availableVersions, id: \.self) { version in
                            Button(version) {
                                currentPage = 0
                                viewModel.updateVersion(version)
                            }
                        }
                    }

                    if viewModel.supportsLoaderFilter && !viewModel.availableLoaders.isEmpty {
                        compactFilterField(title: "加载器", value: viewModel.selectedLoader?.description ?? "任意", labelWidth: 44, fieldWidth: 230) {
                            Button("任意") {
                                currentPage = 0
                                viewModel.updateLoader(nil)
                            }
                            ForEach(viewModel.availableLoaders, id: \.rawValue) { loader in
                                Button(loader.description) {
                                    currentPage = 0
                                    viewModel.updateLoader(loader)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var emptyStateView: some View {
        MyCard("搜索结果", foldable: false) {
            VStack(alignment: .leading, spacing: 12) {
                MyText(viewModel.query.isEmpty ? "暂时没有可展示的资源。" : "没有找到和“\(viewModel.query)”相关的结果。", color: .colorGray3)
                if !viewModel.query.isEmpty {
                    MyButton("重新加载") {
                        viewModel.retry()
                    }
                    .frame(width: 100)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var pageTitle: String {
        if viewModel.requiredCategories.contains("datapack") {
            return "数据包"
        }
        if viewModel.requiredCategories.contains("worldgen") {
            return "世界"
        }
        return viewModel.type.localizedName
    }

    @ViewBuilder
    private func filterMenu<Content: View>(title: String, value: String, disabled: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            VStack(alignment: .leading, spacing: title.isEmpty ? 0 : 6) {
                if !title.isEmpty {
                    Text(title)
                        .font(.custom("PCLEnglish", size: 12))
                        .foregroundStyle(Color.colorGray2)
                }
                HStack(spacing: 8) {
                    Text(value)
                        .font(.custom("PCLEnglish", size: 14))
                        .foregroundStyle(disabled ? Color.colorGray4 : Color.color1)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.colorGray8)
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(menuBorderColor(value: value, disabled: disabled), lineWidth: 1)
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Color.color1)
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        .tint(.color1)
        .disabled(disabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func compactFilterField<Content: View>(title: String, value: String, labelWidth: CGFloat, fieldWidth: CGFloat, disabled: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            MyText(title, size: 13, color: .colorGray2)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: labelWidth, alignment: .leading)
            filterMenu(title: "", value: value, disabled: disabled) {
                content()
            }
            .frame(width: fieldWidth, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func menuBorderColor(value: String, disabled: Bool) -> Color {
        if disabled {
            return .colorGray6
        }
        let isDefaultValue = value == "任意" || value == "默认" || value == "Modrinth"
        return isDefaultValue ? .colorGray6 : .color5
    }
}

struct ProjectListItemView: View {
    @StateObject private var favoritesStore: FavoriteProjectsStore = .shared
    @State private var isHovered: Bool = false
    private let project: ProjectListItemModel

    init(project: ProjectListItemModel) {
        self.project = project
    }

    var body: some View {
        MyListItem {
            HStack {
                Group {
                    if let iconURL: URL = project.iconURL {
                        NetworkImage(url: iconURL, targetSize: .init(width: 48, height: 48))
                    } else {
                        Color.clear
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(width: 48, height: 48)
                .padding(.leading, 4)

                VStack(alignment: .leading, spacing: 2) {
                    MyText(project.title, size: 16)
                        .lineLimit(1)
                    HStack {
                        ForEach(project.tags, id: \.self) { tag in
                            MyTag(tag, labelColor: .colorGray2, backgroundColor: .init(0x000000, alpha: 17 / 255), size: 12)
                        }
                        MyText(project.description, color: .colorGray3)
                            .lineLimit(1)
                    }

                    HStack {
                        InformationView(icon: .iconSettingsPage, text: project.supportDescription, width: 200)
                        InformationView(icon: .iconDownloadPage, text: project.downloads, width: 150)
                        InformationView(icon: .iconUpload, text: project.lastUpdate, width: 150)
                        Spacer()
                    }

                    Spacer(minLength: 0)
                }
                Button {
                    favoritesStore.toggle(project.id, name: project.title)
                } label: {
                    Group {
                        if favoritesStore.contains(project.id) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(Color.yellow)
                        } else if isHovered {
                            Image(systemName: "star")
                                .foregroundStyle(Color.colorGray3)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                Spacer(minLength: 0)
            }
        }
        .onHover { isHovered = $0 }
    }

    private struct InformationView: View {
        private let icon: ImageResource
        private let text: String
        private let width: CGFloat

        init(icon: ImageResource, text: String, width: CGFloat) {
            self.icon = icon
            self.text = text
            self.width = width
        }

        var body: some View {
            HStack(spacing: 6) {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14)
                    .foregroundStyle(Color.colorGray3)
                MyText(text, size: 12, color: .colorGray3)
            }
            .frame(width: width, alignment: .leading)
        }
    }

}
