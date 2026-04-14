import Foundation

enum InstanceMetadataService {
    private static func descriptionKey(for instanceID: String) -> String {
        "instance.meta.desc.\(instanceID)"
    }

    private static func favoriteKey(for instanceID: String) -> String {
        "instance.meta.favorite.\(instanceID)"
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
    }

    static func migrate(from oldID: String, to newID: String) {
        guard oldID != newID else { return }
        let defaults = UserDefaults.standard
        let oldDescKey = descriptionKey(for: oldID)
        let oldFavoriteKey = favoriteKey(for: oldID)
        let newDescKey = descriptionKey(for: newID)
        let newFavoriteKey = favoriteKey(for: newID)

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
