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
                    .init(.minecraftDownload, .downloadSidebarMinecraftIcon, "Minecraft")
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
                    .init(.modDownload, .iconMod, "Mod"),
                    .init(.modpackDownload, .iconBox, "整合包"),
                    .init(.datapackDownload, .downloadSidebarDatapackIcon, "数据包"),
                    .init(.resourcepackDownload, .iconPicture, "资源包"),
                    .init(.shaderpackDownload, .iconSun, "光影包"),
                    .init(.worldDownload, .downloadSidebarWorldIcon, "世界"),
                    .init(.favoritesDownload, .downloadSidebarFavoritesIcon, "收藏夹")
                )

                MyText("安装包", size: 12, color: .colorGray2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 13)
                    .padding(.top, 20)
                MyNavigationList(
                    .init(.installerMinecraftDownload, .downloadSidebarMinecraftIcon, "Minecraft"),
                    .init(.installerOptiFineDownload, .downloadSidebarOptiFineIcon, "OptiFine"),
                    .init(.installerForgeDownload, .downloadSidebarForgeIcon, "Forge"),
                    .init(.installerNeoForgeDownload, .downloadSidebarForgeIcon, "NeoForge"),
                    .init(.installerCleanroomDownload, .downloadSidebarCleanroomIcon, "Cleanroom"),
                    .init(.installerFabricDownload, .downloadSidebarFabricIcon, "Fabric"),
                    .init(.installerLegacyFabricDownload, .downloadSidebarFabricIcon, "Legacy Fabric"),
                    .init(.installerQuiltDownload, .downloadSidebarQuiltIcon, "Quilt"),
                    .init(.installerLabyModDownload, .downloadSidebarLabyModIcon, "LabyMod"),
                    .init(.installerLiteLoaderDownload, .downloadSidebarLiteLoaderIcon, "LiteLoader")
                )
                Spacer(minLength: 12)
            }
        }
    }
}
