//
//  MicrosoftAccount.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/2/2.
//

import Foundation

public class MicrosoftAccount: Account {
    public private(set) var profile: PlayerProfile
    public private(set) var accessTokenValue: String
    private var refreshToken: String
    private var lastRefresh: Date
    public let id: UUID
    
    private enum CodingKeys: String, CodingKey {
        case profile, accessTokenValue = "accessToken", refreshToken, lastRefresh, id
    }
    
    public init(profile: PlayerProfile, accessToken: String, refreshToken: String) {
        self.profile = profile
        self.accessTokenValue = accessToken
        self.refreshToken = refreshToken
        self.lastRefresh = .now
        self.id = .init()
    }

    public func accessToken() -> String {
        accessTokenValue
    }
    
    public func refresh() async throws {
        let service: MicrosoftAuthService = .init()
        let response = try await service.refresh(token: refreshToken)
        self.profile = response.profile
        self.accessTokenValue = response.accessToken
        self.refreshToken = response.refreshToken
        lastRefresh = .now
    }
    
    public func shouldRefresh() -> Bool {
        return Date.now.timeIntervalSince(lastRefresh) >= 86400
    }
}
