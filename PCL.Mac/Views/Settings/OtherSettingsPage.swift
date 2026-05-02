//
//  OtherSettingsPage.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/26.
//

import SwiftUI
import Core

struct OtherSettingsPage: View {
    @StateObject private var viewModel: OtherSettingsViewModel = .init()
    @State private var curseForgeAPIKey: String = LauncherConfig.shared.curseForgeAPIKey ?? ""

    var body: some View {
        CardContainer {
            MyCard("资源平台", foldable: false) {
                VStack(alignment: .leading, spacing: 12) {
                    configLine(label: "CurseForge API Key") {
                        MyTextField(text: $curseForgeAPIKey, placeholder: "留空则仅使用 Modrinth 与包内图标")
                            .onChange(of: curseForgeAPIKey) { newValue in
                                saveCurseForgeAPIKey(newValue)
                            }
                    }

                    HStack(spacing: 12) {
                        MyButton("清空 Key", type: .red) {
                            curseForgeAPIKey = ""
                            saveCurseForgeAPIKey("")
                        }
                        .frame(width: 120)
                        Spacer()
                    }
                    .frame(height: 35)

                    MyText("用于实例管理页的 CurseForge 本地 Mod 指纹识别；未配置时会自动回退为仅使用 Modrinth 与包内图标。", size: 11.5, color: .colorGray3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            MyCard("调试", foldable: false) {
                HStack {
                    MyButton("导出日志") {
                        do {
                            let url: URL = try viewModel.exportLogs()
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } catch {
                            let wrappedError = AppError.wrap(error, category: .fileSystem, action: "导出日志失败")
                            err(wrappedError.localizedDescription)
                            hint(wrappedError.localizedDescription, type: .critical)
                        }
                    }
                    .frame(width: 150)
                    Spacer()
                }
                .frame(height: 40)
            }
            MyCard("启动器更新", foldable: false) {
                HStack {
                    MyButton("检查更新") {
                        viewModel.checkUpdates()
                    }
                    .frame(width: 150)
                    Spacer()
                }
                .frame(height: 40)
            }
        }
    }

    private func saveCurseForgeAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        LauncherConfig.mutate {
            $0.curseForgeAPIKey = trimmed.isEmpty ? nil : trimmed
        }
        do {
            try LauncherConfig.save()
        } catch {
            err("保存 CurseForge API Key 失败：\(error.localizedDescription)")
            hint("保存 CurseForge API Key 失败：\(error.localizedDescription)", type: .critical)
        }
    }

    @ViewBuilder
    private func configLine(label: String, @ViewBuilder body: () -> some View) -> some View {
        HStack(spacing: 20) {
            MyText(label)
                .frame(width: 140, alignment: .leading)
            HStack {
                Spacer(minLength: 0)
                body()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
    }
}
