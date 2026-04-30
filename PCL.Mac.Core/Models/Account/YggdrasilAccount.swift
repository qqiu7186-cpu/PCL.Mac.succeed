//
//  YggdrasilAccount.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/4/7.
//

import Foundation

public class YggdrasilAccount: Account {
    public let id: UUID
    public private(set) var profile: PlayerProfile
    public let authServer: String
    public let authServerURL: URL
    public private(set) var cachedMetadata: String?
    
    private lazy var service: YggdrasilService = .init(authServerURL: authServerURL)
    public private(set) var accessTokenValue: String
    private var clientToken: String
    
    private enum CodingKeys: String, CodingKey {
        case id, profile, authServer, authServerURL, cachedMetadata, accessTokenValue = "accessToken", clientToken
    }
    
    public init(
        profile: PlayerProfile,
        authServer: String,
        authServerURL: URL,
        accessToken: String,
        clientToken: String
    ) {
        self.id = .init()
        self.profile = profile
        self.authServer = authServer
        self.authServerURL = authServerURL
        self.accessTokenValue = accessToken
        self.clientToken = clientToken
    }

    public func accessToken() -> String {
        accessTokenValue
    }
    
    public func refresh() async throws {
        let response = try await service.refresh(accessTokenValue, clientToken: clientToken)
        self.accessTokenValue = response.accessToken
        if let profile = response.selectedProfile {
            let fullProfile: PlayerProfile = try await service.fullProfile(for: profile.id)
            self.profile = fullProfile
        }
    }
    
    public func shouldRefresh() -> Bool {
        true
    }
    
    public func fetchMetadata() async throws -> String {
        let metadata = try await service.fetchMetadata().encoded
        self.cachedMetadata = metadata
        return metadata
    }
}
