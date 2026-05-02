import AppKit
import Foundation
import ImageIO
import Core

actor RemoteImageService {
    static let shared = RemoteImageService()

    private let imageCache = MemoryCache<String, NSImage>(countLimit: 256)
    private var inFlightTasks: [String: Task<Data, Error>] = [:]
    private let session: URLSession

    init() {
        let configuration: URLSessionConfiguration = .ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.httpMaximumConnectionsPerHost = 8
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        session = .init(configuration: configuration)
    }

    func cachedImage(for url: URL, targetSize: CGSize?) -> NSImage? {
        imageCache.object(forKey: cacheKey(for: url, targetSize: targetSize))
    }

    func image(for url: URL, targetSize: CGSize?) async throws -> NSImage {
        let key = cacheKey(for: url, targetSize: targetSize)
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        if let task = inFlightTasks[key] {
            let data = try await task.value
            let image = try decodeImage(from: data, targetSize: targetSize)
            imageCache.setValue(image, for: key)
            return image
        }

        let task = Task<Data, Error> {
            let request = try configuredRequest(for: url)
            let (data, _) = try await session.data(for: request)
            return data
        }
        inFlightTasks[key] = task
        defer { inFlightTasks[key] = nil }
        let data = try await task.value
        let image = try decodeImage(from: data, targetSize: targetSize)
        imageCache.setValue(image, for: key)
        return image
    }

    private func configuredRequest(for url: URL) throws -> URLRequest {
        try validate(url: url)
        var request = URLRequest(url: url)
        request.setValue("PCL-Mac/\(Metadata.appVersion)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return request
    }

    private func validate(url: URL) throws {
        guard url.scheme?.lowercased() == "https" else {
            throw SimpleError("图片链接不安全，已拒绝加载。")
        }
        guard let host = url.host?.lowercased(), isAllowedHost(host) else {
            throw SimpleError("图片来源不受信任，已拒绝加载。")
        }
    }

    private func isAllowedHost(_ host: String) -> Bool {
        host == "modrinth.com" ||
        host.hasSuffix(".modrinth.com") ||
        host == "forgecdn.net" ||
        host.hasSuffix(".forgecdn.net") ||
        host == "curseforge.com" ||
        host.hasSuffix(".curseforge.com") ||
        host == "cylorine.studio" ||
        host.hasSuffix(".cylorine.studio")
    }

    private func cacheKey(for url: URL, targetSize: CGSize?) -> String {
        guard let targetSize else { return url.absoluteString }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let width = Int(max(targetSize.width * scale, 1).rounded(.up))
        let height = Int(max(targetSize.height * scale, 1).rounded(.up))
        return "\(url.absoluteString)#\(width)x\(height)"
    }

    private func decodeImage(from data: Data, targetSize: CGSize?) throws -> NSImage {
        if let targetSize,
           let downsampled = downsampledImage(from: data, targetSize: targetSize) {
            return downsampled
        }
        guard let image = NSImage(data: data) else {
            throw SimpleError("解码 NSImage 失败。")
        }
        return image
    }

    private func downsampledImage(from data: Data, targetSize: CGSize) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let maxPixelSize = max(targetSize.width, targetSize.height) * scale
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(Int(maxPixelSize.rounded(.up)), 1)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: targetSize)
    }
}
