//
//  JavaManager.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/2/2.
//

import Foundation

public final class JavaManager: ObservableObject {
    public static let shared: JavaManager = .init()
    private static let brokenRuntimePathsKey: String = "pclmac.broken-java-runtime-paths"
    
    @Published public private(set) var javaRuntimes: [JavaRuntime]
    private let blacklistQueue: DispatchQueue = .init(label: "PCL.Mac.JavaManager.Blacklist")
    private var brokenRuntimePaths: Set<String>

    public func isBrokenRuntime(_ runtime: JavaRuntime) -> Bool {
        blacklistQueue.sync {
            brokenRuntimePaths.contains(Self.normalizedRuntimePath(runtime.executableURL))
        }
    }

    public func markRuntimeAsBroken(_ runtime: JavaRuntime) {
        let normalizedPath = Self.normalizedRuntimePath(runtime.executableURL)
        var changed = false
        blacklistQueue.sync {
            changed = brokenRuntimePaths.insert(normalizedPath).inserted
            if changed {
                UserDefaults.standard.set(Array(brokenRuntimePaths), forKey: Self.brokenRuntimePathsKey)
            }
        }
        guard changed else { return }
        DispatchQueue.main.async {
            self.javaRuntimes.removeAll { Self.normalizedRuntimePath($0.executableURL) == normalizedPath }
        }
    }

    public func clearBrokenRuntime(_ runtime: JavaRuntime) {
        let normalizedPath = Self.normalizedRuntimePath(runtime.executableURL)
        clearBrokenRuntime(atExecutableURL: URL(fileURLWithPath: normalizedPath))
    }

    public func clearBrokenRuntime(atExecutableURL executableURL: URL) {
        let normalizedPath = Self.normalizedRuntimePath(executableURL)
        blacklistQueue.sync {
            let changed = brokenRuntimePaths.remove(normalizedPath) != nil
            if changed {
                UserDefaults.standard.set(Array(brokenRuntimePaths), forKey: Self.brokenRuntimePathsKey)
            }
        }
    }
    
    @MainActor
    public func research() throws {
        self.javaRuntimes = try JavaSearcher.search().filter { !isBrokenRuntime($0) }
    }

    public func allJavaRuntimes() throws -> [JavaRuntime] {
        try JavaSearcher.search()
    }
    
    private init() {
        let initialBrokenPaths: Set<String> = Set((UserDefaults.standard.stringArray(forKey: Self.brokenRuntimePathsKey) ?? []).map { Self.normalizedRuntimePath(URL(fileURLWithPath: $0)) })
        self.brokenRuntimePaths = initialBrokenPaths
        self.javaRuntimes = []
        do {
            self.javaRuntimes = try JavaSearcher.search().filter { !initialBrokenPaths.contains(Self.normalizedRuntimePath($0.executableURL)) }
            log("Java 搜索完成，共 \(javaRuntimes.count) 个：")
            for javaRuntime in javaRuntimes {
                let type: String = .init(describing: javaRuntime.type).padding(toLength: 4, withPad: " ", startingAt: 0)
                let version: String = .init(describing: javaRuntime.version).padding(toLength: 10, withPad: " ", startingAt: 0)
                let arch: String = .init(describing: javaRuntime.architecture).padding(toLength: 8, withPad: " ", startingAt: 0)
                let impl: String = (javaRuntime.implementor ?? "").padding(toLength: 24, withPad: " ", startingAt: 0)
                log("\(type) \(version)\t\(arch)\t\(impl)\t\(javaRuntime.executableURL.path)")
            }
        } catch {
            err("搜索 Java 失败：\(error.localizedDescription)")
            self.javaRuntimes = []
        }
    }

    private static func normalizedRuntimePath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
