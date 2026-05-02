//
//  LaunchOptions.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/11/21.
//

import Foundation

public struct LaunchOptions {
    public struct AutoJoinServer: Codable, Equatable {
        public var host: String
        public var port: Int?

        public init(host: String, port: Int? = nil) {
            self.host = host
            self.port = port
        }
    }

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
    public var instanceDirectory: URL?
    public var manifest: ClientManifest!
    public var repository: MinecraftRepository!
    public var memory: UInt64 = 4096
    public var demo: Bool = false
    public var javaReleaseType: JavaRuntime.JavaReleaseType?
    public var javaFallbackPolicy: JavaFallbackPolicy = .init()
    public var userType: String = "msa"
    public var userProperties: String = "{}"
    public var thirdPartyAuth: ThirdPartyAuthContext?
    public var customWindowTitle: String?
    public var additionalJVMArguments: [String] = []
    public var additionalGameArguments: [String] = []
    public var classpathPrefixEntries: [String] = []
    public var preLaunchCommand: String?
    public var followProxyEnvironment: Bool = true
    public var skipResourceValidation: Bool = false
    public var enableLog4jDebug: Bool = false
    public var autoJoinServer: AutoJoinServer?
    public var quickPlayPath: String?
    public var quickPlayMultiplayer: String?
    
    // Authlib Injector
    public var authlibInjectorPath: String?
    public var authServerURL: URL?
    public var prefetchedMeta: String?
    
    public func validate() throws {
        if profile == nil || accessToken == nil { throw LaunchError.missingAccount }
        if javaRuntime == nil { throw LaunchError.missingJava }
        if runningDirectory == nil { throw LaunchError.missingRunningDirectory }
        if manifest == nil { throw LaunchError.missingManifest }
        if repository == nil { throw LaunchError.missingRepository }
    }
    
    public init() {}

    public static func parseArgumentString(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var isEscaping = false

        for character in text {
            if isEscaping {
                current.append(character)
                isEscaping = false
                continue
            }

            if character == "\\" {
                isEscaping = true
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                continue
            }

            if character.isWhitespace {
                self.appendTokenIfNeeded(&tokens, current: &current)
                continue
            }

            current.append(character)
        }

        if isEscaping {
            current.append("\\")
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    public static func parseAutoJoinServer(_ text: String?) -> AutoJoinServer? {
        guard let rawText = text?.trimmingCharacters(in: .whitespacesAndNewlines), !rawText.isEmpty else {
            return nil
        }

        let components = rawText.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = components.first else { return nil }
        let host = String(first).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return nil }

        if components.count == 1 {
            return .init(host: host)
        }

        let portText = String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !portText.isEmpty, let port = Int(portText), (1...65535).contains(port) else {
            return nil
        }
        return .init(host: host, port: port)
    }

    private static func appendTokenIfNeeded(_ tokens: inout [String], current: inout String) {
        guard !current.isEmpty else { return }
        tokens.append(current)
        current.removeAll(keepingCapacity: true)
    }
}
