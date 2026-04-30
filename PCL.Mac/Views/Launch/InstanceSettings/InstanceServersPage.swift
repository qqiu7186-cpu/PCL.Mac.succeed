import SwiftUI
import Core
import UniformTypeIdentifiers
import AppKit

struct InstanceServersPage: View {
    let id: String
    private let serverButtonWidth: CGFloat = 130
    @State private var instance: MinecraftInstance?
    @State private var errorMessage: String?
    @State private var hasServersDat: Bool = false

    var body: some View {
        CardContainer {
            if let instance {
                let serversDat = instance.runningDirectory.appending(path: "servers.dat")
                MyCard(hasServersDat ? "快捷操作" : "服务器", foldable: false) {
                    if hasServersDat {
                        VStack(alignment: .leading, spacing: 12) {
                            MyText("暂时没有找到服务器时，可先在游戏内添加，或在此处导入 servers.dat。", size: 12, color: .colorGray3)
                                .lineLimit(3)
                            HStack(spacing: 15) {
                                MyButton("刷新服务器信息") {
                                    refreshServersDatState(serversDat)
                                }
                                .frame(width: serverButtonWidth)
                                MyButton("添加新服务器") {
                                    NSWorkspace.shared.open(instance.runningDirectory)
                                    errorMessage = "已打开实例目录，请在游戏内添加服务器，或使用“导入 servers.dat”。"
                                }
                                .frame(width: serverButtonWidth)
                                MyButton("导入 servers.dat") {
                                    importServersDat(to: serversDat)
                                }
                                .frame(width: serverButtonWidth)
                                Spacer(minLength: 0)
                            }
                            .frame(height: 35)
                            HStack(spacing: 15) {
                                MyButton("导出 servers.dat") {
                                    exportServersDat(from: serversDat)
                                }
                                .frame(width: serverButtonWidth)
                                MyButton("打开 servers.dat") {
                                    if FileManager.default.fileExists(atPath: serversDat.path) {
                                        NSWorkspace.shared.open(serversDat)
                                    } else {
                                        errorMessage = "未找到 servers.dat，请先在游戏内添加一个服务器。"
                                    }
                                }
                                .frame(width: serverButtonWidth)
                                MyButton("重置", type: .red) {
                                    resetServersDat(at: serversDat)
                                }
                                .frame(width: serverButtonWidth)
                                Spacer(minLength: 0)
                            }
                            .frame(height: 35)
                            if let errorMessage {
                                MyText(errorMessage, color: errorMessage.contains("已检测") ? .colorGray3 : .red)
                            }
                        }
                    } else {
                        VStack(spacing: 10) {
                            MyText("暂时没有服务器", size: 18, color: .colorGray3)
                            MyText("你可以先在游戏内添加，或在此处导入 servers.dat。", size: 12, color: .colorGray3)
                            HStack(spacing: 15) {
                                Spacer()
                                MyButton("导入 servers.dat") {
                                    importServersDat(to: serversDat)
                                }
                                .frame(width: serverButtonWidth)
                                MyButton("刷新") {
                                    refreshServersDatState(serversDat)
                                }
                                .frame(width: serverButtonWidth)
                                Spacer()
                            }
                            .frame(height: 35)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                }
            } else {
                MyLoading(viewModel: .init(text: "未找到可配置的实例"))
            }
        }
        .task(id: id) {
            instance = InstancePageLoader.loadInstance(id)
            if let instance {
                refreshServersDatState(instance.runningDirectory.appending(path: "servers.dat"))
            }
        }
    }

    private func refreshServersDatState(_ path: URL) {
        hasServersDat = FileManager.default.fileExists(atPath: path.path)
        if hasServersDat {
            errorMessage = "已检测到 servers.dat，可直接导出或打开。"
        } else {
            errorMessage = "暂时没有服务器，请在游戏内添加后再刷新。"
        }
    }

    private func exportServersDat(from path: URL) {
        guard FileManager.default.fileExists(atPath: path.path) else {
            errorMessage = "未找到 servers.dat。"
            return
        }
        let panel = NSSavePanel()
        panel.title = "导出 servers.dat"
        panel.nameFieldStringValue = "servers.dat"
        panel.allowedContentTypes = [.data]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: path, to: destination)
            hint("导出成功", type: .finish)
            errorMessage = nil
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func importServersDat(to path: URL) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.data]
        panel.title = "导入 servers.dat"
        guard panel.runModal() == .OK, let source = panel.url else { return }
        guard source.lastPathComponent.lowercased() == "servers.dat" else {
            errorMessage = "请选择名为 servers.dat 的文件。"
            hint("导入失败：请选择 servers.dat", type: .critical)
            return
        }
        do {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: path.path) {
                try FileManager.default.removeItem(at: path)
            }
            try FileManager.default.copyItem(at: source, to: path)
            hint("导入成功", type: .finish)
            hasServersDat = true
            errorMessage = nil
        } catch {
            errorMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    private func resetServersDat(at path: URL) {
        do {
            if FileManager.default.fileExists(atPath: path.path) {
                try FileManager.default.removeItem(at: path)
            }
            hint("已重置 servers.dat", type: .finish)
            hasServersDat = false
            errorMessage = nil
        } catch {
            errorMessage = "重置失败：\(error.localizedDescription)"
        }
    }
}
