import Foundation
import Core

enum SaveClipboardService {
    private static let clipboardRootURL: URL = URLConstants.tempURL.appending(path: "save-clipboard")

    static func copySave(at sourceURL: URL) throws {
        clearClipboard()
        try FileManager.default.createDirectory(at: clipboardRootURL, withIntermediateDirectories: true)

        let destinationURL = clipboardRootURL.appending(path: sourceURL.lastPathComponent)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    static func copiedSaves() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: clipboardRootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]))?
            .filter {
                let values = try? $0.resourceValues(forKeys: [.isDirectoryKey])
                return values?.isDirectory == true
            } ?? []
    }

    static var hasCopiedSaves: Bool {
        !copiedSaves().isEmpty
    }

    static func clearClipboard() {
        try? FileManager.default.removeItem(at: clipboardRootURL)
    }
}
