//
//  PlayerAvatar.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/1/18.
//

import SwiftUI
import Core

struct PlayerAvatar: View {
    @StateObject private var viewModel: AccountViewModel = .init()
    @State private var skinImage: CIImage?
    private static let defaultSkinData: Data = .init(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAMAAACdt4HsAAAAdVBMVEUAAAAKvLwAzMwmGgokGAgrHg0zJBE/KhW3g2uzeV5SPYn///+qclmbY0mQWT8Af38AaGhVVVWUYD52SzOBUzmPXj5JJRBCHQp3QjVqQDA0JRIoKCg3Nzc/Pz9KSko6MYlBNZtGOqUDenoFiIgElZUApKQAr6/wvakZAAAAAXRSTlMAQObYZgAAAolJREFUeNrt1l1rHucZReFrj/whu5hSCCQtlOTE/f+/Jz4q9Cu0YIhLcFVpVg+FsOCVehi8jmZgWOzZz33DM4CXlum3gH95GgeAzQZVeL4gTm6Cbp4vqFkD8HwBazPY8wWbMq9utu3mNZ5fotVezbzOE3kBEFbaZuc8kb00NTMUbWJp678Xf2GV7RRtx1TDQQ6XBNvsmL2+2vHq1TftmMPIyAWujtN2cl274ua2jpVpZneXEjjo7XW1q53V9ds4ODO5xIuhvGHvfLI3aixauig415uuO2+vl9+cncfsFw25zL650fXn687jqnXuP68/X3+eV3zE7y6u9eB73MlfAcfbTf3yR8CfAX+if8S/H5/EAbAxj5LN48tULvEBOh8V1AageMTXe2YHAOwHbZxrzPkSR3+ffr8TR2JDzE/4Fj8CDgEwDsW+q+9GsR07hhg2CsALBgMo2v5wNxXnQXMeGQVW7gUAyKI2m6KDsJ8Au3++F5RZO+kKNQjQcLLWgjwUjBXLltFgWWMUUlviocBgNoxNGgMjSxiYAA7zgLFo2hgIENiDU8gQCzDOmViGFAsEuBcQSDCothhpJaDRA8E5fHqH2nTbYm5fHLo1V0u3B7DAuheoeScRYabjjjuzs17cHVaTrTXmK78m9swP34d9oK/dfeXSIH2PW/MXwPvxN/bJlxw8zlYAcEyeI6gNgA/O8P8neN8xe1IHP2gTzegjvhUDfuRygmwEs2GE4mkCDIAzm2R4yAuPsIdR9k8AvMc+3L9+2UEjo4WP0FpgP19O0MzCsqxIoMsdDBvYcQyGmO0ZJRoYCKjLJWY0BAhYwGUBCgkh8MRdOKt+ruqMwAB2OcEX94U1TPbYJP0PkyyAI1S6cSIAAAAASUVORK5CYII=")!
    private let account: Account
    private let length: CGFloat
    
    init(_ account: Account, length: CGFloat = 58) {
        self.account = account
        self.length = length
    }
    
    var body: some View {
        ZStack {
            if let skinImage {
                SkinLayerView(image: skinImage, startX: 8, startY: 16)
                    .frame(width: length / 10 * 9)
                SkinLayerView(image: skinImage, startX: 40, startY: 16)
                    .frame(width: length)
            }
        }
        .shadow(radius: 2)
        .frame(width: length, height: length)
        .task {
            let skinData: Data = await viewModel.skinData(for: account)
            if let image = decodeSkinImage(from: skinData) {
                await MainActor.run {
                    self.skinImage = image
                }
                return
            }

            if let fallbackImage = decodeSkinImage(from: Self.defaultSkinData) {
                warn("皮肤解码失败，已回退到默认皮肤：数据大小=\(skinData.count) 字节，前缀=\(skinData.prefix(16).map { String(format: "%02X", $0) }.joined())")
                await MainActor.run {
                    self.skinImage = fallbackImage
                }
                return
            }

            err("加载皮肤图像失败：数据大小=\(skinData.count) 字节，前缀=\(skinData.prefix(16).map { String(format: "%02X", $0) }.joined())")
        }
    }

    private func decodeSkinImage(from data: Data) -> CIImage? {
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
}

private struct SkinLayerView: View {
    private let image: NSImage?
    
    init(image: CIImage, startX: CGFloat, startY: CGFloat) {
        let yOffset: CGFloat = image.extent.height == 32 ? 0 : 32
        let cropped: CIImage = image.cropped(to: CGRect(x: startX, y: startY + yOffset, width: 8, height: 8))
        let context: CIContext = .init()
        guard let cgImage = context.createCGImage(cropped, from: cropped.extent) else {
            warn("创建 CGImage 失败")
            self.image = nil
            return
        }
        self.image = NSImage(cgImage: cgImage, size: cropped.extent.size)
    }
    
    var body: some View {
        if let image {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        }
    }
}
