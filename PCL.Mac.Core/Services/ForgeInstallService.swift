//
//  ForgeInstallService.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/2/15.
//

import Foundation
import ZIPFoundation
import SwiftyJSON

public class ForgeInstallService {
    public init(
        minecraftVersion: MinecraftVersion,
        version: String,
        repository: MinecraftRepository,
        manifest: ClientManifest,
        runningDirectory: URL
    ) {
        self.minecraftVersion = minecraftVersion
        self.version = version
        self.repository = repository
        self.manifest = manifest
        self.runningDirectory = runningDirectory
        self.tempDirectory = URLConstants.tempURL.appending(path: "forge-install-\(UUID().uuidString.lowercased())")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    deinit {
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            do {
                try FileManager.default.removeItem(at: tempDirectory)
            } catch {
                err("删除临时目录失败：\(error.localizedDescription)")
            }
        }
    }
    
    internal let minecraftVersion: MinecraftVersion
    internal let version: String
    private let repository: MinecraftRepository
    private let manifest: ClientManifest
    private let runningDirectory: URL
    private let tempDirectory: URL
    private var installProfile: ForgeInstallProfile!
    private var values: [String: String]!
    
    private lazy var installerURL: URL = tempDirectory.appending(path: "installer")
    private lazy var librariesURL: URL = repository.librariesURL
    
    /// 下载安装器及其所需文件。
    /// - Parameter progressHandler: 进度回调。
    public func downloadFiles(progressHandler: @MainActor @escaping (Double) -> Void) async throws {
        let progressHandler: ConcurrentProgressHandler = .init(totalHandler: progressHandler)
        progressHandler.startCalculate()
        guard try await downloadInstaller(progressHandler: progressHandler.handler(withMultiplier: 0.3)) else {
            await progressHandler.stopCalculate()
            return
        }
        try copyLibraries()
        try await downloadInstallerDependencies(progressHandler: progressHandler.handler(withMultiplier: 0.7))
        self.values = makeValueDict()
        await progressHandler.stopCalculate()
    }
    
    /// 执行安装器。
    /// - Parameter progressHandler: 进度回调。
    public func executeProcessors(progressHandler: @MainActor @escaping (Double) -> Void) async throws {
        guard let installProfile else {
            await progressHandler(1)
            return
        }
        let processors: [ForgeInstallProfile.Processor] = installProfile.processors.filter { $0.sides?.contains(.client) ?? true }
        var progress: Double = 0
        let progressStep: Double = 1.0 / Double(processors.count)
        for processor in processors {
            if processor.args.contains("DOWNLOAD_MOJMAPS") {
                guard let destination: URL = values["MOJMAPS"].map(URL.init(fileURLWithPath:)) else {
                    throw SimpleError("下载混淆表失败：未找到混淆表下载项。")
                }
                try await downloadMojmaps(to: destination)
            } else {
                try executeProcessor(processor)
            }
            progress += progressStep
            await progressHandler(progress)
        }
        await progressHandler(1)
    }
    
    /// 下载安装器本体并解析。
    /// - Returns: 是否是新版本安装器，且需要继续执行后续步骤。
    private func downloadInstaller(progressHandler: @MainActor @escaping (Double) -> Void) async throws -> Bool {
        let destination: URL = tempDirectory.appending(path: "installer.jar")
        try await downloadInstallerFromMirrors(destination: destination, progressHandler: progressHandler)
        _ = try FileManager.default.unzipItem(at: destination, to: installerURL)
        
        // 处理客户端清单
        let manifestURL: URL = runningDirectory.appending(path: "\(runningDirectory.lastPathComponent).json")
        let parentURL: URL = runningDirectory.appending(path: ".parent/\(minecraftVersion).json")
        if !FileManager.default.fileExists(atPath: parentURL.path) {
            try FileManager.default.createDirectory(at: runningDirectory.appending(path: ".parent"), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: manifestURL, to: parentURL)
        }
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            try FileManager.default.removeItem(at: manifestURL)
        }
        // 此时 manifestURL 上没有文件
        
