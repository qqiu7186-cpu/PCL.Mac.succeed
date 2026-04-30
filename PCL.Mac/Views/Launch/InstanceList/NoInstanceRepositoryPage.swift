//
//  NoInstanceRepositoryPage.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/12/29.
//

import SwiftUI

/// 未添加任何 `MinecraftRepository` 时显示的视图
struct NoInstanceRepositoryPage: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.color5.opacity(0.55), Color.color7.opacity(0.9), Color.color8],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Image("IconSearch")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .foregroundStyle(Color.colorGray3)
                    MyText("搜索游戏实例", size: 14, color: .colorGray3)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.white.opacity(0.82))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.color6, lineWidth: 1)
                        )
                )

                MyCard("实例列表", folded: false, padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        MyText("你还没有添加任何文件夹。", size: 13)
                        MyText("先在左侧选择“添加已有文件夹”，或者导入整合包后再来选择实例。", size: 11.5, color: .colorGray3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
