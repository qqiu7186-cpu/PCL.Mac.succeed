import SwiftUI
import Core

struct FavoritesDownloadPage: View {
    @StateObject private var store: FavoriteProjectsStore = .shared
    @State private var projects: [ProjectListItemModel] = []
    @State private var loading: Bool = false

    var body: some View {
        CardContainer {
            if loading {
                MyLoading(viewModel: .init(text: "加载中"))
            } else if projects.isEmpty {
                MyCard("收藏夹", foldable: false) {
                    MyText("收藏夹为空，去社区资源里点 ⭐ 收藏你喜欢的项目。", color: .colorGray3)
                }
            } else {
                MyCard("收藏夹（\(projects.count)）", foldable: false) {
                    MyList(items: projects.map { project in
                        ListItem(image: iconName(for: project.type), name: project.title, description: project.description)
                    }) { index in
                        guard let index else { return }
                        AppRouter.shared.append(.projectInstall(project: projects[index]))
                    }
                }
            }
        }
        .task(id: store.ids) {
            loading = true
            var loaded: [ProjectListItemModel] = []
            for id in store.ids {
                if let project = try? await ModrinthAPIClient.shared.project(id) {
                    loaded.append(.init(project))
                }
            }
            projects = loaded
            loading = false
        }
    }

    private func iconName(for type: ModrinthProjectType) -> String {
        switch type {
        case .mod: "IconMod"
        case .modpack: "IconBox"
        case .resourcepack: "IconPicture"
        case .shader: "IconSun"
        }
    }
}
