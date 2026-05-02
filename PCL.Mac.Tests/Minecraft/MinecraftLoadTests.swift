//
//  MinecraftLoadTests.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/1/12.
//

import Foundation
@testable import Core
import Testing

struct MinecraftLoadTests {
    @Test private func testLoad() throws {
        let directory: URL = FileManager.default.temporaryDirectory.appending(path: "testLoad")
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        
        #expect(throws: MinecraftError.missingManifest) {
            try MinecraftInstance.load(from: directory)
        }
        FileManager.default.createFile(atPath: directory.appending(path: "testLoad.json").path, contents: "{}".data(using: .utf8)!)
        #expect(throws: ClientManifest.LoadError.formatError) {
            try MinecraftInstance.load(from: directory)
        }
    }

    @Test private func testThirdPartyAccountSerialization() throws {
        let profile = PlayerProfile(name: "Tester", id: UUID(), properties: [])
        let account = ThirdPartyAccount(
            profile: profile,
            apiRoot: URL(string: "https://example.com/api/yggdrasil/")!,
            serverName: "ExampleAuth",
            accountName: "tester@example.com",
            accessToken: "token-123",
            clientToken: "client-456",
            userProperties: Data("[]".utf8)
        )

        let data = try JSONEncoder.shared.encode(AccountWrapper(account))
        let decoded = try JSONDecoder.shared.decode(AccountWrapper.self, from: data)

        #expect(decoded.type == .thirdParty)
        #expect((decoded.account as? ThirdPartyAccount)?.serverName == "ExampleAuth")
    }

    @Test private func testThirdPartyAuthlibInjectorArguments() throws {
        let manifest = try JSONDecoder.shared.decode(ClientManifest.self, from: Data(#"{"arguments":{"game":[],"jvm":[]},"assetIndex":{"id":"1","sha1":"x","size":1,"totalSize":1,"url":"https://example.com/index.json"},"downloads":{"client":{"sha1":"x","size":1,"url":"https://example.com/client.jar"}},"id":"1.21.1","javaVersion":{"component":"java-runtime-gamma","majorVersion":21},"libraries":[],"mainClass":"net.minecraft.client.main.Main","type":"release"}"#.utf8))
        var options = LaunchOptions()
        options.profile = .init(name: "Tester", id: UUID(), properties: [])
        options.accessToken = "token-123"
        options.runningDirectory = URL(fileURLWithPath: "/tmp/instance")
        options.repository = .init(name: "TestRepo", url: URL(fileURLWithPath: "/tmp/repo"))
        options.manifest = manifest
        options.javaRuntime = .init(version: "21.0.7", majorVersion: 21, type: .jdk, architecture: .arm64, implementor: "Microsoft", executableURL: URL(fileURLWithPath: "/usr/bin/java"))
        options.thirdPartyAuth = .init(
            apiRoot: URL(string: "https://example.com/api/yggdrasil/")!,
            serverName: "ExampleAuth",
            metadata: .init(skinDomains: ["example.com"], signaturePublickey: nil, meta: .init(serverName: "ExampleAuth", implementationName: nil, implementationVersion: nil, links: nil)),
            injectorURL: URL(fileURLWithPath: "/tmp/authlib-injector.jar")
        )
        options.userType = "mojang"
        options.userProperties = "[]"

        let args = MinecraftLauncher.buildLaunchArguments(manifest: manifest, values: ["auth_player_name": "Tester"], options: options)
        #expect(args.contains(where: { $0.hasPrefix("-javaagent:/tmp/authlib-injector.jar=https://example.com/api/yggdrasil/") }))
        #expect(args.contains(where: { $0.hasPrefix("-Dauthlibinjector.yggdrasil.prefetched=") }))
    }

    @Test private func testInstanceConfigPersistsExtendedSettings() throws {
        let config = MinecraftInstance.Config()
        config.memoryMode = .auto
        config.versionIsolationEnabled = false
        config.windowTitle = "自定义标题"
        config.autoJoinServer = "mc.example.com:25565"
        config.jvmArguments = #"-Dfoo=bar 'hello world'"#
        config.gameArguments = "--fullscreen"
        config.classpathPrefix = "/tmp/a.jar /tmp/b.jar"
        config.preLaunchCommand = "echo ready"
        config.followProxySettings = false
        config.disableResourceValidation = true
        config.enableLog4jDebug = true

        let data = try JSONEncoder.shared.encode(config)
        let decoded = try JSONDecoder.shared.decode(MinecraftInstance.Config.self, from: data)

        #expect(decoded.memoryMode == .auto)
        #expect(decoded.versionIsolationEnabled == false)
        #expect(decoded.windowTitle == "自定义标题")
        #expect(decoded.autoJoinServer == "mc.example.com:25565")
        #expect(decoded.jvmArguments == #"-Dfoo=bar 'hello world'"#)
        #expect(decoded.gameArguments == "--fullscreen")
        #expect(decoded.classpathPrefix == "/tmp/a.jar /tmp/b.jar")
        #expect(decoded.preLaunchCommand == "echo ready")
        #expect(decoded.followProxySettings == false)
        #expect(decoded.disableResourceValidation)
        #expect(decoded.enableLog4jDebug)
    }

    @Test private func testLaunchOptionsApplyInstanceOverrides() throws {
        let manifest = try JSONDecoder.shared.decode(ClientManifest.self, from: Data(#"{"arguments":{"game":["--username","${auth_player_name}"],"jvm":["-cp","${classpath}"]},"assetIndex":{"id":"1","sha1":"x","size":1,"totalSize":1,"url":"https://example.com/index.json"},"downloads":{"client":{"sha1":"x","size":1,"url":"https://example.com/client.jar"}},"id":"1.21.1","javaVersion":{"component":"java-runtime-gamma","majorVersion":21},"libraries":[],"mainClass":"net.minecraft.client.main.Main","type":"release"}"#.utf8))

        var options = LaunchOptions()
        options.profile = .init(name: "Tester", id: UUID(), properties: [])
        options.accessToken = "token-123"
        options.runningDirectory = URL(fileURLWithPath: "/tmp/MyInstance")
        options.repository = .init(name: "TestRepo", url: URL(fileURLWithPath: "/tmp/repo"))
        options.manifest = manifest
        options.javaRuntime = .init(version: "21.0.7", majorVersion: 21, type: .jdk, architecture: .arm64, implementor: "Microsoft", executableURL: URL(fileURLWithPath: "/usr/bin/java"))
        options.customWindowTitle = "自定义窗口"
        options.additionalJVMArguments = LaunchOptions.parseArgumentString(#"-Dfoo=bar 'hello world'"#)
        options.additionalGameArguments = ["--fullscreen"]
        options.enableLog4jDebug = true
        options.autoJoinServer = .init(host: "mc.example.com", port: 25565)

        let args = MinecraftLauncher.buildLaunchArguments(
            manifest: manifest,
            values: [
                "auth_player_name": "Tester",
                "classpath": "/tmp/client.jar"
            ],
            options: options
        )

        #expect(args.contains("-Xdock:name=自定义窗口"))
        #expect(args.contains("-Dapple.awt.application.name=自定义窗口"))
        #expect(args.contains("-Dcom.apple.mrj.application.apple.menu.about.name=自定义窗口"))
        #expect(args.contains("-Dlog4j2.debug=true"))
        #expect(args.contains("-Dfoo=bar"))
        #expect(args.contains("hello world"))
        #expect(args.contains("--fullscreen"))
        #expect(args.contains("--server"))
        #expect(args.contains("mc.example.com"))
        #expect(args.contains("--port"))
        #expect(args.contains("25565"))
    }

    @Test private func testQuickPlayMultiplayerArgumentsAreUsedWhenSupported() throws {
        let manifest = try JSONDecoder.shared.decode(ClientManifest.self, from: Data(#"{"arguments":{"game":[{"rules":[{"action":"allow","features":{"has_quick_plays_support":true}}],"value":["--quickPlayPath","${quickPlayPath}"]},{"rules":[{"action":"allow","features":{"is_quick_play_multiplayer":true}}],"value":["--quickPlayMultiplayer","${quickPlayMultiplayer}"]}],"jvm":["-cp","${classpath}"]},"assetIndex":{"id":"1","sha1":"x","size":1,"totalSize":1,"url":"https://example.com/index.json"},"downloads":{"client":{"sha1":"x","size":1,"url":"https://example.com/client.jar"}},"id":"1.21.1","javaVersion":{"component":"java-runtime-gamma","majorVersion":21},"libraries":[],"mainClass":"net.minecraft.client.main.Main","type":"release"}"#.utf8))

        var options = LaunchOptions()
        options.profile = .init(name: "Tester", id: UUID(), properties: [])
        options.accessToken = "token-123"
        options.runningDirectory = URL(fileURLWithPath: "/tmp/MyInstance")
        options.repository = .init(name: "TestRepo", url: URL(fileURLWithPath: "/tmp/repo"))
        options.manifest = manifest
        options.javaRuntime = .init(version: "21.0.7", majorVersion: 21, type: .jdk, architecture: .arm64, implementor: "Microsoft", executableURL: URL(fileURLWithPath: "/usr/bin/java"))
        options.autoJoinServer = .init(host: "mc.example.com", port: 25565)
        options.quickPlayPath = "quickPlay/log.json"
        options.quickPlayMultiplayer = "mc.example.com:25565"

        let args = MinecraftLauncher.buildLaunchArguments(
            manifest: manifest,
            values: [
                "auth_player_name": "Tester",
                "classpath": "/tmp/client.jar",
                "quickPlayPath": "quickPlay/log.json",
                "quickPlayMultiplayer": "mc.example.com:25565"
            ],
            options: options
        )

        #expect(args.contains("--quickPlayPath"))
        #expect(args.contains("quickPlay/log.json"))
        #expect(args.contains("--quickPlayMultiplayer"))
        #expect(args.contains("mc.example.com:25565"))
        #expect(args.contains("--server") == false)
        #expect(args.contains("--port") == false)
    }
}

extension ClientManifest.LoadError: @retroactive Equatable {
    public static func == (lhs: Core.ClientManifest.LoadError, rhs: Core.ClientManifest.LoadError) -> Bool {
        switch (lhs, rhs) {
        case (.fileNotFound, .fileNotFound): true
        case (.formatError, .formatError): true
        case (.missingParentManifest, .missingParentManifest): true
        case (.failedToRead(_), .failedToRead(_)): true
        default: false
        }
    }
}
