//
//  DownloadSidebar.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/11/10.
//

import SwiftUI
import Core

struct DownloadSidebar: Sidebar {
    @EnvironmentObject private var minecraftDownloadPageViewModel: MinecraftDownloadPageViewModel
    
    let width: CGFloat = 150
    
    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                MyText("游戏下载", size: 12, color: .colorGray2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 13)
                    .padding(.top, 10)
                MyNavigationList(
                    .init(.minecraftDownload, "IconBlock", "Minecraft")
                ) { route in
                    switch route {
                    case .minecraftDownload:
                        minecraftDownloadPageViewModel.reload()
                    default: break
                    }
                }
                
                MyText("社区资源", size: 12, color: .colorGray2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 13)
                    .padding(.top, 20)
                MyNavigationList(
                    .init(.modDownload, "IconMod", "Mod"),
                    .init(.modpackDownload, "IconBox", "整合包"),
                    .init(.datapackDownload, "IconMod", "数据包"),
                    .init(.resourcepackDownload, "IconPicture", "资源包"),
                    .init(.shaderpackDownload, "IconSun", "光影包"),
                    .init(.worldDownload, "IconMod", "世界"),
                    .init(.favoritesDownload, "SettingsPageIcon", "收藏夹")
                )

                MyText("安装包", size: 12, color: .colorGray2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 13)
                    .padding(.top, 20)
                MyNavigationList(
                    .init(.installerMinecraftDownload, "IconBlock", "Minecraft"),
                    .init(.installerOptiFineDownload, "IconSun", "OptiFine"),
                    .init(.installerForgeDownload, "IconMod", "Forge"),
                    .init(.installerNeoForgeDownload, "IconMod", "NeoForge"),
                    .init(.installerCleanroomDownload, "IconBox", "Cleanroom"),
                    .init(.installerFabricDownload, "IconMod", "Fabric"),
                    .init(.installerLegacyFabricDownload, "IconMod", "Legacy Fabric"),
                    .init(.installerQuiltDownload, "IconPicture", "Quilt"),
                    .init(.installerLabyModDownload, "IconBox", "LabyMod"),
                    .init(.installerLiteLoaderDownload, "IconMod", "LiteLoader")
                )
                Spacer(minLength: 12)
            }
        }
    }
}
