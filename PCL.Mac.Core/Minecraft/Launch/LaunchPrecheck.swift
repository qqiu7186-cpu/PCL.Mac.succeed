//
//  LaunchPrecheck.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/2/2.
//

import Foundation

public enum LaunchPrecheck {
    public static func check(
        for instance: MinecraftInstance,
        with options: LaunchOptions,
        hasMicrosoftAccount: Bool
    ) -> [Entry] {
        var entries: [Entry] = []
        entries += checkJava(instance: instance, currentJava: options.javaRuntime)
        entries += checkAccount(options.profile, hasMicrosoftAccount: hasMicrosoftAccount)
        return entries
    }
    
    private static func checkJava(instance: MinecraftInstance, currentJava: JavaRuntime) -> [Entry] {
        var entries: [Entry] = []
        let minVersion: Int = instance.manifest.requiredJavaMajorVersion(for: instance.version)
        let javaRange = instance.manifest.supportedJavaMajorRange(
            for: instance.version,
            modLoader: instance.modLoader,
            modLoaderVersion: instance.modLoaderVersion
        )
        let actualVersion: Int = currentJava.majorVersion
        if actualVersion < minVersion {
            log("当前 Java 版本（\(actualVersion)）低于最低 Java 版本（\(minVersion)）")
            entries.append(.javaVersionTooLow(min: minVersion))
        } else if !javaRange.contains(actualVersion) {
            log("当前 Java 版本（\(actualVersion)）不在支持范围（\(javaRange.lowerBound)-\(javaRange.upperBound)）")
            entries.append(.javaVersionOutOfRange(min: javaRange.lowerBound, max: javaRange.upperBound))
        }
        if Architecture.systemArchitecture() == .arm64 && currentJava.architecture == .arm64 && instance.version <= .init("1.7.2") {
            log("不支持当前 Java 架构")
            entries.append(.armNotSupported)
        }
        return entries
    }
    
    private static func checkAccount(_ profile: PlayerProfile, hasMicrosoftAccount: Bool) -> [Entry] {
        var entries: [Entry] = []
        if !hasMicrosoftAccount {
            entries.append(.noMicrosoftAccount)
        }
        return entries
    }
    
    public enum Entry {
        case javaVersionTooLow(min: Int)
        case javaVersionOutOfRange(min: Int, max: Int)
        case armNotSupported
        case noMicrosoftAccount
    }
}
