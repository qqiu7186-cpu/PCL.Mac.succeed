//
//  SingleFileDownloader.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/11/22.
//

import Foundation

/// 单文件下载器。
public enum SingleFileDownloader {
    public static let session: URLSession = .init(configuration: .default, delegate: DownloadDelegate.shared, delegateQueue: DownloadDelegate.queue)
    private static let maxRetryCount: Int = 3
    
    public static func download(_ item: DownloadItem, replaceMethod: ReplaceMethod, progressHandler: (@MainActor (Double) -> Void)? = nil) async throws {
        try await download(urls: item.urls, mirrorKey: item.mirrorKey, destination: item.destination, sha1: item.sha1, executable: item.executable, replaceMethod: replaceMethod, progressHandler: progressHandler)
    }
    
    public static func download(
        url: URL,
        destination: URL,
        sha1: String?,
        executable: Bool = false,
        replaceMethod: ReplaceMethod,
        progressHandler: (@MainActor (Double) -> Void)? = nil
    ) async throws {
        try await download(urls: [url], destination: destination, sha1: sha1, executable: executable, replaceMethod: replaceMethod, progressHandler: progressHandler)
    }

    public static func download(
        urls: [URL],
        mirrorKey: String? = nil,
        destination: URL,
        sha1: String?,
        executable: Bool = false,
        replaceMethod: ReplaceMethod,
        progressHandler: (@MainActor (Double) -> Void)? = nil
    ) async throws {
        // 文件已存在处理
        if FileManager.default.fileExists(atPath: destination.path) {
            if let sha1, try FileUtils.sha1(of: destination) != sha1 {
                try FileManager.default.removeItem(at: destination)
            } else {
                switch replaceMethod {
                case .replace:
                    try FileManager.default.removeItem(at: destination)
                case .skip:
                    await progressHandler?(1)
                    return
                case .throw:
                    throw DownloadError.fileExists
                }
            }
        } else {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        let selectorKey = mirrorKey ?? "download.file.\(destination.path)"
        let candidates = NetworkMirrorSelector.prioritize(deduplicated(urls), key: selectorKey)
        var lastError: Error?
        for candidateURL in candidates {
            for attempt in 0...maxRetryCount {
                do {
                    try Task.checkCancellation()
                    var request: URLRequest = .init(url: candidateURL)
                    request.httpMethod = "GET"
                    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                    request.setValue("PCL-Mac/\(Metadata.appVersion)", forHTTPHeaderField: "User-Agent")

                    let task: URLSessionDownloadTask = session.downloadTask(with: request)
                    try await withTaskCancellationHandler {
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                            DownloadDelegate.shared.register(task: task, destination: destination, continuation: continuation, progressHandler: progressHandler)
                            task.resume()
                        }
                    } onCancel: {
                        task.cancel()
                    }

                    // 验证 SHA-1
                    if let sha1 {
                        guard try FileUtils.sha1(of: destination) == sha1 else {
                            try FileManager.default.removeItem(at: destination)
                            throw DownloadError.checksumMismatch
                        }
                    }
                    if executable {
                        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
                    }
                    NetworkMirrorSelector.markSuccess(candidateURL, key: selectorKey)
                    return
                } catch {
                    lastError = error
                    if error is CancellationError {
                        throw error
                    }
                    guard shouldRetry(error: error), attempt < maxRetryCount else {
                        break
                    }
                    let remaining = maxRetryCount - attempt
                    log("下载失败，准备重试（剩余 \(remaining) 次）：\(candidateURL.absoluteString) - \(error.localizedDescription)")
                    try? FileManager.default.removeItem(at: destination)
                    let delay: UInt64 = UInt64(1 << attempt) * 1_000_000_000
                    try await Task.sleep(nanoseconds: delay)
                }
            }
            log("下载源失败，尝试切换镜像：\(candidateURL.absoluteString)")
            try? FileManager.default.removeItem(at: destination)
        }

        throw lastError ?? DownloadError.unknownError
    }

    private static func shouldRetry(error: Error) -> Bool {
        if error is CancellationError {
            return false
        }
        if let urlError = error as? URLError {
            return urlError.code != .cancelled
        }
        if let downloadError = error as? DownloadError {
            switch downloadError {
            case .badStatusCode(let code):
                return (500..<600).contains(code)
            case .unknownError:
                return true
            case .fileExists, .checksumMismatch:
                return false
            }
        }
        if let requestError = error as? RequestError {
            return requestError == .badResponse
        }
        return false
    }

    private static func deduplicated(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        var result: [URL] = []
        for url in urls {
            let value = url.absoluteString
            if seen.contains(value) { continue }
            seen.insert(value)
            result.append(url)
        }
        return result
    }
}
