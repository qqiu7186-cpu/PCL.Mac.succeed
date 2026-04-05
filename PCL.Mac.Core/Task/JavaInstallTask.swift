//
//  JavaInstallTask.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/11.
//

import Foundation
import ZIPFoundation

public enum JavaInstallTask {
    public static func create(
        download: JavaDownloadPackage,
        replaceExisting: Bool = false
    ) -> MyTask<Model> {
        let tempDirectory: URL = URLConstants.tempURL.appending(path: "JavaInstall-\(UUID().uuidString)")
        let bundleDestination: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Java/JavaVirtualMachines/\(download.installDirectoryName)")
        return .init(
            name: "Java 安装 - \(download.version)", model: .init(),
            .init(0, "获取 Java 清单") { _, model in
                if FileManager.default.fileExists(atPath: bundleDestination.path) {
                    if replaceExisting {
                        try FileManager.default.removeItem(at: bundleDestination)
                    } else {
                        throw SimpleError("已存在版本相同的 Java，可使用覆盖安装。")
                    }
                }
                switch download.payload {
                case .mojangManifest:
                    model.manifest = try await requestJavaManifest(for: download)
                case .zipArchive(let url):
                    model.archiveURL = tempDirectory.appending(path: url.lastPathComponent)
                    model.archiveDownloadURL = url
                }
            },
            .init(1, "下载文件") { task, model in
                try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
                switch download.payload {
                case .mojangManifest:
                    var downloadItems: [DownloadItem] = []
                    for (path, file) in model.manifest.files {
                        switch file {
                        case .directory:
                            try FileManager.default.createDirectory(at: tempDirectory.appending(path: path), withIntermediateDirectories: true)
                        case .file(let url, let sha1, _, let executable):
                            let mirrorKey = sha1.map { "java-runtime.file.\($0)" } ?? "java-runtime.path.\(path)"
                            downloadItems.append(.init(urls: JavaRuntimeMirrorResolver.candidateURLs(for: url), destination: tempDirectory.appending(path: path), sha1: sha1, executable: executable, mirrorKey: mirrorKey))
                    case .link(let target):
                        let parent: URL = tempDirectory.appending(path: path).deletingLastPathComponent()
                        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                        try FileManager.default.createSymbolicLink(atPath: tempDirectory.appending(path: path).path, withDestinationPath: target)
                    }
                }
                try await MultiFileDownloader(items: downloadItems, concurrentLimit: 64, replaceMethod: .skip, progressHandler: task.setProgress(_:)).start()
                case .zipArchive(let url):
                    let archiveURL = try model.archiveURL.unwrap()
                    try await SingleFileDownloader.download(
                        .init(url: url, destination: archiveURL, sha1: nil, mirrorKey: "java-runtime.zip.\(download.provider.rawValue).\(download.majorVersion).\(download.architecture.rawValue)"),
                        replaceMethod: .replace,
                        progressHandler: task.setProgress(_:)
                    )
                }
            },
            .init(2, "__completion", display: false) { _, model in
                let bundleRoot: URL
                switch download.payload {
                case .mojangManifest:
                    bundleRoot = try findJavaBundleRoot(in: tempDirectory)
                case .zipArchive:
                    let archiveURL = try model.archiveURL.unwrap()
                    let extractDirectory = tempDirectory.appending(path: "archive-extracted")
                    try FileManager.default.createDirectory(at: extractDirectory, withIntermediateDirectories: true)
                    try FileManager.default.unzipItem(at: archiveURL, to: extractDirectory)
                    bundleRoot = try findJavaBundleRoot(in: extractDirectory)
                }
                try FileManager.default.createDirectory(at: bundleDestination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: bundleRoot, to: bundleDestination)
                let executableURL = bundleDestination.appending(path: "Contents/Home/bin/java")
                if FileManager.default.fileExists(atPath: executableURL.path) {
                    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
                }
                JavaManager.shared.clearBrokenRuntime(atExecutableURL: executableURL)
                try await JavaManager.shared.research()
            }
        ) { _ in
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }
    
    public class Model: TaskModel {
        public var manifest: MojangJavaManifest!
        public var archiveURL: URL?
        public var archiveDownloadURL: URL?
        
        public init() {}
    }

    private static func requestJavaManifest(for download: JavaDownloadPackage) async throws -> MojangJavaManifest {
        guard case .mojangManifest(let mojangDownload) = download.payload else {
            throw SimpleError("当前 Java 下载项不包含 Mojang 清单")
        }
        let urls = NetworkMirrorSelector.prioritize(JavaRuntimeMirrorResolver.candidateURLs(for: mojangDownload.manifestURL), key: "java-runtime.manifest.\(download.version)")
        var lastError: Error?
        for url in urls {
            do {
                let manifest: MojangJavaManifest = try await Requests.get(url.absoluteString).decode(MojangJavaManifest.self)
                NetworkMirrorSelector.markSuccess(url, key: "java-runtime.manifest.\(download.version)")
                return manifest
            } catch {
                lastError = error
                warn("Java 清单请求失败（\(url.host ?? url.absoluteString)）：\(error.localizedDescription)")
            }
        }
        throw lastError ?? SimpleError("无法获取 Java 安装清单")
    }

    private static func findJavaBundleRoot(in directory: URL) throws -> URL {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            throw SimpleError("无法枚举 Java 压缩包内容")
        }

        for case let fileURL as URL in enumerator {
            let releasePath = fileURL.appending(path: "Contents/Home/release")
            if FileManager.default.fileExists(atPath: releasePath.path) {
                return fileURL
            }
        }
        throw SimpleError("压缩包中未找到有效的 Java 运行时")
    }
}
