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
