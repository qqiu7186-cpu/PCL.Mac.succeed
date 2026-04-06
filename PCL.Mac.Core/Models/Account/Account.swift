//
//  Account.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/1/14.
//

import Foundation

public protocol Account: Codable {
    var profile: PlayerProfile { get }
    var id: UUID { get }
    func accessToken() -> String
    func refresh() async throws
    func shouldRefresh() -> Bool
    func configureLaunchOptions(_ options: inout LaunchOptions) async throws
}

public enum AccountType: String, Codable {
    case offline, microsoft, thirdParty
}

public class AccountWrapper: Codable {
    public let type: AccountType
    public let account: Account
    
    public init(_ account: Account) {
        self.type = account.type
        self.account = account
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
        case account
    }
    
    public required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(AccountType.self, forKey: .type)
        switch type {
        case .offline:
            self.account = try container.decode(OfflineAccount.self, forKey: .account)
        case .microsoft:
            self.account = try container.decode(MicrosoftAccount.self, forKey: .account)
        case .thirdParty:
            self.account = try container.decode(ThirdPartyAccount.self, forKey: .account)
        }
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(account, forKey: .account)
    }
}

public extension Account {
    var type: AccountType {
        switch self {
        case is OfflineAccount:
            .offline
        case is MicrosoftAccount:
            .microsoft
        case is ThirdPartyAccount:
            .thirdParty
        default:
            fatalError() // unreachable
        }
    }

    func configureLaunchOptions(_ options: inout LaunchOptions) async throws {}
}

public final class ThirdPartyAccount: Account {
    public private(set) var profile: PlayerProfile
    public let id: UUID
    public let apiRoot: URL
    public let serverName: String
    public let accountName: String
    private var _accessToken: String
    private var clientToken: String
    private var userProperties: Data?
    private var selectedProfileID: UUID
    private var lastRefresh: Date

    private enum CodingKeys: String, CodingKey {
        case profile
        case id
        case apiRoot
        case serverName
        case accountName
        case _accessToken = "accessToken"
        case clientToken
        case userProperties
        case selectedProfileID
        case lastRefresh
    }

    public init(
        profile: PlayerProfile,
        apiRoot: URL,
        serverName: String,
        accountName: String,
        accessToken: String,
        clientToken: String,
        userProperties: Data?
    ) {
        self.profile = profile
        self.id = .init()
        self.apiRoot = apiRoot
        self.serverName = serverName
        self.accountName = accountName
        self._accessToken = accessToken
        self.clientToken = clientToken
        self.userProperties = userProperties
        self.selectedProfileID = profile.id
        self.lastRefresh = .now
    }

    public func accessToken() -> String { _accessToken }

    public func refresh() async throws {
        let service = YggdrasilAuthService(apiRoot: apiRoot)
        if try await service.validate(accessToken: _accessToken, clientToken: clientToken) {
            self.lastRefresh = .now
            return
        }
        let response = try await service.refresh(accessToken: _accessToken, clientToken: clientToken, selectedProfileID: selectedProfileID)
        self.profile = response.profile
        self._accessToken = response.accessToken
        self.clientToken = response.clientToken
        self.userProperties = response.userProperties
        self.selectedProfileID = response.profile.id
        self.lastRefresh = .now
    }

    public func shouldRefresh() -> Bool {
        true
    }

    public func configureLaunchOptions(_ options: inout LaunchOptions) async throws {
        let service = YggdrasilAuthService(apiRoot: apiRoot)
        let metadata = try await service.fetchMetadata()
        let injectorURL = try await AuthlibInjectorService.shared.prepare()

        options.userType = "mojang"
        options.userProperties = userProperties.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        options.thirdPartyAuth = .init(
            apiRoot: apiRoot,
            serverName: serverName,
            metadata: metadata,
            injectorURL: injectorURL
        )
    }
}
