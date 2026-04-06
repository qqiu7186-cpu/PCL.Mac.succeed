//
//  LaunchOptions.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/11/21.
//

import Foundation

public struct LaunchOptions {
    public struct ThirdPartyAuthContext: Codable {
        public let apiRoot: URL
        public let serverName: String
        public let metadata: YggdrasilAuthService.ServerMetadata
        public let injectorURL: URL

        public init(apiRoot: URL, serverName: String, metadata: YggdrasilAuthService.ServerMetadata, injectorURL: URL) {
            self.apiRoot = apiRoot
            self.serverName = serverName
            self.metadata = metadata
            self.injectorURL = injectorURL
        }
    }

    public struct JavaFallbackPolicy: Codable {
        public var enabled: Bool = true
        public var preferredReleaseOrder: [JavaRuntime.JavaReleaseType] = [.stableLTS, .stable, .earlyAccess]
        public var fallbackMajors: [Int] = [21, 25, 26]
        public var allowRosettaX64OnAppleSilicon: Bool = true
        public var skipRuntimePrecheck: Bool = false
        public var sanitizeJvmArguments: Bool = true

        public init() {}
    }

    public var profile: PlayerProfile!
    public var accessToken: String!
    public var javaRuntime: JavaRuntime!
    public var runningDirectory: URL!
    public var manifest: ClientManifest!
    public var repository: MinecraftRepository!
    public var memory: UInt64 = 4096
    public var demo: Bool = false
    public var javaReleaseType: JavaRuntime.JavaReleaseType?
    public var javaFallbackPolicy: JavaFallbackPolicy = .init()
    public var userType: String = "msa"
    public var userProperties: String = "{}"
    public var thirdPartyAuth: ThirdPartyAuthContext?
    
    public func validate() throws {
        if profile == nil || accessToken == nil { throw LaunchError.missingAccount }
        if javaRuntime == nil { throw LaunchError.missingJava }
        if runningDirectory == nil { throw LaunchError.missingRunningDirectory }
        if manifest == nil { throw LaunchError.missingManifest }
        if repository == nil { throw LaunchError.missingRepository }
    }
    
    public init() {}
}
