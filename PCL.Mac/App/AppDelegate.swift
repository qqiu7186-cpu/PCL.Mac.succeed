//
//  AppDelegate.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/11/8.
//

import Foundation
import AppKit
import Core
import SwiftScaffolding

class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: AppWindow!
    private lazy var isUnderTesting: Bool = ProcessInfo.processInfo.environment["PCL_MAC_TESTING"] != nil
    private var keyMonitor: Any?
     
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppBootstrapService.shared.runInitialBootstrap(isUnderTesting: isUnderTesting)
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if isUnderTesting { return }
        log("App 启动完成")
        self.window = AppWindow()
        self.window.makeKeyAndOrderFront(nil)
        log("成功创建窗口")
        MinecraftWindowTitleOverrideService.preparePermissionOnLauncherStartup()
        addEscapeMonitor()
        
        if !LauncherConfig.shared.hasEnteredLauncher {
            MessageBoxManager.shared.showText(
                title: "欢迎使用 PCL.Mac！",
                content: "PCL.Mac 是 Plain Craft Launcher 的非官方衍生版，使用 SwiftUI 框架完全重构了 PCL 以支持 macOS。\n本启动器还处于开发阶段，有许多功能尚未完成，Bug 可能也比较多……\n若要获取帮助或查看更多信息，请访问 Cylorine Studio 官方网站！\n\n在开始使用前，请先阅读 Cylorine Studio 隐私政策。",
                level: .info,
                .init(id: 0, label: "打开 Cylorine Studio 官网", type: .normal) {
                    NSWorkspace.shared.open(URL(string: "https://cylorine.studio/projects/PCL.Mac.Refactor")!)
                },
                .init(id: 1, label: "查看隐私政策", type: .normal) {
                    NSWorkspace.shared.open(URL(string: "https://cylorine.studio/privacy")!)
                },
                .init(id: 2, label: "开始使用", type: .highlight)
            ) { _ in
                LauncherConfig.mutate {
                    $0.hasEnteredLauncher = true
                }
            }
        }
        UpdateService.shared.runInteractiveUpdateFlow()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        do {
            try VersionCache.save()
            log("保存版本缓存成功")
        } catch {
            err("保存版本缓存失败：\(error.localizedDescription)")
        }
        do {
            try LauncherConfig.save()
            log("保存启动器配置成功")
        } catch {
            err("保存启动器配置失败：\(error.localizedDescription)")
        }
        EasyTierManager.shared.terminateAll()
    }
    
    private func addEscapeMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 {
                DispatchQueue.main.async {
                    guard AppRouter.shared.isSubPage, MessageBoxManager.shared.currentMessageBox == nil else { return }
                    AppRouter.shared.removeLast()
                }
            } else {
                return event
            }
            return nil
        }
    }
}
