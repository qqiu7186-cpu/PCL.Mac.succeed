import Foundation
import Core
import Combine

@MainActor
protocol SettingsLogExporting {
    func exportLogs() throws -> URL
}

@MainActor
protocol AppUpdateFlowRunning {
    func runInteractiveUpdateFlow(manually: Bool)
}

@MainActor
protocol AppUpdateSettingsControlling: AnyObject, AppUpdateFlowRunning {
    var canUseSparkle: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var allowsAutomaticDownloads: Bool { get }
    var selectedChannelIdentifier: String? { get set }
    var currentFeedURLString: String? { get }
    func openReleaseNotesPage()
}

@MainActor
protocol JavaDownloadPrompting {
    func selectJavaDownload(from downloads: [JavaDownloadPackage], itemBuilder: (JavaDownloadPackage) -> ListItem) async -> Int?
}

@MainActor
protocol TaskExecuting {
    func execute(_ task: MyTask<JavaInstallTask.Model>)
}

@MainActor
protocol TaskRouteNavigating {
    func showTasksPage()
}

@MainActor
protocol JavaRuntimeManaging {
    var javaRuntimesPublisher: Published<[JavaRuntime]>.Publisher { get }
    func research() throws
    func allJavaRuntimes() throws -> [JavaRuntime]
    func isBrokenRuntime(_ runtime: JavaRuntime) -> Bool
}

extension SettingsViewModel: SettingsLogExporting {}
extension UpdateService: AppUpdateFlowRunning {}
extension UpdateService: AppUpdateSettingsControlling {}

@MainActor
extension JavaManager: JavaRuntimeManaging {
    var javaRuntimesPublisher: Published<[JavaRuntime]>.Publisher { $javaRuntimes }
}

@MainActor
final class SharedJavaDownloadPrompter: JavaDownloadPrompting {
    func selectJavaDownload(from downloads: [JavaDownloadPackage], itemBuilder: (JavaDownloadPackage) -> ListItem) async -> Int? {
        await MessageBoxManager.shared.showListAsync(
            title: "选择 Java 版本",
            items: downloads.map(itemBuilder)
        )
    }
}

@MainActor
final class SharedTaskExecutor: TaskExecuting {
    func execute(_ task: MyTask<JavaInstallTask.Model>) {
        TaskManager.shared.execute(task: task)
    }
}

@MainActor
final class SharedTaskRouteNavigator: TaskRouteNavigating {
    func showTasksPage() {
        AppRouter.shared.append(.tasks)
    }
}
