import Foundation

enum InstanceMetadataService {
    enum Category: String, CaseIterable {
        case normal = "普通实例"
        case favorite = "收藏夹"
    }

    struct IconOption {
        let id: String
        let name: String
        let resource: ImageResource
    }

    static let iconOptions: [IconOption] = [
        .init(id: "iconGrassBlock", name: "草方块", resource: .iconGrassBlock),
        .init(id: "iconDirt", name: "泥土", resource: .iconDirt),
        .init(id: "iconCobblestone", name: "圆石", resource: .iconCobblestone),
        .init(id: "iconGoldBlock", name: "金块", resource: .iconGoldBlock),
        .init(id: "iconRedstoneBlock", name: "红石块", resource: .iconRedstoneBlock),
        .init(id: "iconMod", name: "模组", resource: .iconMod),
        .init(id: "iconJava", name: "Java", resource: .iconJava),
        .init(id: "gameDownloadIcon", name: "下载", resource: .gameDownloadIcon)
    ]

    private static func descriptionKey(for instanceID: String) -> String {
        "instance.meta.desc.\(instanceID)"
    }

    private static func favoriteKey(for instanceID: String) -> String {
        "instance.meta.favorite.\(instanceID)"
    }

    private static func categoryKey(for instanceID: String) -> String {
        "instance.meta.category.\(instanceID)"
    }

    private static func iconKey(for instanceID: String) -> String {
        "instance.meta.icon.\(instanceID)"
    }

    private static func launchCountKey(for instanceID: String) -> String {
        "instance.meta.launchCount.\(instanceID)"
    }

    static func description(for instanceID: String) -> String {
        UserDefaults.standard.string(forKey: descriptionKey(for: instanceID)) ?? ""
    }

    static func setDescription(_ description: String, for instanceID: String) {
        UserDefaults.standard.set(description, forKey: descriptionKey(for: instanceID))
    }

    static func isFavorite(instanceID: String) -> Bool {
        UserDefaults.standard.bool(forKey: favoriteKey(for: instanceID))
    }

    static func setFavorite(_ isFavorite: Bool, for instanceID: String) {
        UserDefaults.standard.set(isFavorite, forKey: favoriteKey(for: instanceID))
        if isFavorite {
            setCategory(.favorite, for: instanceID)
        } else if category(for: instanceID) == .favorite {
            setCategory(.normal, for: instanceID)
        }
    }

    static func category(for instanceID: String) -> Category {
        if let raw = UserDefaults.standard.string(forKey: categoryKey(for: instanceID)),
           let category = Category(rawValue: raw) {
            return category
        }
        return isFavorite(instanceID: instanceID) ? .favorite : .normal
    }

    static func setCategory(_ category: Category, for instanceID: String) {
        UserDefaults.standard.set(category.rawValue, forKey: categoryKey(for: instanceID))
        UserDefaults.standard.set(category == .favorite, forKey: favoriteKey(for: instanceID))
    }

    static func icon(for instanceID: String) -> ImageResource? {
        guard let raw = UserDefaults.standard.string(forKey: iconKey(for: instanceID)) else { return nil }
        return iconOptions.first(where: { $0.id == raw })?.resource
    }

    static func setIcon(_ icon: ImageResource?, for instanceID: String) {
        if let icon {
            guard let option = iconOptions.first(where: { $0.resource == icon }) else { return }
            UserDefaults.standard.set(option.id, forKey: iconKey(for: instanceID))
        } else {
            UserDefaults.standard.removeObject(forKey: iconKey(for: instanceID))
        }
    }

    static func launchCount(for instanceID: String) -> Int {
        UserDefaults.standard.integer(forKey: launchCountKey(for: instanceID))
    }

    static func incrementLaunchCount(for instanceID: String) {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: launchCountKey(for: instanceID)) + 1, forKey: launchCountKey(for: instanceID))
    }

    static func migrate(from oldID: String, to newID: String) {
        guard oldID != newID else { return }
        let defaults = UserDefaults.standard
        let oldDescKey = descriptionKey(for: oldID)
        let oldFavoriteKey = favoriteKey(for: oldID)
        let oldCategoryKey = categoryKey(for: oldID)
        let oldIconKey = iconKey(for: oldID)
        let oldLaunchCountKey = launchCountKey(for: oldID)
        let newDescKey = descriptionKey(for: newID)
        let newFavoriteKey = favoriteKey(for: newID)
        let newCategoryKey = categoryKey(for: newID)
        let newIconKey = iconKey(for: newID)
        let newLaunchCountKey = launchCountKey(for: newID)

        if let desc = defaults.string(forKey: oldDescKey) {
            defaults.set(desc, forKey: newDescKey)
            defaults.removeObject(forKey: oldDescKey)
        }
        if defaults.object(forKey: oldFavoriteKey) != nil {
            defaults.set(defaults.bool(forKey: oldFavoriteKey), forKey: newFavoriteKey)
            defaults.removeObject(forKey: oldFavoriteKey)
        }
        if let category = defaults.string(forKey: oldCategoryKey) {
            defaults.set(category, forKey: newCategoryKey)
            defaults.removeObject(forKey: oldCategoryKey)
        }
        if let icon = defaults.string(forKey: oldIconKey) {
            defaults.set(icon, forKey: newIconKey)
            defaults.removeObject(forKey: oldIconKey)
        }
        if defaults.object(forKey: oldLaunchCountKey) != nil {
            defaults.set(defaults.integer(forKey: oldLaunchCountKey), forKey: newLaunchCountKey)
            defaults.removeObject(forKey: oldLaunchCountKey)
        }
    }
}
