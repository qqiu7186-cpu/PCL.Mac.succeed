//
//  JavaSettingsViewModel.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/6.
//

import Foundation
import Core
import Combine

class JavaSettingsViewModel: ObservableObject {
    private static let dateFormatter: DateFormatter = {
        let formatter: DateFormatter = .init()
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter
    }()
    
    @Published public var javaList: [ListItem] = []
    
    private var cancellables: [AnyCancellable] = []
    
    init() {
        JavaManager.shared.$javaRuntimes
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
                runtimes = try JavaManager.shared.allJavaRuntimes()
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
                let broken: Bool = JavaManager.shared.isBrokenRuntime(runtime)
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
        try await JavaDownloadCatalogService.javaDownloads(
            forArchitecture: architecture,
            preferredMajor: preferredMajor,
            includeAllProviders: includeAllProviders
        )
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

}
