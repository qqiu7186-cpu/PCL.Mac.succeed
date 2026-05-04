//
//  JavaSettingsPage.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/6.
//

import SwiftUI
import Core

struct JavaSettingsPage: View {
    @StateObject private var viewModel: JavaSettingsViewModel = .init()
    
    var body: some View {
        CardContainer {
            MyCard("", titled: false) {
                HStack {
                    MyButton("刷新 Java 列表") {
                        do {
                            try viewModel.refreshJavaList()
                            hint("刷新成功！", type: .finish)
                        } catch {
                            let wrappedError = AppError.wrap(error, category: .runtime, action: "刷新 Java 列表失败")
                            err(wrappedError.localizedDescription)
                            hint(wrappedError.localizedDescription, type: .critical)
                        }
                    }
                    .frame(width: 120)
                    
                    MyButton("安装 Java") {
                        Task {
                            do {
                                try await viewModel.startInstallJavaFlow()
                            } catch {
                                let wrappedError = AppError.wrap(error, category: .network, action: "拉取 Java 列表失败")
                                err(wrappedError.localizedDescription)
                                hint(wrappedError.localizedDescription, type: .critical)
                            }
                        }
                    }
                    .frame(width: 120)
                    Spacer()
                }
                .frame(height: 40)
            }
            
            MyCard("Java 列表", folded: false) {
                MyList(items: viewModel.javaList)
            }
            .cardIndex(1)
        }
        .onAppear {
            viewModel.reloadJavaList()
        }
    }
}
