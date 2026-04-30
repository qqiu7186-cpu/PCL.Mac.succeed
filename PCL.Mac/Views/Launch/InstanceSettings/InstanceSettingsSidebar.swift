//
//  InstanceSettingsSidebar.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/2/2.
//

import SwiftUI

struct InstanceSettingsSidebar: Sidebar {
    let width: CGFloat = 128
    private let id: String
    
    init(id: String) {
        self.id = id
    }
    
    var body: some View {
        VStack(spacing: 0) {
            MyText("游戏本体", size: 11, color: .colorGray3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)
            MyNavigationList(
                .init(.instanceOverview(id: id), .gameDownloadIcon, "概览"),
                .init(.instanceConfig(id: id), .iconSettingsPage, "设置"),
                .init(.instanceModify(id: id), .iconSettingsPage, "修改"),
                .init(.instanceExport(id: id), .iconDownloadPage, "导出")
            )

            MyText("游戏资源", size: 11, color: .colorGray3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .padding(.top, 14)
                .padding(.bottom, 4)
            MyNavigationList(routeList: resourceRoutes)
            Spacer()
        }
    }

    private var resourceRoutes: [MyNavigationList.Route] {
        [
            .init(.instanceSaves(id: id), .iconBox, "存档"),
            .init(.instanceScreenshots(id: id), .iconPicture, "截图"),
            .init(.instanceMods(id: id), .iconMod, "模组"),
            .init(.instanceResourcepacks(id: id), .iconPicture, "资源包"),
            .init(.instanceShaderpacks(id: id), .iconSun, "光影包"),
            .init(.instanceSchematics(id: id), .iconBox, "投影原理图"),
            .init(.instanceServers(id: id), .iconSettingsPage, "服务器")
        ]
    }
}
