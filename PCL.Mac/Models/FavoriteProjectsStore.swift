import Foundation
import Core

@MainActor
class FavoriteProjectsStore: ObservableObject {
    static let shared: FavoriteProjectsStore = .init()

    @Published private(set) var ids: Set<String>

    private let key: String = "favoriteProjectIds"

    private init() {
        let loaded = UserDefaults.standard.array(forKey: key) as? [String] ?? []
        self.ids = Set(loaded)
    }

    func contains(_ id: String) -> Bool {
        ids.contains(id)
    }

    func toggle(_ id: String, name: String? = nil) {
        let normalizedName: String? = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetName: String = (normalizedName?.isEmpty == false) ? (normalizedName ?? "该项目") : "该项目"
        if ids.contains(id) {
            ids.remove(id)
            hint("已从收藏夹移除 \(targetName)", type: .finish)
        } else {
            ids.insert(id)
            hint("已收藏 \(targetName)", type: .finish)
        }
        UserDefaults.standard.set(Array(ids), forKey: key)
    }
}
