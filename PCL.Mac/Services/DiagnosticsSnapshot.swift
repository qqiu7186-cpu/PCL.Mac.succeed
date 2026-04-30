import Foundation
import Core

struct DiagnosticsSnapshot: Codable, Equatable {
    struct RepositoryInfo: Codable, Equatable {
        let name: String
        let path: String
    }

    struct InstanceInfo: Codable, Equatable {
        let name: String
        let version: String
        let directory: String
    }

    let appVersion: String
    let bundleVersion: String
    let timestamp: String
    let systemVersion: String
    let currentRoute: String
    let repository: RepositoryInfo?
    let instance: InstanceInfo?
    let taskCount: Int
}

protocol DiagnosticsSnapshotProviding {
    @MainActor func snapshot() -> DiagnosticsSnapshot
}

struct LiveDiagnosticsSnapshotProvider: DiagnosticsSnapshotProviding {
    @MainActor
    func snapshot() -> DiagnosticsSnapshot {
        let currentRepository = InstanceManager.shared.currentRepository
        let currentInstance = InstanceManager.shared.currentInstance
        let currentRoute = AppRouter.shared.getLast()

        return DiagnosticsSnapshot(
            appVersion: Metadata.appVersion,
            bundleVersion: String(Metadata.bundleVersion),
            timestamp: ISO8601DateFormatter().string(from: .now),
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            currentRoute: currentRoute.stringValue,
            repository: currentRepository.map { .init(name: $0.name, path: $0.url.path) },
            instance: currentInstance.map { .init(name: $0.name, version: $0.version.id, directory: $0.runningDirectory.path) },
            taskCount: TaskManager.shared.tasks.count
        )
    }
}
