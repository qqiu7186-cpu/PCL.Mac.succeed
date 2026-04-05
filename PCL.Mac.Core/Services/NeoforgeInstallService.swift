//
//  NeoforgeInstallService.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/21.
//

import Foundation

public class NeoforgeInstallService: ForgeInstallService {
    override func installerDownloadURLs() -> [URL] {
        if minecraftVersion.id == "1.20.1" {
            let version: String = !self.version.hasPrefix("1.20.1-") ? "1.20.1-\(self.version)" : self.version
            let path = "net/neoforged/forge/\(version)/forge-\(version)-installer.jar"
            return [
                URL(string: "https://maven.neoforged.net/releases/\(path)")!,
                URL(string: "https://bmclapi2.bangbang93.com/maven/\(path)")!,
                URL(string: "https://bmclapi.bangbang93.com/maven/\(path)")!,
                URL(string: "https://download.mcbbs.net/maven/\(path)")!,
                URL(string: "https://bmclapi2-cn.bangbang93.com/maven/\(path)")!
            ]
        }
        let path = "net/neoforged/neoforge/\(version)/neoforge-\(version)-installer.jar"
        return [
            URL(string: "https://maven.neoforged.net/releases/\(path)")!,
            URL(string: "https://bmclapi2.bangbang93.com/maven/\(path)")!,
            URL(string: "https://bmclapi.bangbang93.com/maven/\(path)")!,
            URL(string: "https://download.mcbbs.net/maven/\(path)")!,
            URL(string: "https://bmclapi2-cn.bangbang93.com/maven/\(path)")!
        ]
    }
}
