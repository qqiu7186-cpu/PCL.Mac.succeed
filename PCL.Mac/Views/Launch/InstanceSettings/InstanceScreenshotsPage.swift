import SwiftUI
import Core
import AppKit

private struct ScreenshotItem: Identifiable {
    let id: URL
    let url: URL

    var name: String { url.lastPathComponent }
}

struct InstanceScreenshotsPage: View {
    let id: String
    @State private var instance: MinecraftInstance?
    @State private var screenshots: [ScreenshotItem] = []

    private let columns: [GridItem] = Array(repeating: .init(.flexible(), spacing: 12), count: 4)

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
                    .overlay(alignment: .bottomTrailing) {
                        InstanceSettingsFloatingActionButton(systemImage: "power") {
                            openScreenshotsFolder(instance)
                        }
                    }
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

                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(screenshots) { item in
                                    ScreenshotCard(item: item, onDelete: {
                                        delete(item)
                                    })
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 28)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        InstanceSettingsFloatingActionButton(systemImage: "power") {
                            openScreenshotsFolder(instance)
                        }
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
    }

    private func reloadScreenshots() {
        guard let instance else { return }
        let screenshotsURL = instance.runningDirectory.appending(path: "screenshots")
        let files = InstanceFileBrowserService.resourceFileEntries(at: screenshotsURL)
        screenshots = files
            .filter { ["png", "jpg", "jpeg", "bmp", "tiff", "webp"].contains($0.url.pathExtension.lowercased()) }
            .map { ScreenshotItem(id: $0.url, url: $0.url) }
    }

    private func openScreenshotsFolder(_ instance: MinecraftInstance) {
        let url = instance.runningDirectory.appending(path: "screenshots")
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
                    fallbackIcon: "IconPicture"
                )
                .frame(maxWidth: .infinity)

                HStack(spacing: 10) {
                    smallAction("folder", "打开") {
                        NSWorkspace.shared.open(item.url)
                    }
                    smallAction("trash", "删除") {
                        onDelete()
                    }
                    smallAction("doc.on.doc", "复制") {
                        let board = NSPasteboard.general
                        board.clearContents()
                        board.writeObjects([item.url as NSURL])
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)
        }
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
}
