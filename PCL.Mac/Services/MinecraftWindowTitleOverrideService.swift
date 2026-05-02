import Foundation
import ApplicationServices
import Core

enum MinecraftWindowTitleOverrideService {
    private static let fastMonitorIntervalNanoseconds: UInt64 = 250_000_000
    private static let slowMonitorIntervalNanoseconds: UInt64 = 1_000_000_000
    private static let promptLock = NSLock()
    private static var hasWarnedForAccessibilityPermission = false

    static func preparePermissionIfNeeded(for title: String?) -> Bool {
        guard requiresPermission(for: title) else { return true }
        let granted = ensureAccessibilityPermission(promptIfNeeded: false)
        if !granted {
            warnAccessibilityPermissionIfNeeded(message: "若要修改实际游戏窗口标题，请在系统设置中允许 PCL.Mac 的辅助功能权限，然后重新启动游戏。")
        }
        return granted
    }

    static func preparePermissionOnLauncherStartup() {
        let granted = ensureAccessibilityPermission(promptIfNeeded: false)
        log("启动器辅助功能权限检查结果：\(granted ? "已授权" : "未授权")")
        if !granted {
            warnAccessibilityPermissionIfNeeded(message: "PCL.Mac 需要辅助功能权限来修改 Minecraft 实际窗口标题。请在系统设置中允许后重新启动启动器。")
        }
    }

    static func requiresPermission(for title: String?) -> Bool {
        guard let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !normalizedTitle.isEmpty
    }

    static func enforceTitle(for process: Process, title: String) {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return }

        Task.detached(priority: .utility) {
            guard ensureAccessibilityPermission(promptIfNeeded: false) else {
                warn("窗口标题覆盖未执行：辅助功能权限未授予")
                warnAccessibilityPermissionIfNeeded(message: "若要修改实际游戏窗口标题，请在系统设置中允许 PCL.Mac 的辅助功能权限。")
                return
            }

            log("开始监视 Minecraft 窗口标题，目标标题：\(normalizedTitle)")
            var attempt = 0
            while process.isRunning {
                attempt += 1
                _ = updateWindowTitles(processID: process.processIdentifier, title: normalizedTitle, attempt: attempt)
                let interval = attempt <= 20 ? fastMonitorIntervalNanoseconds : slowMonitorIntervalNanoseconds
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private static func updateWindowTitles(processID: Int32, title: String, attempt: Int) -> Bool {
        let application = AXUIElementCreateApplication(processID)
        let windows = applicationWindows(application)
        if windows.isEmpty, attempt == 1 {
            warn("窗口标题覆盖：未发现任何可访问窗口")
        }
        var updated = false

        for window in windows {
            let beforeTitle = currentTitle(of: window)
            if beforeTitle == title {
                updated = true
                continue
            }

            let result = AXUIElementSetAttributeValue(window, kAXTitleAttribute as CFString, title as CFTypeRef)
            if result == .success {
                let afterTitle = currentTitle(of: window)
                if afterTitle == title {
                    updated = true
                    log("窗口标题覆盖成功：\(title)")
                } else {
                    warn("窗口标题覆盖：写入返回 success，但回读标题未变化（之前=\(beforeTitle ?? "<nil>")，之后=\(afterTitle ?? "<nil>")）")
                }
            } else {
                warn("窗口标题覆盖失败：AXError=\(axErrorDescription(result))")
            }
        }

        return updated
    }

    private static func applicationWindows(_ application: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
           let windows = value as? [AXUIElement], !windows.isEmpty {
            return windows
        }

        var focusedWindow: CFTypeRef?
        if AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
           let focusedWindow {
            let window = focusedWindow as! AXUIElement
            return [window]
        }

        return []
    }

    private static func currentTitle(of window: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func ensureAccessibilityPermission(promptIfNeeded: Bool) -> Bool {
        if AXIsProcessTrusted() {
            return true
        }
        guard promptIfNeeded else {
            return false
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func warnAccessibilityPermissionIfNeeded(message: String) {
        promptLock.lock()
        let shouldWarn = !hasWarnedForAccessibilityPermission
        hasWarnedForAccessibilityPermission = true
        promptLock.unlock()
        guard shouldWarn else { return }

        DispatchQueue.main.async {
            hint(message, type: .info)
        }
    }

    private static func axErrorDescription(_ error: AXError) -> String {
        switch error {
        case .success: "success"
        case .failure: "failure"
        case .illegalArgument: "illegalArgument"
        case .invalidUIElement: "invalidUIElement"
        case .invalidUIElementObserver: "invalidUIElementObserver"
        case .cannotComplete: "cannotComplete"
        case .attributeUnsupported: "attributeUnsupported"
        case .actionUnsupported: "actionUnsupported"
        case .notificationUnsupported: "notificationUnsupported"
        case .notImplemented: "notImplemented"
        case .notificationAlreadyRegistered: "notificationAlreadyRegistered"
        case .notificationNotRegistered: "notificationNotRegistered"
        case .apiDisabled: "apiDisabled"
        case .noValue: "noValue"
        case .parameterizedAttributeUnsupported: "parameterizedAttributeUnsupported"
        case .notEnoughPrecision: "notEnoughPrecision"
        @unknown default: "unknown(\(error.rawValue))"
        }
    }
}