        let profileURL: URL = installerURL.appending(path: "install_profile.json")
        let data: Data = try .init(contentsOf: profileURL)
        let json: JSON = try .init(data: data)
        if json["install"].exists() { // 旧版本安装器，只需拷贝一个文件即可完成安装
            let forgeURL: URL = installerURL.appending(path: json["install"]["filePath"].stringValue)
            let forgeDestination: URL = repository.librariesURL.appending(path: MavenCoordinateUtils.path(of: json["install"]["path"].stringValue))
            if !FileManager.default.fileExists(atPath: forgeDestination.path) {
                try FileManager.default.createDirectory(at: forgeDestination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: forgeURL, to: forgeDestination)
            }
            
            try json["versionInfo"].rawData().write(to: manifestURL)
            return false
        } else {
            self.installProfile = try JSONDecoder.shared.decode(ForgeInstallProfile.self, from: data)
            try FileManager.default.moveItem(at: installerURL.appending(path: "version.json"), to: manifestURL)
            return true
        }
    }
    
    internal func installerDownloadURLs() -> [URL] {
        let path = "net/minecraftforge/forge/\(minecraftVersion)-\(version)/forge-\(minecraftVersion)-\(version)-installer.jar"
        return [
            URL(string: "https://files.minecraftforge.net/maven/\(path)")!,
            URL(string: "https://maven.minecraftforge.net/\(path)")!,
            URL(string: "https://bmclapi2.bangbang93.com/maven/\(path)")!,
            URL(string: "https://bmclapi.bangbang93.com/maven/\(path)")!,
            URL(string: "https://download.mcbbs.net/maven/\(path)")!,
            URL(string: "https://bmclapi2-cn.bangbang93.com/maven/\(path)")!
        ]
    }

    private func downloadInstallerFromMirrors(destination: URL, progressHandler: @MainActor @escaping (Double) -> Void) async throws {
        var errors: [String] = []
        let urls = NetworkMirrorSelector.prioritize(installerDownloadURLs(), key: "installer.forge")
        for url in urls {
            try Task.checkCancellation()
            do {
                try await SingleFileDownloader.download(url: url, destination: destination, sha1: nil, replaceMethod: .replace, progressHandler: progressHandler)
                NetworkMirrorSelector.markSuccess(url, key: "installer.forge")
                return
            } catch {
                errors.append("\(url.host ?? url.absoluteString): \(error.localizedDescription)")
            }
        }
        throw SimpleError(errors.isEmpty ? "Forge 安装器下载失败：无可用镜像。" : "Forge 安装器下载失败：\(errors.joined(separator: " | "))")
    }
    
    private func makeValueDict() -> [String: String] {
        let values: [String: String] = [
            "SIDE": "client",
            "INSTALLER": tempDirectory.appending(path: "installer.jar").path,
            "MINECRAFT_JAR": runningDirectory.appending(path: "\(runningDirectory.lastPathComponent).jar").path,
            "MINECRAFT_VERSION": minecraftVersion.id,
            "ROOT": repository.url.path,
            "LIBRARY_DIR": librariesURL.path
        ].merging(installProfile.data.mapValues { parseValue($0.client) }, uniquingKeysWith: { _, value in value })
        
        return values
    }
    
    
    private func parseValue(_ value: String) -> String {
        if value.starts(with: "/") {
            return installerURL.appending(path: value).path
        } else if value.starts(with: "[") && value.hasSuffix("]") {
            let path: String = MavenCoordinateUtils.path(of: String(value.dropFirst().dropLast()))
            return librariesURL.appending(path: path).path
        } else if value.starts(with: "'") && value.hasSuffix("'") {
            return String(value.dropFirst().dropLast())
        } else {
            return value
        }
    }
    
    private func copyLibraries() throws {
        let sourceDirectory: URL = installerURL.appending(path: "maven")
        guard FileManager.default.fileExists(atPath: sourceDirectory.path) else {
            return
        }
        let baseComponents: [String] = sourceDirectory.pathComponents
        
        guard let enumerator: FileManager.DirectoryEnumerator = FileManager.default.enumerator(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            throw SimpleError("创建 enumerator 失败。")
        }
        
        for case let url as URL in enumerator {
            guard let isRegularFile: Bool = try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
                  isRegularFile else {
                continue
            }
            let components: [String] = url.pathComponents
            guard components.starts(with: baseComponents) else { continue }
            let relativePath: String = components.dropFirst(baseComponents.count).joined(separator: "/")
            let destination: URL = repository.librariesURL.appending(path: relativePath)
            if FileManager.default.fileExists(atPath: destination.path) { continue }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: destination)
        }
    }
    
    /// 下载安装器所需的依赖项。
    private func downloadInstallerDependencies(progressHandler: @MainActor @escaping (Double) -> Void) async throws {
        let libraries: [ForgeInstallProfile.Library] = installProfile.libraries
        let downloadItems: [DownloadItem] = libraries.compactMap { $0.artifact.downloadItem(destinationDirectory: librariesURL) }
        try await MultiFileDownloader(items: downloadItems, concurrentLimit: 64, replaceMethod: .replace, progressHandler: progressHandler).start()
    }
    
    private func parseMavenCoord(coord: String) -> String {
        return librariesURL.appending(path: MavenCoordinateUtils.path(of: coord)).path
    }
    
    private func executeProcessor(_ processor: ForgeInstallProfile.Processor) throws {
        let classpath: String = (processor.classpath + [processor.jar]).map(parseMavenCoord(coord:)).joined(separator: ":")
        let mainClass: String = try JarUtils.mainClass(of: librariesURL.appending(path: MavenCoordinateUtils.path(of: processor.jar)))
        let javaArguments: [String] = ["-cp", classpath, mainClass] + processor.args.map { Utils.replace(parseValue($0), withValues: values, withDollarPrefix: false) }
        let process: Process = .init()
        let outputPipe: Pipe = .init()
        let outputLock: NSLock = .init()
        var outputData: Data = .init()
        let javaCommand = try selectJavaCommand()
        process.arguments = javaCommand.arguments + javaArguments
        process.executableURL = javaCommand.executableURL
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            outputLock.lock()
            outputData.append(chunk)
            outputLock.unlock()
        }
        try process.run()
        let startTime = Date()
        while process.isRunning {
            if Date().timeIntervalSince(startTime) > 180 {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                process.terminate()
                throw SimpleError("Forge 安装器 \(processor.jar) 执行超时。")
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        outputPipe.fileHandleForReading.readabilityHandler = nil
        let trailingData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        if !trailingData.isEmpty {
            outputLock.lock()
            outputData.append(trailingData)
            outputLock.unlock()
        }
        if process.terminationStatus != 0 {
            outputLock.lock()
            let output = String(decoding: outputData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            outputLock.unlock()
            if !output.isEmpty {
                err("Forge 处理器执行失败输出：\n\(output)")
                throw SimpleError("Forge 安装器 \(processor.jar) 执行失败。\(output)")
            }
            throw SimpleError("Forge 安装器 \(processor.jar) 执行失败。")
        }
    }

    private func selectJavaCommand() throws -> JavaCommand {
        let javaRange = manifest.supportedJavaMajorRange(
            for: minecraftVersion,
            modLoader: self is NeoforgeInstallService ? .neoforge : .forge,
            modLoaderVersion: version
        )
        let runtimes = try? JavaManager.shared.allJavaRuntimes()
        let prefersX64 = shouldPreferX64RuntimeForForge()
        let matchingRuntime = runtimes?
            .filter { javaRange.contains($0.majorVersion) }
            .sorted { compareJavaRuntime(lhs: $0, rhs: $1, prefersX64: prefersX64) }
            .first

        if let matchingRuntime {
            let shouldForceX64 = prefersX64 && runtimeCanRunUnderRosetta(matchingRuntime)
            let command = javaCommand(for: matchingRuntime, forceX64: shouldForceX64)
            log("Forge 安装器使用 Java：\(matchingRuntime.executableURL.path) (\(matchingRuntime.version))\(shouldForceX64 ? " [x64/Rosetta]" : "")")
            return command
        }

        let fallback = URL(fileURLWithPath: "/usr/bin/java")
        if FileManager.default.isExecutableFile(atPath: fallback.path) {
            warn("未找到符合要求的 Java 运行时，Forge 安装器回退到系统 Java：\(fallback.path)。需要版本范围：\(javaRange.lowerBound)-\(javaRange.upperBound)")
            return .init(executableURL: fallback, arguments: [])
        }

        throw SimpleError("未找到可用的 Java 运行时。Forge 安装需要 Java \(javaRange.lowerBound)-\(javaRange.upperBound)。")
    }

    private func compareJavaRuntime(lhs: JavaRuntime, rhs: JavaRuntime, prefersX64: Bool) -> Bool {
        let requiredMajor = manifest.requiredJavaMajorVersion(for: minecraftVersion)
        if prefersX64 {
            let lhsPreferred = runtimeCanRunUnderRosetta(lhs)
            let rhsPreferred = runtimeCanRunUnderRosetta(rhs)
            if lhsPreferred != rhsPreferred {
                return lhsPreferred
            }
        }
        let lhsDistance = abs(lhs.majorVersion - requiredMajor)
        let rhsDistance = abs(rhs.majorVersion - requiredMajor)
        if lhsDistance != rhsDistance {
            return lhsDistance < rhsDistance
        }
        if lhs.type != rhs.type {
            return lhs.type == .jdk
        }
        if lhs.releaseType != rhs.releaseType {
            switch (lhs.releaseType, rhs.releaseType) {
            case (.stableLTS, _), (.stable, .earlyAccess), (.stable, .unknown), (.unknown, .earlyAccess):
                return true
            default:
                return false
            }
        }
        return lhs.majorVersion < rhs.majorVersion
    }

    private func shouldPreferX64RuntimeForForge() -> Bool {
        Architecture.systemArchitecture() == .arm64 && minecraftVersion >= .init("1.21") && supportsX64JavaFallback()
    }

    private func runtimeCanRunUnderRosetta(_ runtime: JavaRuntime) -> Bool {
        runtime.architecture == .x64 || runtime.architecture == .fatFile
    }

    private func javaCommand(for runtime: JavaRuntime, forceX64: Bool) -> JavaCommand {
        guard forceX64 else {
            return .init(executableURL: runtime.executableURL, arguments: [])
        }
        return .init(
            executableURL: URL(fileURLWithPath: "/usr/bin/arch"),
            arguments: ["-x86_64", runtime.executableURL.path]
        )
    }

    private func supportsX64JavaFallback() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        process.arguments = ["-x86_64", "/usr/bin/true"]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private struct JavaCommand {
        let executableURL: URL
        let arguments: [String]
    }
    
    private func downloadMojmaps(to destination: URL) async throws {
        guard let url: URL = manifest.downloads.clientMappings?.url else {
            throw SimpleError("下载混淆表失败：未找到混淆表下载项。")
        }
        try await SingleFileDownloader.download(url: url, destination: destination, sha1: nil, replaceMethod: .skip)
    }
}
