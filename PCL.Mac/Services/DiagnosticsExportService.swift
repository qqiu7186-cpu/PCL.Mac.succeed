import Foundation
import AppKit
import Core

@MainActor
enum DiagnosticsExportService {
    static let liveSnapshotProvider: DiagnosticsSnapshotProviding = LiveDiagnosticsSnapshotProvider()

    static func exportToUserSelectedDirectory() async throws -> URL {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "导出"
        panel.message = "选择一个目录，用于导出诊断信息与日志。"

        guard panel.runModal() == .OK, let destinationDirectory = panel.url else {
            throw SimpleError("已取消导出。")
        }

        return try export(to: destinationDirectory, snapshotProvider: liveSnapshotProvider)
    }

    static func export(to destinationDirectory: URL, snapshotProvider: DiagnosticsSnapshotProviding) throws -> URL {
        let exportDirectory = try LogManager.shared.exportLogs(to: destinationDirectory)
        let reportURL = exportDirectory.appending(path: "diagnostics.json")

        let reportData = try JSONEncoder.shared.encode(snapshotProvider.snapshot())
        try reportData.write(to: reportURL)
        return exportDirectory
    }
}
