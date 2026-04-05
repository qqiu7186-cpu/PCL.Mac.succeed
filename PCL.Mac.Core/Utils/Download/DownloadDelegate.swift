//
//  DownloadDelegate.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/12/16.
//

import Foundation

class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    public static let shared: DownloadDelegate = .init()
    public static let queue: OperationQueue = {
        let queue: OperationQueue = OperationQueue()
        queue.name = "PCL.Mac.DownloadDelegate"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    
    public class DownloadContext {
        public let destination: URL
        public let progressHandler: (@MainActor (Double) -> Void)?
        public var continuation: CheckedContinuation<Void, Error>?
        
        fileprivate init(destination: URL, continuation: CheckedContinuation<Void, Error>, progressHandler: (@MainActor (Double) -> Void)?) {
            self.destination = destination
            self.progressHandler = progressHandler
            self.continuation = continuation
        }
    }
    
    private var contexts: [Int: DownloadContext] = [:]
    private let contextsLock: NSLock = .init()
    
    public func register(
        task: URLSessionDownloadTask,
        destination: URL,
        continuation: CheckedContinuation<Void, Error>,
        progressHandler: (@MainActor (Double) -> Void)?
    ) {
        let context: DownloadContext = .init(destination: destination, continuation: continuation, progressHandler: progressHandler)
        contextsLock.lock()
        contexts[task.taskIdentifier] = context
        contextsLock.unlock()
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let context: DownloadContext = context(for: downloadTask.taskIdentifier) else {
            return
        }
        
        guard let response = downloadTask.response.flatMap({ $0 as? HTTPURLResponse }) else {
            resume(task: downloadTask, with: .failure(RequestError.badResponse))
            return
        }
        guard (200..<300).contains(response.statusCode) else {
            resume(task: downloadTask, with: .failure(DownloadError.badStatusCode(code: response.statusCode)))
            return
        }
        do {
            try FileManager.default.moveItem(at: location, to: context.destination)
        } catch {
            resume(task: downloadTask, with: .failure(error))
            return
        }
        updateProgress(for: downloadTask, with: 1)
        resume(task: downloadTask, with: .success(()))
    }
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        if let error = error as? URLError {
            resume(task: task, with: .failure(SimpleError("下载请求失败（\(error.code.rawValue)）：\(error.localizedDescription)")))
            return
        }
        resume(task: task, with: .failure(error ?? DownloadError.unknownError))
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        DispatchQueue.main.async {
            DownloadSpeedManager.shared.addBytes(bytesWritten)
        }
        if totalBytesExpectedToWrite > 0 {
            updateProgress(for: downloadTask, with: Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }
    }
    
    private func resume(task: URLSessionTask, with value: Result<Void, Error>) {
        contextsLock.lock()
        let context = contexts[task.taskIdentifier]
        contexts.removeValue(forKey: task.taskIdentifier)
        contextsLock.unlock()
        if let context {
            context.continuation?.resume(with: value)
            context.continuation = nil
        }
    }
    
    private func updateProgress(for task: URLSessionTask, with progress: Double) {
        if let context = context(for: task.taskIdentifier), let progressHandler = context.progressHandler {
            DispatchQueue.main.async {
                progressHandler(progress)
            }
        }
    }

    private func context(for identifier: Int) -> DownloadContext? {
        contextsLock.lock()
        defer { contextsLock.unlock() }
        return contexts[identifier]
    }
    
    private override init() {
        super.init()
    }
}
