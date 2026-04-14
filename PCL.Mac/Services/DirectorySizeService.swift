import Foundation

enum DirectorySizeService {
    private static let cache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 256
        return cache
    }()
    private static let actor = DirectorySizeLoader()

    static func cachedSize(for url: URL) -> Int64? {
        cache.object(forKey: url.standardizedFileURL.path as NSString)?.int64Value
    }

    static func loadSize(for url: URL) async -> Int64 {
        let key = url.standardizedFileURL.path as NSString
        if let cached = cache.object(forKey: key) {
            return cached.int64Value
        }

        if let task = await actor.task(for: url) {
            return await task.value
        }

        let task = Task<Int64, Never> {
            let size = calculateDirectorySize(at: url)
            cache.setObject(NSNumber(value: size), forKey: key)
            await actor.removeTask(for: url)
            return size
        }

        await actor.setTask(task, for: url)
        return await task.value
    }

    private static func calculateDirectorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }

        var size: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                size += Int64(values?.fileSize ?? 0)
            }
        }
        return size
    }
}

private actor DirectorySizeLoader {
    private var tasks: [String: Task<Int64, Never>] = [:]

    func task(for url: URL) -> Task<Int64, Never>? {
        tasks[url.standardizedFileURL.path]
    }

    func setTask(_ task: Task<Int64, Never>, for url: URL) {
        tasks[url.standardizedFileURL.path] = task
    }

    func removeTask(for url: URL) {
        tasks[url.standardizedFileURL.path] = nil
    }
}
