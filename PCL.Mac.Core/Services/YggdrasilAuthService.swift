import Foundation
import SwiftyJSON
import CryptoKit

public final class YggdrasilAuthService {
    public struct ServerMetadata: Codable {
        public let skinDomains: [String]?
        public let signaturePublickey: String?
        public let meta: Meta?

        public struct Meta: Codable {
            public let serverName: String?
            public let implementationName: String?
            public let implementationVersion: String?
            public let links: Links?

            public struct Links: Codable {
                public let homepage: String?
                public let register: String?
            }
        }
    }

    public struct AuthResponse {
        public let profile: PlayerProfile
        public let accessToken: String
        public let clientToken: String
        public let userProperties: Data?
    }

    private let apiRoot: URL

    public init(apiRoot: URL) {
        self.apiRoot = apiRoot
    }

    public static func resolveAPIURL(from raw: String) async throws -> URL {
        var normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.contains("://") {
            normalized = "https://\(normalized)"
        }
        guard let url = URL(string: normalized) else { throw SimpleError("无效的验证服务器地址") }
        guard url.scheme?.lowercased() == "https" else {
            throw SimpleError("第三方登录必须使用 HTTPS 验证服务器地址")
        }
        let response = try await Requests.get(url)
        if let ali = response.headers.first(where: { $0.key.lowercased() == "x-authlib-injector-api-location" })?.value,
           let aliURL = URL(string: ali, relativeTo: url)?.absoluteURL,
           aliURL != url {
            return aliURL
        }
        return url
    }

    public func fetchMetadata() async throws -> ServerMetadata {
        try await Requests.get(apiRoot).decode(ServerMetadata.self)
    }

    public func authenticate(username: String, password: String) async throws -> AuthResponse {
        let clientToken = UUID().uuidString.lowercased()
        let json = try await Requests.post(
            apiRoot.appendingPathComponent("authserver/authenticate"),
            body: [
                "username": username,
                "password": password,
                "clientToken": clientToken,
                "requestUser": true
            ],
            using: .json
        ).json()
        return try parseAuthResponse(json)
    }

    public func validate(accessToken: String, clientToken: String) async throws -> Bool {
        let response = try await Requests.post(
            apiRoot.appendingPathComponent("authserver/validate"),
            body: [
                "accessToken": accessToken,
                "clientToken": clientToken
            ],
            using: .json
        )
        return (200..<300).contains(response.statusCode)
    }

    public func refresh(accessToken: String, clientToken: String, selectedProfileID: UUID) async throws -> AuthResponse {
        let json = try await Requests.post(
            apiRoot.appendingPathComponent("authserver/refresh"),
            body: [
                "accessToken": accessToken,
                "clientToken": clientToken,
                "selectedProfile": [
                    "id": UUIDUtils.string(of: selectedProfileID)
                ],
                "requestUser": true
            ],
            using: .json
        ).json()
        return try parseAuthResponse(json)
    }

    private func parseAuthResponse(_ json: JSON) throws -> AuthResponse {
        let accessToken = json["accessToken"].stringValue
        let clientToken = json["clientToken"].stringValue
        guard !accessToken.isEmpty, !clientToken.isEmpty else {
            throw SimpleError("第三方登录失败：验证服务器未返回访问令牌或客户端令牌")
        }
        let selectedProfile = json["selectedProfile"]
        let profileName = selectedProfile["name"].stringValue
        guard let id = UUIDUtils.uuid(of: selectedProfile["id"].stringValue), !profileName.isEmpty else {
            throw SimpleError("第三方登录失败：缺少角色信息")
        }

        let propertiesArray = json["user"]["properties"].arrayValue
        let userPropertiesData = try? JSONSerialization.data(withJSONObject: propertiesArray.map { $0.dictionaryObject ?? [:] })
        let properties = propertiesArray.compactMap { item -> PlayerProfile.Property? in
            guard let name = item["name"].string,
                  let valueString = item["value"].string,
                  let value = valueString.data(using: .utf8)
            else { return nil }
            return .init(name: name, signature: item["signature"].string, value: value)
        }

        return AuthResponse(
            profile: .init(name: profileName, id: id, properties: properties),
            accessToken: accessToken,
            clientToken: clientToken,
            userProperties: userPropertiesData
        )
    }
}

public final class AuthlibInjectorService {
    public static let shared = AuthlibInjectorService()
    private init() {}

    public func prepare() async throws -> URL {
        if FileManager.default.fileExists(atPath: URLConstants.authlibInjectorURL.path) {
            return URLConstants.authlibInjectorURL
        }

        let latest: JSON = try await Requests.get("https://authlib-injector.yushi.moe/artifact/latest.json").json()
        guard let url = latest["download_url"].url else {
            throw SimpleError("无法获取 authlib-injector 下载地址")
        }
        let expectedSHA256 = latest["checksums"]["sha256"].stringValue.lowercased()
        let data = try await Requests.get(url).data
        let actualSHA256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard expectedSHA256.isEmpty || actualSHA256 == expectedSHA256 else {
            throw SimpleError("authlib-injector 校验失败，已拒绝使用损坏文件")
        }
        let tempURL = URLConstants.authlibInjectorURL.appendingPathExtension("download")
        try data.write(to: tempURL, options: .atomic)
        if FileManager.default.fileExists(atPath: URLConstants.authlibInjectorURL.path) {
            try FileManager.default.removeItem(at: URLConstants.authlibInjectorURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: URLConstants.authlibInjectorURL)
        return URLConstants.authlibInjectorURL
    }
}
