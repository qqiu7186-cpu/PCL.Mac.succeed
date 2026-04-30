import Foundation
import Core

@MainActor
protocol InstallRouteNavigating {
    func showTasksPageIfNeeded()
    func showTasksPage()
    func dismissInstallOptionsIfNeeded()
    func openProjectInstall(_ target: ProjectInstallTarget)
}

@MainActor
protocol InstallTaskDispatching {
    var hasRunningInstallTask: Bool { get }
    func executeMinecraftInstall(_ task: MyTask<MinecraftInstallTask.Model>, completion: @escaping (Error?) -> Void)
    func executeResourceTask(_ task: MyTask<EmptyModel>)
    func executeModpackInstallTask(_ task: MyTask<ModrinthModpackInstallTask.Model>)
    func executeDownloadTask(_ task: MyTask<EmptyModel>) -> Task<Void, Error>
}

@MainActor
protocol InstallPrompting {
    func showError(title: String, content: String) async
    func showConfirm(title: String, content: String, level: MessageBoxModel.Level, cancelLabel: String, confirmLabel: String, confirmType: MyButton.`Type`) async -> Bool
    func showInput(title: String, initialContent: String?) async -> String?
}

@MainActor
final class SharedInstallRouteNavigator: InstallRouteNavigating {
    func showTasksPageIfNeeded() {
        if AppRouter.shared.getLast() != .tasks {
            AppRouter.shared.append(.tasks)
        }
    }

    func showTasksPage() {
        AppRouter.shared.append(.tasks)
    }

    func dismissInstallOptionsIfNeeded() {
        if AppRouter.shared.getLast() == .tasks {
            AppRouter.shared.removeLast()
            if case .minecraftInstallOptions = AppRouter.shared.getLast() {
                AppRouter.shared.removeLast()
            }
        }
    }

    func openProjectInstall(_ target: ProjectInstallTarget) {
        AppRouter.shared.append(.projectInstall(target))
    }
}

@MainActor
final class SharedInstallTaskDispatcher: InstallTaskDispatching {
    var hasRunningInstallTask: Bool {
        TaskManager.shared.tasks.contains { $0.name.contains("安装") || $0.name.contains("下载") }
    }

    func executeMinecraftInstall(_ task: MyTask<MinecraftInstallTask.Model>, completion: @escaping (Error?) -> Void) {
        TaskManager.shared.execute(task: task, completion: completion)
    }

    func executeResourceTask(_ task: MyTask<EmptyModel>) {
        TaskManager.shared.execute(task: task)
    }

    func executeModpackInstallTask(_ task: MyTask<ModrinthModpackInstallTask.Model>) {
        TaskManager.shared.execute(task: task)
    }

    func executeDownloadTask(_ task: MyTask<EmptyModel>) -> Task<Void, Error> {
        TaskManager.shared.execute(task: task)
    }
}

@MainActor
final class SharedInstallPrompter: InstallPrompting {
    func showError(title: String, content: String) async {
        await MessageBoxManager.shared.showErrorAsync(title: title, content: content)
    }

    func showConfirm(title: String, content: String, level: MessageBoxModel.Level = .info, cancelLabel: String = "取消", confirmLabel: String = "确认", confirmType: MyButton.`Type` = .highlight) async -> Bool {
        await MessageBoxManager.shared.showConfirmAsync(title: title, content: content, level: level, cancelLabel: cancelLabel, confirmLabel: confirmLabel, confirmType: confirmType)
    }

    func showInput(title: String, initialContent: String?) async -> String? {
        await MessageBoxManager.shared.showInputAsync(title: title, initialContent: initialContent)
    }
}
