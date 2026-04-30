//
//  JavaSettingsViewModel.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/6.
//

import Foundation
import Core
import Combine

@MainActor
class JavaSettingsViewModel: ObservableObject {
    private static let dateFormatter: DateFormatter = {
        let formatter: DateFormatter = .init()
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter
    }()
    
    @Published public var javaList: [ListItem] = []
    
    private var cancellables: [AnyCancellable] = []
    private let javaManager: JavaRuntimeManaging
    private let javaDownloadPrompter: JavaDownloadPrompting
    private let taskExecutor: TaskExecuting
    private let taskNavigator: TaskRouteNavigating
    var javaDownloadsProvider: (Architecture, Int, Bool) async throws -> [JavaDownloadPackage]
    
    init(
        javaManager: JavaRuntimeManaging = JavaManager.shared,
        javaDownloadPrompter: JavaDownloadPrompting? = nil,
        taskExecutor: TaskExecuting? = nil,
        taskNavigator: TaskRouteNavigating? = nil
    ) {
        self.javaManager = javaManager
        self.javaDownloadPrompter = javaDownloadPrompter ?? SharedJavaDownloadPrompter()
        self.taskExecutor = taskExecutor ?? SharedTaskExecutor()
        self.taskNavigator = taskNavigator ?? SharedTaskRouteNavigator()
        self.javaDownloadsProvider = { architecture, preferredMajor, includeAllProviders in
            try await JavaDownloadCatalogService.javaDownloads(
                forArchitecture: architecture,
                preferredMajor: preferredMajor,
                includeAllProviders: includeAllProviders
            )
        }
        javaManager.javaRuntimesPublisher
            .sink { [weak self] _ in
                self?.reloadJavaList()
            }
            .store(in: &cancellables)

        reloadJavaList()
    }

    public func reloadJavaList() {
        DispatchQueue.global(qos: .userInitiated).async {
            let runtimes: [JavaRuntime]
            do {
                runtimes = try self.javaManager.allJavaRuntimes()
            } catch {
                err("加载 Java 列表失败：\(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.javaList = []
                }
                return
            }

            let sorted = runtimes.sorted { lhs, rhs in
                if lhs.majorVersion != rhs.majorVersion { return lhs.majorVersion > rhs.majorVersion }
                return lhs.version.compare(rhs.version, options: .numeric) == .orderedDescending
            }

            let items: [ListItem] = sorted.map { runtime in
                let broken: Bool = self.javaManager.isBrokenRuntime(runtime)
                let suffix: String = broken ? "（不可用：此前预检失败）" : "（可用）"
                return ListItem(
                    name: "\(runtime.description) \(suffix)",
                    description: runtime.executableURL.path
                )
            }

            DispatchQueue.main.async {
                self.javaList = items
            }
        }
    }
    
    public func javaDownloads(
        forArchitecture architecture: Architecture = .systemArchitecture(),
        preferredMajor: Int = 21,
        includeAllProviders: Bool = false
    ) async throws -> [JavaDownloadPackage] {
        try await javaDownloadsProvider(architecture, preferredMajor, includeAllProviders)
    }
    
    public func listItem(forJavaDownload javaDownload: JavaDownloadPackage) -> ListItem {
        let description: String
        if javaDownload.releaseTime == .distantPast {
            description = "\(javaDownload.displaySourceName) · 版本 \(javaDownload.version)"
        } else {
            description = "\(javaDownload.displaySourceName) · 最新版本 \(javaDownload.version) · 更新于 \(Self.dateFormatter.string(from: javaDownload.releaseTime))"
        }
        return .init(
            name: "Java \(javaDownload.majorVersion)",
            description: description
        )
    }

    public func refreshJavaList() throws {
        try javaManager.research()
        reloadJavaList()
    }

    @MainActor
    public func startInstallJavaFlow() async throws {
        let downloads = try await javaDownloads()
        guard let index = await javaDownloadPrompter.selectJavaDownload(from: downloads, itemBuilder: listItem(forJavaDownload:)) else {
            return
        }
        taskExecutor.execute(JavaInstallTask.create(download: downloads[index], replaceExisting: true))
        taskNavigator.showTasksPage()
    }

}
