//
//  DownloadItem.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/11/22.
//

import Foundation

public struct DownloadItem: Hashable {
    public let url: URL
    public let urls: [URL]
    public let mirrorKey: String?
    public let destination: URL
    public let sha1: String?
    public let executable: Bool
    
    public init(url: URL, destination: URL, sha1: String?, executable: Bool = false, mirrorKey: String? = nil) {
        self.init(urls: [url], destination: destination, sha1: sha1, executable: executable, mirrorKey: mirrorKey)
    }

    public init(urls: [URL], destination: URL, sha1: String?, executable: Bool = false, mirrorKey: String? = nil) {
        guard let firstURL = urls.first else {
            preconditionFailure("DownloadItem 至少需要一个下载 URL")
        }
        self.url = firstURL
        self.urls = urls
        self.mirrorKey = mirrorKey
        self.destination = destination
        self.sha1 = sha1
        self.executable = executable
    }
}

public enum ReplaceMethod {
    case replace, skip, `throw`
}
