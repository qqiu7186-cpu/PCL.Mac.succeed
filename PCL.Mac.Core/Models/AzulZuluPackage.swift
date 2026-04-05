import Foundation

public struct AzulZuluPackage: Decodable {
    public let downloadURL: URL
    public let javaVersion: [Int]
    public let name: String
    public let latest: Bool

    private enum CodingKeys: String, CodingKey {
        case downloadURL = "download_url"
        case javaVersion = "java_version"
        case name, latest
    }

    public var versionString: String {
        javaVersion.map(String.init).joined(separator: ".")
    }
}
