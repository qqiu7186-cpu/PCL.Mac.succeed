import Foundation

enum InstanceFileBrowserService {
    static func listDirectory(
        at url: URL,
        including keys: [URLResourceKey] = [],
        options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
    ) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: options)) ?? []
    }

    static func ensureDirectoryExists(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func resourceValues(for url: URL, keys: Set<URLResourceKey>) -> URLResourceValues? {
        try? url.resourceValues(forKeys: keys)
    }

    static func directoryByteSize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    static func saveDirectoryURLs(at url: URL) -> [(url: URL, createdAt: Date?, modifiedAt: Date?)] {
        listDirectory(at: url, including: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey])
            .compactMap { itemURL in
                let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey])
                guard values?.isDirectory == true else { return nil }
                return (itemURL, values?.creationDate, values?.contentModificationDate)
            }
    }

    static func backupZipURLs(at url: URL) -> [(url: URL, modifiedAt: Date?, byteSize: Int64)] {
        listDirectory(at: url, including: [.contentModificationDateKey, .fileSizeKey])
            .filter { $0.pathExtension.lowercased() == "zip" }
            .map { itemURL in
                let values = try? itemURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                return (itemURL, values?.contentModificationDate, Int64(values?.fileSize ?? 0))
            }
    }

    static func datapackEntries(at url: URL) -> [(url: URL, modifiedAt: Date?, isDirectory: Bool, byteSize: Int64)] {
        listDirectory(at: url, including: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey])
            .compactMap { itemURL in
                let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey])
                let isDirectory = values?.isDirectory == true
                let isZip = itemURL.pathExtension.lowercased() == "zip"
                guard isDirectory || isZip else { return nil }
                let byteSize = isDirectory ? 0 : Int64(values?.fileSize ?? 0)
                return (itemURL, values?.contentModificationDate, isDirectory, byteSize)
            }
    }

    static func resourceFileEntries(at url: URL) -> [(url: URL, modifiedAt: Date?, byteSize: Int64)] {
        listDirectory(at: url, including: [.contentModificationDateKey, .fileSizeKey])
            .map { itemURL in
                let values = try? itemURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                return (itemURL, values?.contentModificationDate, Int64(values?.fileSize ?? 0))
            }
    }
}
