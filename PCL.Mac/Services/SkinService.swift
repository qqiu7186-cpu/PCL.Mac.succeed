import Foundation
import Core
import AppKit
import SwiftyJSON

enum SkinService {
    static let defaultSkinData: Data = .init(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAMAAACdt4HsAAAAdVBMVEUAAAAKvLwAzMwmGgokGAgrHg0zJBE/KhW3g2uzeV5SPYn///+qclmbY0mQWT8Af38AaGhVVVWUYD52SzOBUzmPXj5JJRBCHQp3QjVqQDA0JRIoKCg3Nzc/Pz9KSko6MYlBNZtGOqUDenoFiIgElZUApKQAr6/wvakZAAAAAXRSTlMAQObYZgAAAolJREFUeNrt1l1rHucZReFrj/whu5hSCCQtlOTE/f+/Jz4q9Cu0YIhLcFVpVg+FsOCVehi8jmZgWOzZz33DM4CXlum3gH95GgeAzQZVeL4gTm6Cbp4vqFkD8HwBazPY8wWbMq9utu3mNZ5fotVezbzOE3kBEFbaZuc8kb00NTMUbWJp678Xf2GV7RRtx1TDQQ6XBNvsmL2+2vHq1TftmMPIyAWujtN2cl274ua2jpVpZneXEjjo7XW1q53V9ds4ODO5xIuhvGHvfLI3aixauig415uuO2+vl9+cncfsFw25zL650fXn687jqnXuP68/X3+eV3zE7y6u9eB73MlfAcfbTf3yR8CfAX+if8S/H5/EAbAxj5LN48tULvEBOh8V1AageMTXe2YHAOwHbZxrzPkSR3+ffr8TR2JDzE/4Fj8CDgEwDsW+q+9GsR07hhg2CsALBgMo2v5wNxXnQXMeGQVW7gUAyKI2m6KDsJ8Au3++F5RZO+kKNQjQcLLWgjwUjBXLltFgWWMUUlviocBgNoxNGgMjSxiYAA7zgLFo2hgIENiDU8gQCzDOmViGFAsEuBcQSDCothhpJaDRA8E5fHqH2nTbYm5fHLo1V0u3B7DAuheoeScRYabjjjuzs17cHVaTrTXmK78m9swP34d9oK/dfeXSIH2PW/MXwPvxN/bJlxw8zlYAcEyeI6gNgA/O8P8neN8xe1IHP2gTzegjvhUDfuRygmwEs2GE4mkCDIAzm2R4yAuPsIdR9k8AvMc+3L9+2UEjo4WP0FpgP19O0MzCsqxIoMsdDBvYcQyGmO0ZJRoYCKjLJWY0BAhYwGUBCgkh8MRdOKt+ruqMwAB2OcEX94U1TPbYJP0PkyyAI1S6cSIAAAAASUVORK5CYII=")!

    private static let skinDataCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 128
        return cache
    }()
    private static let loader = SkinDataLoader()

    static func skinData(for account: Account) async -> Data {
        let cacheKey = account.id.uuidString as NSString
        if let cached = skinDataCache.object(forKey: cacheKey) {
            return cached as Data
        }

        if let existingTask = await loader.task(for: account.id) {
            return await existingTask.value
        }

        let task = Task<Data, Never> {
            let data = await loadSkinData(for: account)
            skinDataCache.setObject(data as NSData, forKey: cacheKey)
            await loader.removeTask(for: account.id)
            return data
        }

        await loader.setTask(task, for: account.id)
        return await task.value
    }

    static func decodeSkinImage(from data: Data) -> CIImage? {
        if let image = CIImage(data: data) {
            return image
        }

        guard let nsImage = NSImage(data: data) else {
            return nil
        }

        if let tiffRepresentation = nsImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffRepresentation) {
            return CIImage(bitmapImageRep: bitmap)
        }

        return nil
    }

    private static func loadSkinData(for account: Account) async -> Data {
        do {
            guard let textures: Data = account.profile.property(forName: "textures") else {
                if !(account is OfflineAccount) {
                    warn("玩家档案中不存在 textures 属性")
                }
                return defaultSkinData
            }

            let decodedTextures: Data
            if let texturesString = String(data: textures, encoding: .utf8),
               let base64Decoded = Data(base64Encoded: texturesString) {
                decodedTextures = base64Decoded
            } else {
                decodedTextures = textures
            }

            let json: JSON
            do {
                json = try .init(data: decodedTextures)
            } catch {
                err("解析 textures 属性失败：原始大小=\(textures.count) 字节，解码后大小=\(decodedTextures.count) 字节，原始前缀=\(dataPrefixHex(textures))，解码前缀=\(dataPrefixHex(decodedTextures))")
                return defaultSkinData
            }

            guard let url: URL = json["textures"]["SKIN"]["url"].url else {
                err("解析 textures 属性失败：未找到 SKIN.url，解码后前缀=\(dataPrefixHex(decodedTextures))")
                return defaultSkinData
            }

            let normalizedURL = normalizeSkinURL(url)
            let skinData = try await Requests.get(normalizedURL).data
            guard isValidSkinImageData(skinData) else {
                err("获取皮肤数据失败：内容不是有效皮肤图片，URL=\(normalizedURL.absoluteString)，大小=\(skinData.count) 字节，前缀=\(dataPrefixHex(skinData))")
                return defaultSkinData
            }
            return skinData
        } catch {
            err("获取皮肤数据失败：\(error.localizedDescription)")
            return defaultSkinData
        }
    }

    private static func dataPrefixHex(_ data: Data, length: Int = 16) -> String {
        data.prefix(length).map { String(format: "%02X", $0) }.joined()
    }

    private static func normalizeSkinURL(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.scheme = "https"
        return components.url ?? url
    }

    private static func isValidSkinImageData(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }

        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        if data.starts(with: pngSignature) {
            return true
        }

        if let stringPrefix = String(data: data.prefix(64), encoding: .utf8)?.lowercased() {
            if stringPrefix.contains("<html") || stringPrefix.contains("<?xml") || stringPrefix.contains("accessdenied") {
                return false
            }
        }

        return NSImage(data: data) != nil
    }
}

private actor SkinDataLoader {
    private var tasks: [UUID: Task<Data, Never>] = [:]

    func task(for id: UUID) -> Task<Data, Never>? { tasks[id] }
    func setTask(_ task: Task<Data, Never>, for id: UUID) { tasks[id] = task }
    func removeTask(for id: UUID) { tasks[id] = nil }
}
