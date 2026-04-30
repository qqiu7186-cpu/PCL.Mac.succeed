//
//  NetworkImage.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/19.
//

import SwiftUI
import Core

struct NetworkImage: View {
    @State private var nsImage: NSImage?
    private let url: URL
    private let targetSize: CGSize?
    
    init(url: URL, targetSize: CGSize? = nil) {
        self.url = url
        self.targetSize = targetSize
    }
    
    var body: some View {
        Group {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
            .task(id: taskIdentifier) {
                do {
                    await MainActor.run {
                        withAnimation(nil) {
                            self.nsImage = nil
                        }
                    }
                    if let cached = await RemoteImageService.shared.cachedImage(for: url, targetSize: targetSize) {
                        await MainActor.run {
                            withAnimation(nil) {
                                self.nsImage = cached
                            }
                        }
                        return
                    }
                    let nsImage = try await RemoteImageService.shared.image(for: url, targetSize: targetSize)
                    await MainActor.run {
                        withAnimation(nil) {
                            self.nsImage = nsImage
                        }
                    }
                } catch is CancellationError {
                } catch {
                    err("加载图片 \(url.absoluteString) 失败：\(error.localizedDescription)")
                }
            }
    }

    private var taskIdentifier: String {
        let width = Int((targetSize?.width ?? 0).rounded(.up))
        let height = Int((targetSize?.height ?? 0).rounded(.up))
        return "\(url.absoluteString)#\(width)x\(height)"
    }
}
