//
//  InstanceSettingsSidebar.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/2/2.
//

import SwiftUI

struct InstanceSettingsSidebar: Sidebar {
    let width: CGFloat = 140
    private let id: String
    
    init(id: String) {
        self.id = id
    }
    
    var body: some View {
        VStack {
            MyText("游戏本体", size: 12, color: .colorGray2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 13)
                .padding(.top, 10)
            MyNavigationList(
                .init(.instanceOverview(id: id), "GameDownloadIcon", "概览"),
                .init(.instanceConfig(id: id), "SettingsPageIcon", "设置"),
                .init(.instanceModify(id: id), "SettingsPageIcon", "修改"),
                .init(.instanceExport(id: id), "DownloadPageIcon", "导出")
            )

            MyText("游戏资源", size: 12, color: .colorGray2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 13)
                .padding(.top, 18)
            MyNavigationList(routeList: resourceRoutes)
            Spacer()
        }
    }

    private var resourceRoutes: [MyNavigationList.Route] {
        [
            .init(.instanceSaves(id: id), "IconBox", "存档"),
            .init(.instanceScreenshots(id: id), "IconPicture", "截图"),
            .init(.instanceMods(id: id), "IconMod", "模组"),
            .init(.instanceResourcepacks(id: id), "IconPicture", "资源包"),
            .init(.instanceShaderpacks(id: id), "IconSun", "光影包"),
            .init(.instanceSchematics(id: id), "IconBox", "投影原理图"),
            .init(.instanceServers(id: id), "SettingsPageIcon", "服务器")
        ]
    }
}
