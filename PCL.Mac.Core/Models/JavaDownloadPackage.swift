import Foundation

public struct JavaDownloadPackage {
    public enum Provider: String {
        case mojang
        case azulZulu
    }

    public enum Payload {
        case mojangManifest(MojangJavaList.JavaDownload)
        case zipArchive(url: URL)
    }

    public let provider: Provider
    public let majorVersion: Int
    public let version: String
    public let architecture: Architecture
    public let releaseTime: Date
    public let payload: Payload

    public init(
        provider: Provider,
        majorVersion: Int,
        version: String,
        architecture: Architecture,
        releaseTime: Date,
        payload: Payload
    ) {
        self.provider = provider
        self.majorVersion = majorVersion
        self.version = version
        self.architecture = architecture
        self.releaseTime = releaseTime
        self.payload = payload
    }

    public var displaySourceName: String {
        switch provider {
        case .mojang:
            return "Mojang Runtime"
        case .azulZulu:
            return "Azul Zulu"
        }
    }

    public var installDirectoryName: String {
        let sanitizedVersion = version
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "+", with: "-")
        return "\(provider.rawValue)-\(sanitizedVersion)-\(architecture.rawValue).bundle"
    }
}
