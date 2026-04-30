import Foundation
import Core

enum InstancePageLoader {
    static func loadInstance(_ id: String) -> MinecraftInstance? {
        try? InstanceManager.shared.loadInstance(id)
    }

    static func fileSizeString(_ byteSize: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }

    static func folderSize(at url: URL) -> Int64 {
        InstanceFileBrowserService.directoryByteSize(at: url)
    }
}
