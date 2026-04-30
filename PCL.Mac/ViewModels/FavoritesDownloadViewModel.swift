import Foundation
import Core

@MainActor
final class FavoritesDownloadViewModel: ObservableObject {
    @Published private(set) var projects: [ProjectListItemModel] = []
    @Published private(set) var loading = false

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies = .live) {
        self.dependencies = dependencies
    }

    func reload(ids: [String]) async {
        loading = true
        defer { loading = false }

        var loaded: [ProjectListItemModel] = []
        for id in ids {
            if let project = try? await dependencies.modrinthService.project(id, revalidate: false) {
                loaded.append(.init(project))
            }
        }

        projects = loaded
    }
}
