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
    private static let javaRuntimeListMirrorKey: String = "java-runtime-all-json"
    private static let supportedJavaMajors: ClosedRange<Int> = 8...26
    private static let azulMetadataBaseURL = "https://api.azul.com/metadata/v1/zulu/packages/"
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
    
    public func javaDownloads(forArchitecture architecture: Architecture = .systemArchitecture(), preferredMajor: Int = 21) async throws -> [JavaDownloadPackage] {
        async let mojangDownloadsTask: [JavaDownloadPackage] = {
            do {
                return try await fetchMojangJavaDownloads(forArchitecture: architecture)
            } catch {
                warn("Mojang Java 列表获取失败，已回退其他源：\(error.localizedDescription)")
                return []
            }
        }()
        async let azulDownloadsTask: [JavaDownloadPackage] = {
            do {
                return try await fetchAzulJavaDownloads(forArchitecture: architecture)
            } catch {
                warn("Zulu Java 列表获取失败：\(error.localizedDescription)")
                return []
            }
        }()

        let mojangDownloads = await mojangDownloadsTask
        let azulDownloads = await azulDownloadsTask

        let merged = mergeDownloads(primary: mojangDownloads, secondary: azulDownloads)
        guard !merged.isEmpty else {
            throw SimpleError("无法获取可下载的 Java 版本列表")
        }

        return merged.sorted { lhs, rhs in
            let lhsMajor = lhs.majorVersion
            let rhsMajor = rhs.majorVersion
            let lhsPre = isPrerelease(lhs.version)
            let rhsPre = isPrerelease(rhs.version)

            let lhsGroup = versionPriorityGroup(lhsMajor, preferredMajor: preferredMajor)
            let rhsGroup = versionPriorityGroup(rhsMajor, preferredMajor: preferredMajor)
            if lhsGroup != rhsGroup { return lhsGroup < rhsGroup }

            if lhsPre != rhsPre { return rhsPre }

            if lhsMajor != rhsMajor {
                if lhsGroup == 1 {
                    return lhsMajor < rhsMajor
                }
                return lhsMajor > rhsMajor
            }

            if lhs.provider != rhs.provider {
                return lhs.provider == .mojang
            }

            return lhs.version.compare(rhs.version, options: .numeric) == .orderedDescending
        }
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

    private func fetchMojangJavaDownloads(forArchitecture architecture: Architecture) async throws -> [JavaDownloadPackage] {
        let list: MojangJavaList = try await fetchJavaRuntimeList()
        let platformKey: String = architecture == .arm64 ? "mac-os-arm64" : "mac-os"
        let downloads = (list.entries[platformKey] ?? [:]).flatMap { $0.value }

        let bestDownloadByMajor: [Int: MojangJavaList.JavaDownload] = Dictionary(grouping: downloads, by: { javaMajorVersion($0.version) })
            .compactMapValues { versions in
                versions.sorted(by: isBetterDownload(_:_:)).first
            }

        return bestDownloadByMajor.compactMap { major, download in
            guard Self.supportedJavaMajors.contains(major) else { return nil }
            return JavaDownloadPackage(
                provider: .mojang,
                majorVersion: major,
                version: download.version,
                architecture: architecture,
                releaseTime: download.releaseTime,
                payload: .mojangManifest(download)
            )
        }
    }

    private func fetchAzulJavaDownloads(forArchitecture architecture: Architecture) async throws -> [JavaDownloadPackage] {
        try await withThrowingTaskGroup(of: JavaDownloadPackage?.self) { group in
            for major in Self.supportedJavaMajors {
                group.addTask {
                    try await self.fetchAzulJavaDownload(majorVersion: major, architecture: architecture)
                }
            }

            var result: [JavaDownloadPackage] = []
            for try await package in group {
                if let package {
                    result.append(package)
                }
            }
            return result
        }
    }

    private func fetchAzulJavaDownload(majorVersion: Int, architecture: Architecture) async throws -> JavaDownloadPackage? {
        let params: [String: String?] = [
            "java_version": String(majorVersion),
            "os": "macos",
            "arch": architecture == .arm64 ? "arm" : "x86",
            "java_package_type": "jdk",
            "release_status": "ga",
            "availability_types": "CA",
            "certifications": "tck",
            "archive_type": "zip",
            "latest": "true",
            "page": "1",
            "page_size": "1"
        ]

        let packages: [AzulZuluPackage]
        do {
            packages = try await Requests.get(Self.azulMetadataBaseURL, params: params).decode([AzulZuluPackage].self)
        } catch {
            warn("Zulu Java \(majorVersion) 清单请求失败：\(error.localizedDescription)")
            return nil
        }

        guard let package = packages.first else {
            return nil
        }

        return JavaDownloadPackage(
            provider: .azulZulu,
            majorVersion: majorVersion,
            version: package.versionString,
            architecture: architecture,
            releaseTime: .distantPast,
            payload: .zipArchive(url: package.downloadURL)
        )
    }

    private func mergeDownloads(primary: [JavaDownloadPackage], secondary: [JavaDownloadPackage]) -> [JavaDownloadPackage] {
        var merged: [Int: JavaDownloadPackage] = [:]
        for package in secondary {
            merged[package.majorVersion] = package
        }
        for package in primary {
            merged[package.majorVersion] = package
        }
        return Array(merged.values)
    }

    private func fetchJavaRuntimeList() async throws -> MojangJavaList {
        let candidates = NetworkMirrorSelector.prioritize(JavaRuntimeMirrorResolver.runtimeListURLs, key: Self.javaRuntimeListMirrorKey)
        var lastError: Error?
        for url in candidates {
            do {
                let list: MojangJavaList = try await Requests.get(url.absoluteString).decode(MojangJavaList.self)
                NetworkMirrorSelector.markSuccess(url, key: Self.javaRuntimeListMirrorKey)
                return list
            } catch {
                lastError = error
                warn("Java 运行时清单请求失败（\(url.host ?? url.absoluteString)）：\(error.localizedDescription)")
            }
        }
        throw lastError ?? SimpleError("无法获取 Java 运行时清单")
    }

    private func isBetterDownload(_ lhs: MojangJavaList.JavaDownload, _ rhs: MojangJavaList.JavaDownload) -> Bool {
        let lhsPre = isPrerelease(lhs.version)
        let rhsPre = isPrerelease(rhs.version)
        if lhsPre != rhsPre {
            return !lhsPre
        }
        return lhs.version.compare(rhs.version, options: .numeric) == .orderedDescending
    }

    private func javaMajorVersion(_ version: String) -> Int {
        let parts = version.split(separator: ".")
        guard let first = parts.first else { return 0 }
        if first == "1", parts.count > 1 {
            return leadingNumber(in: String(parts[1])) ?? 0
        }
        return leadingNumber(in: String(first)) ?? 0
    }

    private func isPrerelease(_ version: String) -> Bool {
        let lowered = version.lowercased()
        return lowered.contains("ea") || lowered.contains("beta") || lowered.contains("preview") || lowered.contains("rc")
    }

    private func versionPriorityGroup(_ major: Int, preferredMajor: Int) -> Int {
        if major == preferredMajor { return 0 }
        if major > preferredMajor { return 1 }
        return 2
    }

    private func leadingNumber(in value: String) -> Int? {
        let digits = value.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }
}
