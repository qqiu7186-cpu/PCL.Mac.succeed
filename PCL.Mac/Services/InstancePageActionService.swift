import Foundation
import AppKit
import UniformTypeIdentifiers
import Core

enum InstancePageActionService {
    static func openManagedFolder(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    static func exportLaunchScript(
        instance: MinecraftInstance,
        repository: MinecraftRepository,
        account: Account,
        runtime: JavaRuntime
    ) throws {
        let panel = NSSavePanel()
        panel.title = "导出启动脚本"
        panel.nameFieldStringValue = "启动-\(instance.name).command"
        panel.allowedContentTypes = [.shellScript]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let script = buildLaunchScript(instance: instance, account: account, repository: repository, runtime: runtime)
        guard let scriptData = script.data(using: .utf8) else {
            throw SimpleError("无法编码脚本内容")
        }
        try scriptData.write(to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        NSWorkspace.shared.open(destination.deletingLastPathComponent())
    }

    private static func buildLaunchScript(
        instance: MinecraftInstance,
        account: Account,
        repository: MinecraftRepository,
        runtime: JavaRuntime
    ) -> String {
        let manifest = instance.manifest
        let accessToken = account.accessToken()
        var launchOptions: LaunchOptions = .init()
        launchOptions.profile = account.profile
        launchOptions.accessToken = accessToken
        launchOptions.runningDirectory = instance.runningDirectory
        launchOptions.repository = repository
        launchOptions.manifest = manifest
        launchOptions.javaRuntime = runtime
        launchOptions.javaReleaseType = runtime.releaseType
        applyInstanceSettings(instance: instance, to: &launchOptions)

        let launchDirectory = launchOptions.runningDirectory ?? instance.runningDirectory
        let instanceDirectory = launchOptions.instanceDirectory ?? instance.runningDirectory

        let classpath = (launchOptions.classpathPrefixEntries
            + manifest.getLibraries().compactMap { $0.artifact?.path }.map { repository.librariesURL.appending(path: $0).path }
            + [instanceDirectory.appending(path: "\(instanceDirectory.lastPathComponent).jar").path])
            .joined(separator: ":")
        let values: [String: String] = [
            "natives_directory": instanceDirectory.appending(path: "natives").path,
            "launcher_name": "PCL.Mac",
            "launcher_version": Metadata.appVersion,
            "classpath_separator": ":",
            "library_directory": repository.librariesURL.path,
            "auth_player_name": account.profile.name,
            "version_name": launchOptions.customWindowTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? instanceDirectory.lastPathComponent,
            "game_directory": launchDirectory.path,
            "assets_root": repository.assetsURL.path,
            "assets_index_name": manifest.assetIndex.id,
            "auth_uuid": UUIDUtils.string(of: account.profile.id, withHyphens: false),
            "auth_access_token": accessToken,
            "user_type": launchOptions.userType,
            "version_type": "PCL.Mac",
            "user_properties": launchOptions.userProperties,
            "classpath": classpath
        ]
        let args = MinecraftLauncher.buildLaunchArguments(
            manifest: manifest,
            values: values,
            options: launchOptions
        )

        let escapedArgs = args.map(shellEscape).joined(separator: " ")
        var scriptLines: [String] = ["#!/bin/zsh", "cd \(shellEscape(launchDirectory.path))"]
        if let preLaunchCommand = launchOptions.preLaunchCommand?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            scriptLines.append(preLaunchCommand)
        }
        scriptLines.append("\(shellEscape(runtime.executableURL.path)) \(escapedArgs)")
        return scriptLines.joined(separator: "\n") + "\n"
    }

    static func applyInstanceSettings(instance: MinecraftInstance, to options: inout LaunchOptions) {
        options.instanceDirectory = instance.runningDirectory
        options.runningDirectory = instance.config.versionIsolationEnabled ? instance.runningDirectory : options.repository.url
        options.memory = instance.config.requestedMemoryMB
        options.customWindowTitle = instance.config.windowTitle
        options.additionalJVMArguments = LaunchOptions.parseArgumentString(instance.config.jvmArguments)
        options.additionalGameArguments = LaunchOptions.parseArgumentString(instance.config.gameArguments)
        options.classpathPrefixEntries = LaunchOptions.parseArgumentString(instance.config.classpathPrefix)
        options.preLaunchCommand = instance.config.preLaunchCommand.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        options.followProxyEnvironment = instance.config.followProxySettings
        options.skipResourceValidation = instance.config.disableResourceValidation
        options.enableLog4jDebug = instance.config.enableLog4jDebug
        options.autoJoinServer = LaunchOptions.parseAutoJoinServer(instance.config.autoJoinServer)
    }

    private static func shellEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
