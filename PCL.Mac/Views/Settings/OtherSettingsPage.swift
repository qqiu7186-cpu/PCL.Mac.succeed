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

    var body: some View {
        CardContainer {
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
}
