import Foundation
import Core

@MainActor
class FavoriteProjectsStore: ObservableObject {
    struct Entry: Codable, Identifiable, Equatable {
        let id: String
        var name: String?
        var note: String?
    }

    static let shared: FavoriteProjectsStore = .init()

    @Published private(set) var entries: [Entry]

    var ids: Set<String> {
        Set(entries.map(\.id))
    }

    var orderedIDs: [String] {
        entries.map(\.id)
    }

    private let key: String = "favoriteProjects"
    private let legacyKey: String = "favoriteProjectIds"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let loaded = try? JSONDecoder().decode([Entry].self, from: data) {
            self.entries = loaded
            return
        }

        let legacy = UserDefaults.standard.array(forKey: legacyKey) as? [String] ?? []
        self.entries = legacy.map { .init(id: $0, name: nil, note: nil) }
        persist()
    }

    func contains(_ id: String) -> Bool {
        ids.contains(id)
    }

    func entry(for id: String) -> Entry? {
        entries.first(where: { $0.id == id })
    }

    func note(for id: String) -> String? {
        entry(for: id)?.note
    }

    func toggle(_ id: String, name: String? = nil) {
        let normalizedName: String? = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetName: String = (normalizedName?.isEmpty == false) ? (normalizedName ?? "该项目") : "该项目"
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries.remove(at: index)
            hint("已从收藏夹移除 \(targetName)", type: .finish)
        } else {
            entries.append(.init(id: id, name: normalizedName, note: nil))
            hint("已收藏 \(targetName)", type: .finish)
        }
        persist()
    }

    func remove(_ id: String, name: String? = nil) {
        let normalizedName: String? = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetName: String = (normalizedName?.isEmpty == false) ? (normalizedName ?? "该项目") : (entry(for: id)?.name ?? "该项目")
        entries.removeAll { $0.id == id }
        persist()
        hint("已从收藏夹移除 \(targetName)", type: .finish)
    }

    func updateNote(for id: String, note: String?) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        entries[index].note = (trimmed?.isEmpty == false) ? trimmed : nil
        persist()
        hint(entries[index].note == nil ? "已清除备注" : "备注已保存", type: .finish)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }
}
