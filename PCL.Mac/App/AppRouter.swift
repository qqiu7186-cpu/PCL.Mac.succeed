//
//  AppRouter.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/11/9.
//

import SwiftUI

@MainActor
class AppRouter: ObservableObject {
    static let shared: AppRouter = .init()
      
    @Published private(set) var path: [AppRoute] = [.launch]
    @Published var activeModifyContext: InstanceModifyContext?
     
    func getLast() -> AppRoute {
        return path[path.count - 1]
    }
    
    func getRoot() -> AppRoute {
        return path[0]
    }
    
    func setRoot(_ newRoot: AppRoute) {
        activeModifyContext = nil
        path = [newRoot]
        // 各根页面的默认子页面
        if newRoot == .download { append(.minecraftDownload) }
        if newRoot == .multiplayer { append(.multiplayerSub) }
        if newRoot == .settings { append(.javaSettings) }
        if newRoot == .more { append(.about) }
    }
    
    func append(_ route: AppRoute) {
        path.append(route)
        if case .instanceSettings(let id) = route { append(.instanceOverview(id: id)) }
    }
    
    func removeLast() {
        if path.count > 1 {
            path.removeLast()
            if case .instanceSettings = getLast() { removeLast() }
        }
    }

    func replaceInstanceID(from oldID: String, to newID: String) {
        path = path.map { route in
            switch route {
            case .instanceSettings(let id) where id == oldID: .instanceSettings(id: newID)
            case .instanceOverview(let id) where id == oldID: .instanceOverview(id: newID)
            case .instanceConfig(let id) where id == oldID: .instanceConfig(id: newID)
            case .instanceModify(let id) where id == oldID: .instanceModify(id: newID)
            case .instanceExport(let id) where id == oldID: .instanceExport(id: newID)
            case .instanceSaves(let id) where id == oldID: .instanceSaves(id: newID)
            case .instanceScreenshots(let id) where id == oldID: .instanceScreenshots(id: newID)
            case .instanceMods(let id) where id == oldID: .instanceMods(id: newID)
            case .instanceResourcepacks(let id) where id == oldID: .instanceResourcepacks(id: newID)
            case .instanceShaderpacks(let id) where id == oldID: .instanceShaderpacks(id: newID)
            case .instanceSchematics(let id) where id == oldID: .instanceSchematics(id: newID)
            case .instanceServers(let id) where id == oldID: .instanceServers(id: newID)
            default: route
            }
        }
    }
    
    private init() {}
}
