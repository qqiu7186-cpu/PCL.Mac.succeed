import Foundation

final class MemoryCache<Key: Hashable, Value> {
    private let cache = NSCache<WrappedKey, Entry>()

    init(countLimit: Int, totalCostLimit: Int = 0) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    func object(forKey key: Key) -> Value? {
        cache.object(forKey: WrappedKey(key))?.value
    }

    func setValue(_ value: Value, for key: Key, cost: Int = 0) {
        cache.setObject(Entry(value), forKey: WrappedKey(key), cost: cost)
    }

    private final class Entry {
        let value: Value

        init(_ value: Value) {
            self.value = value
        }
    }

    private final class WrappedKey: NSObject {
        let key: Key

        init(_ key: Key) {
            self.key = key
        }

        override var hash: Int { key.hashValue }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? WrappedKey else { return false }
            return other.key == key
        }
    }
}
