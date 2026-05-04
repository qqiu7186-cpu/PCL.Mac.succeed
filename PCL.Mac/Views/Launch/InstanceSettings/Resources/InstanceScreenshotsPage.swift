import SwiftUI
import Core
import AppKit

private struct ScreenshotItem: Identifiable {
    let id: URL
    let url: URL
    let modifiedAt: Date?

    var name: String { url.lastPathComponent }
}

struct InstanceScreenshotsPage: View {
    let id: String
    @State private var instance: MinecraftInstance?
    @State private var screenshots: [ScreenshotItem] = []

    private let cardsPerRow: Int = 4
    private let supportedImageExtensions: Set<String> = ["png", "jpg", "jpeg", "bmp", "tiff", "webp", "gif", "heic", "heif"]

    private var screenshotRows: [[ScreenshotItem]] {
        stride(from: 0, to: screenshots.count, by: cardsPerRow).map { start in
            Array(screenshots[start..<min(start + cardsPerRow, screenshots.count)])
        }
    }

    var body: some View {
        InstanceSettingsBackground {
            if let instance {
                if screenshots.isEmpty {
                    InstanceSettingsEmptyStateCard(
                        title: "暂时没有截图文件",
                        description: "在游戏内按下截图键（默认为 F2）后，可在此处查看保存的截图",
                        primaryTitle: "打开截图文件夹",
                        secondaryTitle: nil,
                        primaryAction: { openScreenshotsFolder(instance) },
                        secondaryAction: nil
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            InstanceSettingsSectionCard("快捷操作") {
                                HStack(spacing: 16) {
                                    MyButton("打开截图文件夹") { openScreenshotsFolder(instance) }
                                        .frame(width: 112)
                                    Spacer(minLength: 0)
                                }
                                .frame(height: 35)
                            }

                            InstanceSettingsSectionCard("截图列表（\(screenshots.count)）") {
                                VStack(spacing: 12) {
                                    ForEach(Array(screenshotRows.enumerated()), id: \.offset) { _, row in
                                        HStack(alignment: .top, spacing: 12) {
                                            ForEach(row) { item in
                                                ScreenshotCard(item: item, onDelete: {
                                                    delete(item)
                                                })
                                                .frame(maxWidth: .infinity)
                                            }
                                            if row.count < cardsPerRow {
                                                ForEach(0..<(cardsPerRow - row.count), id: \.self) { _ in
                                                    Color.clear
                                                        .frame(maxWidth: .infinity)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 28)
                    }
                }
            } else {
                MyLoading(viewModel: .init(text: "未找到可配置的实例"), showCard: false)
            }
        }
        .task(id: id) {
            instance = InstancePageLoader.loadInstance(id)
            reloadScreenshots()
        }
        .onAppear {
            reloadScreenshots()
        }
    }

    private func reloadScreenshots() {
        guard let instance else { return }
        let screenshotsURL = effectiveGameDirectory(for: instance).appending(path: "screenshots")
        InstanceFileBrowserService.ensureDirectoryExists(screenshotsURL)
        let files = InstanceFileBrowserService.resourceFileEntries(at: screenshotsURL)
        screenshots = files
            .filter { supportedImageExtensions.contains($0.url.pathExtension.lowercased()) }
            .sorted { lhs, rhs in
                switch (lhs.modifiedAt, rhs.modifiedAt) {
                case let (lhsDate?, rhsDate?):
                    if lhsDate != rhsDate { return lhsDate > rhsDate }
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }
                return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
            }
            .map { ScreenshotItem(id: $0.url, url: $0.url, modifiedAt: $0.modifiedAt) }
    }

    private func openScreenshotsFolder(_ instance: MinecraftInstance) {
        let url = effectiveGameDirectory(for: instance).appending(path: "screenshots")
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.open(url)
        } catch {
            hint("打开截图文件夹失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func delete(_ item: ScreenshotItem) {
        do {
            try FileManager.default.removeItem(at: item.url)
            hint("已删除截图", type: .finish)
            reloadScreenshots()
        } catch {
            hint("删除失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func effectiveGameDirectory(for instance: MinecraftInstance) -> URL {
        if instance.config.versionIsolationEnabled {
            return instance.runningDirectory
        }
        return InstanceManager.shared.currentRepository?.url ?? instance.runningDirectory
    }
}

private struct ScreenshotCard: View {
    let item: ScreenshotItem
    let onDelete: () -> Void

    var body: some View {
        MyCard("", foldable: false, titled: false, padding: 0) {
            VStack(spacing: 0) {
                InstanceSettingsLocalImage(
                    url: item.url,
                    size: .init(width: 190, height: 108),
                    cornerRadius: 4,
                    fallbackIcon: "iconPicture"
                )
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) {
                    Text(item.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? item.name)
                        .font(.custom("PCLEnglish", size: 10))
                        .foregroundStyle(Color.color1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                }

                HStack(spacing: 10) {
                    smallAction("folder", "打开") {
                        NSWorkspace.shared.open(item.url)
                    }
                    smallAction("trash", "删除") {
                        onDelete()
                    }
                    smallAction("doc.on.doc", "复制") {
                        copyImageToPasteboard()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.78))
            }
            .frame(maxWidth: .infinity)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func smallAction(_ systemImage: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                Text(title)
                    .font(.custom("PCLEnglish", size: 12))
            }
            .foregroundStyle(Color.color1)
        }
        .buttonStyle(.plain)
    }

    private func copyImageToPasteboard() {
        guard let image = NSImage(contentsOf: item.url) else {
            hint("复制截图失败：无法读取图片", type: .critical)
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        hint("已复制截图到剪贴板", type: .finish)
    }
}
