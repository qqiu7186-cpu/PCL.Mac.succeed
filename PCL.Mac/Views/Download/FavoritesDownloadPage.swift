import SwiftUI
import Core

struct FavoritesDownloadPage: View {
    @StateObject private var store: FavoriteProjectsStore = .shared
    @StateObject private var viewModel: FavoritesDownloadViewModel = .init()
    @State private var query: String = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        CardContainer {
            if viewModel.loading {
                MyLoading(viewModel: .init(text: "加载中"))
            } else if store.entries.isEmpty {
                emptyStateCard
            } else {
                searchCard

                if filteredProjects.isEmpty {
                    MyCard("收藏夹", foldable: false) {
                        MyText("没有找到和“\(query)”相关的收藏。", color: .colorGray3)
                    }
                } else {
                    ForEach(groupedProjects, id: \.0) { section in
                        MyCard("\(sectionTitle(for: section.0))（\(section.1.count)）", foldable: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(section.1) { project in
                                    favoriteRow(project)
                                }
                            }
                        }
                    }
                }
            }
        }
        .task(id: store.orderedIDs) {
            await viewModel.reload(ids: store.orderedIDs)
        }
    }

    private var searchCard: some View {
        MyCard("", foldable: false, titled: false) {
            HStack(spacing: 10) {
                Image(.iconSearch)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Color.color1)

                ZStack(alignment: .leading) {
                    TextField("", text: $query)
                        .textFieldStyle(.plain)
                        .font(.custom("PCLEnglish", size: 14))
                        .foregroundStyle(.black)
                        .focused($searchFocused)

                    if !searchFocused && query.isEmpty {
                        Text("搜索收藏夹内容")
                            .allowsHitTesting(false)
                            .font(.custom("PCLEnglish", size: 14))
                            .foregroundStyle(Color.colorGray3)
                    }
                }
            }
        }
        .frame(height: 40)
    }

    private var emptyStateCard: some View {
        MyCard("", foldable: false, titled: false) {
            VStack(spacing: 12) {
                MyText("还没有收藏内容", size: 22, color: .color2)
                Rectangle()
                    .fill(Color.color2)
                    .frame(width: 230, height: 2)
                MyText("在资源详细信息界面中可以点击收藏按钮进行收藏。", size: 12, color: .colorGray3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity)
        .padding(.top, 140)
    }

    private var filteredProjects: [ProjectListItemModel] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return viewModel.projects }
        return viewModel.projects.filter { project in
            let note = store.note(for: project.id) ?? ""
            let haystack = [project.title, project.description, note].joined(separator: "\n").localizedLowercase
            return haystack.contains(trimmedQuery.localizedLowercase)
        }
    }

    private var groupedProjects: [(ModrinthProjectType, [ProjectListItemModel])] {
        let order: [ModrinthProjectType] = [.mod, .modpack, .resourcepack, .shader]
        let groups = Dictionary(grouping: filteredProjects, by: \.type)
        return order.compactMap { type in
            guard let items = groups[type], !items.isEmpty else { return nil }
            return (type, items)
        }
    }

    @ViewBuilder
    private func favoriteRow(_ project: ProjectListItemModel) -> some View {
        MyListItem { hovered in
            HStack(spacing: 10) {
                Group {
                    if let iconURL = project.iconURL {
                        NetworkImage(url: iconURL, targetSize: .init(width: 42, height: 42))
                    } else {
                        Image(iconName(for: project.type))
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                            .foregroundStyle(Color.color1)
                    }
                }
                .frame(width: 42, height: 42)
                .background(Color.colorGray7)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 3) {
                    MyText(project.title, size: 15)
                        .lineLimit(1)
                    MyText(project.description, size: 12, color: .colorGray3)
                        .lineLimit(1)
                    if let note = store.note(for: project.id) {
                        MyText("备注：\(note)", size: 12, color: .color2)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if hovered {
                    HStack(spacing: 10) {
                        Button {
                            Task { await editNote(for: project) }
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(Color.color3)
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await removeFavorite(project) }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(Color.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onTapGesture {
            AppRouter.shared.append(.projectInstall(.init(project: project)))
        }
    }

    private func sectionTitle(for type: ModrinthProjectType) -> String {
        switch type {
        case .mod: "模组"
        case .modpack: "整合包"
        case .resourcepack: "资源包"
        case .shader: "光影包"
        }
    }

    private func editNote(for project: ProjectListItemModel) async {
        let result = await MessageBoxManager.shared.showInputAsync(
            title: "编辑备注",
            initialContent: store.note(for: project.id),
            placeholder: "输入备注（选填）"
        )
        guard let result else { return }
        store.updateNote(for: project.id, note: result)
    }

    private func removeFavorite(_ project: ProjectListItemModel) async {
        let confirmed = await MessageBoxManager.shared.showConfirmAsync(
            title: "确认删除",
            content: "确定要将 \(project.title) 从收藏夹中移除吗？",
            level: .error,
            cancelLabel: "取消",
            confirmLabel: "删除",
            confirmType: .red
        )
        guard confirmed else { return }
        store.remove(project.id, name: project.title)
    }

    private func iconName(for type: ModrinthProjectType) -> String {
        switch type {
        case .mod: "iconMod"
        case .modpack: "iconBox"
        case .resourcepack: "iconPicture"
        case .shader: "iconSun"
        }
    }
}
