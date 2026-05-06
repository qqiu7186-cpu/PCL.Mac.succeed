import Foundation
import Testing
import Core
@testable import PCL_Mac

struct AppArchitectureTests {
    @Test func repositoryRouteTargetUsesStablePathIdentity() {
        let repository = MinecraftRepository(name: "测试目录", url: URL(fileURLWithPath: "/tmp/pcl-test"))
        let target = RepositoryRouteTarget(repository: repository)

        #expect(target.id == "/tmp/pcl-test")
        #expect(target.name == "测试目录")
    }

    @Test func projectInstallTargetKeepsLightweightFields() {
        let model = ProjectListItemModel(id: "abc", title: "Sodium", description: "desc", type: .mod, iconURL: nil, tags: [], supportDescription: "1.21", downloads: "1", lastUpdate: "today")
        let target = ProjectInstallTarget(project: model)

        #expect(target.id == model.id)
        #expect(target.title == model.title)
        #expect(target.type == model.type)
    }

    @Test func appErrorWrapPreservesActionAndCategory() {
        let wrapped = AppError.wrap(SimpleError("网络超时"), category: .network, action: "搜索资源失败")
        #expect(wrapped == .network("搜索资源失败：网络超时"))
    }

    @Test func memoryCacheStoresValues() {
        let cache = MemoryCache<String, Int>(countLimit: 8)
        cache.setValue(42, for: "answer")

        #expect(cache.object(forKey: "answer") == 42)
    }

    @Test @MainActor func diagnosticsExportWritesStructuredSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let exportURL = try DiagnosticsExportService.export(to: root, snapshotProvider: FakeDiagnosticsSnapshotProvider())
        let diagnosticsURL = exportURL.appending(path: "diagnostics.json")
        let data = try Data(contentsOf: diagnosticsURL)
        let snapshot = try JSONDecoder.shared.decode(DiagnosticsSnapshot.self, from: data)

        #expect(snapshot.currentRoute == "launch")
        #expect(snapshot.taskCount == 3)
        #expect(snapshot.repository?.name == "测试目录")
    }

    @Test func resourcesSearchViewModelLoadsContentFromInjectedService() async throws {
        let service = FakeModrinthService(searchBehavior: .success(try makeSearchResponse()))
        let viewModel = ResourcesSearchViewModel(type: .mod, dependencies: .init(modrinthService: service))

        viewModel.submitSearch("sodium")
        try await waitUntil(timeoutNanoseconds: 1_000_000_000) {
            viewModel.phase == .content
        }

        #expect(viewModel.query == "sodium")
        #expect(viewModel.searchResults.count == 1)
        #expect(viewModel.searchResults.first?.title == "Sodium")
    }

    @Test func resourcesSearchViewModelShowsFailureFromInjectedService() async throws {
        let service = FakeModrinthService(searchBehavior: .failure(SimpleError("网络错误")))
        let viewModel = ResourcesSearchViewModel(type: .mod, dependencies: .init(modrinthService: service))

        viewModel.submitSearch("broken")
        try await waitUntil(timeoutNanoseconds: 1_000_000_000) {
            if case .failure = viewModel.phase { return true }
            return false
        }

        if case .failure(let message) = viewModel.phase {
            #expect(message.contains("搜索模组失败"))
        } else {
            Issue.record("Expected failure phase")
        }
    }

    @Test @MainActor func favoritesDownloadViewModelLoadsProjectsFromInjectedService() async throws {
        let service = FakeModrinthService(searchBehavior: .success(try makeSearchResponse()))
        let viewModel = FavoritesDownloadViewModel(dependencies: .init(modrinthService: service))

        await viewModel.reload(ids: ["AABBCCDD"])

        #expect(viewModel.projects.count == 1)
        #expect(viewModel.projects.first?.title == "Sodium")
        #expect(viewModel.loading == false)
    }

    @Test @MainActor func otherSettingsViewModelDelegatesToInjectedServices() throws {
        let exporter = FakeSettingsExporter(url: URL(fileURLWithPath: "/tmp/test-logs.zip"))
        let updateRunner = FakeUpdateRunner()
        let viewModel = OtherSettingsViewModel(settingsExporter: exporter, updateFlowRunner: updateRunner)

        #expect(try viewModel.exportLogs().path == "/tmp/test-logs.zip")
        viewModel.checkUpdates()
        #expect(updateRunner.invocations == [true])
    }

    @Test @MainActor func updateSettingsViewModelPersistsChannelAndAutomaticBehavior() {
        let updateController = FakeUpdateSettingsController()
        let viewModel = UpdateSettingsViewModel(updateController: updateController)

        viewModel.selectChannel(.beta)
        viewModel.setAutomaticallyChecksForUpdates(false)
        viewModel.setAutomaticallyDownloadsUpdates(true)

        #expect(updateController.selectedChannelIdentifier == "beta")
        #expect(updateController.automaticallyChecksForUpdates == true)
        #expect(updateController.automaticallyDownloadsUpdates == true)
        #expect(viewModel.selectedChannel == .beta)
    }

    @Test @MainActor func updateSettingsViewModelMapsLegacyBetaGrayChannelToBeta() {
        let updateController = FakeUpdateSettingsController()
        updateController.selectedChannelIdentifier = "beta-gray"
        let viewModel = UpdateSettingsViewModel(updateController: updateController)

        #expect(viewModel.selectedChannel == .beta)
    }

    @Test func sparkleChannelRoutingUsesDefaultChannelForStable() {
        #expect(SparkleChannelRouting.normalizedChannelIdentifier(nil) == nil)
        #expect(SparkleChannelRouting.normalizedChannelIdentifier("   ") == nil)
        #expect(SparkleChannelRouting.allowedChannels(for: nil) == ["stable"])
        #expect(SparkleChannelRouting.allowedChannels(for: "   ") == ["stable"])
    }

    @Test func sparkleChannelRoutingUsesExplicitChannelForBeta() {
        #expect(SparkleChannelRouting.normalizedChannelIdentifier(" beta ") == "beta")
        #expect(SparkleChannelRouting.allowedChannels(for: "beta") == ["beta"])
    }

    @Test func sparkleChannelRoutingUsesStableRequestChannelByDefault() {
        #expect(SparkleChannelRouting.requestChannelIdentifier(for: nil) == "stable")
        #expect(SparkleChannelRouting.requestChannelIdentifier(for: "   ") == "stable")
        #expect(SparkleChannelRouting.requestChannelIdentifier(for: "beta") == "beta")
        #expect(SparkleChannelRouting.requestChannelIdentifier(for: "beta-gray") == "beta-gray")
    }

    @Test func sparkleChannelRoutingPrioritizesBetaGrayBeforeBeta() {
        #expect(SparkleChannelRouting.prioritizedRequestChannels(for: nil) == ["stable"])
        #expect(SparkleChannelRouting.prioritizedRequestChannels(for: "beta") == ["beta-gray", "beta"])
        #expect(SparkleChannelRouting.prioritizedRequestChannels(for: "beta-gray") == ["beta-gray"])
    }

    @Test func appcastCandidateSelectorPrefersHigherVersionOverBetaGrayPriority() {
        let candidates: [AppcastUpdateCandidate] = [
            .init(channelIdentifier: "beta-gray", versionString: "101"),
            .init(channelIdentifier: "beta", versionString: "105")
        ]

        let selected = AppcastUpdateCandidateSelector.preferredCandidate(
            from: candidates,
            prioritizedChannels: ["beta-gray", "beta"]
        )

        #expect(selected == .init(channelIdentifier: "beta", versionString: "105"))
    }

    @Test func appcastCandidateSelectorPrefersBetaGrayWhenVersionsTie() {
        let candidates: [AppcastUpdateCandidate] = [
            .init(channelIdentifier: "beta-gray", versionString: "105"),
            .init(channelIdentifier: "beta", versionString: "105")
        ]

        let selected = AppcastUpdateCandidateSelector.preferredCandidate(
            from: candidates,
            prioritizedChannels: ["beta-gray", "beta"]
        )

        #expect(selected == .init(channelIdentifier: "beta-gray", versionString: "105"))
    }

    @Test func appcastFeedCandidateEvaluatorRejectsCandidateBelowMinimumUpdateVersion() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <item>
              <sparkle:version>105</sparkle:version>
              <sparkle:minimumUpdateVersion>101</sparkle:minimumUpdateVersion>
            </item>
          </channel>
        </rss>
        """

        let candidate = AppcastFeedCandidateEvaluator.bestAvailableCandidate(
            in: Data(xml.utf8),
            channelIdentifier: "beta",
            currentBuildVersion: "100",
            currentSystemVersion: "14.4.0"
        )

        #expect(candidate == nil)
    }

    @Test func appcastFeedCandidateEvaluatorRejectsCandidateBelowMinimumSystemVersion() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <item>
              <sparkle:version>105</sparkle:version>
              <sparkle:minimumSystemVersion>15.0.0</sparkle:minimumSystemVersion>
            </item>
          </channel>
        </rss>
        """

        let candidate = AppcastFeedCandidateEvaluator.bestAvailableCandidate(
            in: Data(xml.utf8),
            channelIdentifier: "beta",
            currentBuildVersion: "100",
            currentSystemVersion: "14.4.0"
        )

        #expect(candidate == nil)
    }

    @Test func appcastFeedCandidateEvaluatorSelectsHighestEligibleVersion() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <item>
              <sparkle:version>101</sparkle:version>
            </item>
            <item>
              <sparkle:version>105</sparkle:version>
              <sparkle:minimumSystemVersion>14.0.0</sparkle:minimumSystemVersion>
            </item>
            <item>
              <sparkle:version>110</sparkle:version>
              <sparkle:minimumSystemVersion>15.0.0</sparkle:minimumSystemVersion>
            </item>
          </channel>
        </rss>
        """

        let candidate = AppcastFeedCandidateEvaluator.bestAvailableCandidate(
            in: Data(xml.utf8),
            channelIdentifier: "beta",
            currentBuildVersion: "100",
            currentSystemVersion: "14.4.0"
        )

        #expect(candidate == .init(channelIdentifier: "beta", versionString: "105"))
    }

    @Test func appcastFeedCandidateEvaluatorRejectsCandidateAboveMaximumSystemVersion() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <item>
              <sparkle:version>105</sparkle:version>
              <sparkle:maximumSystemVersion>14.0.0</sparkle:maximumSystemVersion>
            </item>
          </channel>
        </rss>
        """

        let candidate = AppcastFeedCandidateEvaluator.bestAvailableCandidate(
            in: Data(xml.utf8),
            channelIdentifier: "beta",
            currentBuildVersion: "100",
            currentSystemVersion: "14.4.0"
        )

        #expect(candidate == nil)
    }

    @Test func appcastFeedCandidateEvaluatorSupportsEnclosureSparkleVersionAttribute() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <item>
              <enclosure url="https://example.com/PCL.Mac.zip" sparkle:version="108" length="1" type="application/octet-stream" />
            </item>
          </channel>
        </rss>
        """

        let candidate = AppcastFeedCandidateEvaluator.bestAvailableCandidate(
            in: Data(xml.utf8),
            channelIdentifier: "beta",
            currentBuildVersion: "100",
            currentSystemVersion: "14.4.0"
        )

        #expect(candidate == .init(channelIdentifier: "beta", versionString: "108"))
    }

    @Test func sparkleChannelRoutingRejectsBetaPathForStable() {
        let betaURL = URL(string: "https://update.gzitvs.cn/media/meta/cn.gzitvs.PCL-Mac/beta/updates/PCL.Mac%201.0.1.zip")
        #expect(SparkleChannelRouting.allowsAppcastItem(itemChannelIdentifier: nil, fileURL: betaURL, selectedChannelIdentifier: nil) == false)
        #expect(SparkleChannelRouting.allowsAppcastItem(itemChannelIdentifier: nil, fileURL: betaURL, selectedChannelIdentifier: "beta") == true)
    }

    @Test func sparkleChannelRoutingTreatsExplicitStableAsStableChannel() {
        let stableURL = URL(string: "https://update.gzitvs.cn/media/meta/cn.gzitvs.PCL-Mac/stable/updates/PCL.Mac%201.0.1.zip")
        #expect(SparkleChannelRouting.allowsAppcastItem(itemChannelIdentifier: "stable", fileURL: stableURL, selectedChannelIdentifier: nil) == true)
        #expect(SparkleChannelRouting.allowsAppcastItem(itemChannelIdentifier: nil, fileURL: stableURL, selectedChannelIdentifier: nil) == true)
    }

    @Test func sparkleChannelRoutingSupportsBetaGrayPath() {
        let betaGrayURL = URL(string: "https://update.gzitvs.cn/media/meta/cn.gzitvs.PCL-Mac/beta-gray/updates/PCL.Mac%201.0.1.zip")
        #expect(SparkleChannelRouting.inferredChannelIdentifier(from: betaGrayURL) == "beta-gray")
        #expect(SparkleChannelRouting.allowsAppcastItem(itemChannelIdentifier: nil, fileURL: betaGrayURL, selectedChannelIdentifier: nil) == false)
        #expect(SparkleChannelRouting.allowsAppcastItem(itemChannelIdentifier: nil, fileURL: betaGrayURL, selectedChannelIdentifier: "beta-gray") == true)
    }

    @Test func sparkleChannelRoutingRejectsMismatchedExplicitChannel() {
        let stableURL = URL(string: "https://update.gzitvs.cn/media/meta/cn.gzitvs.PCL-Mac/stable/updates/PCL.Mac%201.0.1.zip")
        #expect(SparkleChannelRouting.allowsAppcastItem(itemChannelIdentifier: "beta", fileURL: stableURL, selectedChannelIdentifier: nil) == false)
        #expect(SparkleChannelRouting.allowsAppcastItem(itemChannelIdentifier: "beta", fileURL: stableURL, selectedChannelIdentifier: "beta") == true)
    }

    @Test @MainActor func javaSettingsViewModelRefreshUsesInjectedManager() throws {
        let manager = FakeJavaRuntimeManager(runtimes: [])
        let viewModel = JavaSettingsViewModel(javaManager: manager)

        try viewModel.refreshJavaList()

        #expect(manager.researchCallCount == 1)
        #expect(viewModel.javaList.isEmpty)
    }

    @Test @MainActor func javaSettingsViewModelInstallFlowDelegatesToInjectedCollaborators() async throws {
        let download = JavaDownloadPackage(
            provider: .azulZulu,
            majorVersion: 21,
            version: "21.0.2",
            architecture: .arm64,
            releaseTime: .distantPast,
            payload: .tarGzArchive(url: URL(string: "https://example.com/java.tar.gz")!)
        )
        let manager = FakeJavaRuntimeManager(runtimes: [])
        let prompter = FakeJavaDownloadPrompter(selection: 0)
        let executor = FakeTaskExecutor()
        let navigator = FakeTaskRouteNavigator()
        let viewModel = JavaSettingsViewModel(
            javaManager: manager,
            javaDownloadPrompter: prompter,
            taskExecutor: executor,
            taskNavigator: navigator
        )

        viewModel.javaDownloadsProvider = { _, _, _ in [download] }
        await #expect(throws: Never.self) {
            try await viewModel.startInstallJavaFlow()
        }

        #expect(prompter.selectionRequests == 1)
        #expect(executor.executedTaskNames.count == 1)
        #expect(executor.executedTaskNames[0].contains("Java"))
        #expect(navigator.showTasksCallCount == 1)
    }

    @Test func instancePageActionServiceAppliesVersionIsolationAndWindowTitleOverrides() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let instanceDirectory = root.appending(path: "Test Instance")
        let repositoryURL = root.appending(path: "repository")
        try FileManager.default.createDirectory(at: instanceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manifestJSON = #"{"arguments":{"game":[],"jvm":[]},"assetIndex":{"id":"1","sha1":"x","size":1,"totalSize":1,"url":"https://example.com/index.json"},"downloads":{"client":{"sha1":"x","size":1,"url":"https://example.com/client.jar"}},"id":"1.21.1","javaVersion":{"component":"java-runtime-gamma","majorVersion":21},"libraries":[],"mainClass":"net.minecraft.client.main.Main","type":"release"}"#
        let manifest = try JSONDecoder.shared.decode(ClientManifest.self, from: Data(manifestJSON.utf8))
        let config = MinecraftInstance.Config()
        config.versionIsolationEnabled = false
        config.windowTitle = "自定义标题"
        config.gameArguments = "--fullscreen"

        let instance = MinecraftInstance(
            runningDirectory: instanceDirectory,
            version: .init("1.21.1"),
            manifest: manifest,
            config: config,
            modLoader: nil,
            modLoaderVersion: nil
        )
        let repository = MinecraftRepository(name: "测试仓库", url: repositoryURL)
        var options = LaunchOptions()
        options.repository = repository
        options.runningDirectory = instanceDirectory

        InstancePageActionService.applyInstanceSettings(instance: instance, to: &options)

        #expect(options.instanceDirectory == instanceDirectory)
        #expect(options.runningDirectory == repositoryURL)
        #expect(options.customWindowTitle == "自定义标题")
        #expect(options.additionalGameArguments == ["--fullscreen"])
    }
}

private struct FakeDiagnosticsSnapshotProvider: DiagnosticsSnapshotProviding {
    @MainActor
    func snapshot() -> DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            appVersion: "1.0.0",
            bundleVersion: "100",
            timestamp: "2026-04-28T00:00:00Z",
            systemVersion: "macOS Test",
            currentRoute: "launch",
            repository: .init(name: "测试目录", path: "/tmp/repo"),
            instance: .init(name: "Test Instance", version: "1.20.1", directory: "/tmp/repo/Test Instance"),
            taskCount: 3
        )
    }
}

private struct FakeModrinthService: ModrinthProjectServicing {
    enum SearchBehavior {
        case success(ModrinthAPIClient.SearchResponse)
        case failure(Error)
    }

    let searchBehavior: SearchBehavior

    func search(type: ModrinthProjectType, _ query: String?, forVersion gameVersion: String?, loaders: [ModLoader], requiredCategories: [String], index: ModrinthAPIClient.SearchIndex, pageIndex: Int, limit: Int) async throws -> ModrinthAPIClient.SearchResponse {
        switch searchBehavior {
        case .success(let response): response
        case .failure(let error): throw error
        }
    }

    func project(_ slug: String, revalidate: Bool) async throws -> ModrinthProject {
        try makeProject()
    }

    func versions(ofProject slug: String, revalidate: Bool) async throws -> [ModrinthVersion] {
        []
    }
}

private final class FakeSettingsExporter: SettingsLogExporting {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    func exportLogs() throws -> URL { url }
}

private final class FakeUpdateRunner: AppUpdateFlowRunning {
    private(set) var invocations: [Bool] = []

    func runInteractiveUpdateFlow(manually: Bool) {
        invocations.append(manually)
    }
}

private final class FakeUpdateSettingsController: AppUpdateSettingsControlling {
    var canUseSparkle: Bool = true
    var automaticallyChecksForUpdates: Bool = true
    var automaticallyDownloadsUpdates: Bool = false
    var allowsAutomaticDownloads: Bool = true
    var selectedChannelIdentifier: String?
    var currentFeedURLString: String? = "https://update.gzitvs.cn/api/v1/appcast/cn.gzitvs.PCL-Mac/?channel=stable&current_build=1"
    var softwareUpdateUserID: String = "test-user-001"
    private(set) var invocations: [Bool] = []

    func runInteractiveUpdateFlow(manually: Bool) {
        invocations.append(manually)
    }

    func openReleaseNotesPage() {
    }
}

private final class FakeJavaRuntimeManager: JavaRuntimeManaging {
    @Published private var runtimesStorage: [JavaRuntime]
    private let brokenRuntimePaths: Set<String>
    private(set) var researchCallCount = 0

    init(runtimes: [JavaRuntime], brokenRuntimePaths: Set<String> = []) {
        self.runtimesStorage = runtimes
        self.brokenRuntimePaths = brokenRuntimePaths
    }

    var javaRuntimesPublisher: Published<[JavaRuntime]>.Publisher { $runtimesStorage }

    func research() throws {
        researchCallCount += 1
    }

    func allJavaRuntimes() throws -> [JavaRuntime] {
        runtimesStorage
    }

    func isBrokenRuntime(_ runtime: JavaRuntime) -> Bool {
        brokenRuntimePaths.contains(runtime.executableURL.path)
    }
}

private final class FakeJavaDownloadPrompter: JavaDownloadPrompting {
    let selection: Int?
    private(set) var selectionRequests = 0

    init(selection: Int?) {
        self.selection = selection
    }

    func selectJavaDownload(from downloads: [JavaDownloadPackage], itemBuilder: (JavaDownloadPackage) -> ListItem) async -> Int? {
        selectionRequests += 1
        return selection
    }
}

private final class FakeTaskExecutor: TaskExecuting {
    private(set) var executedTaskNames: [String] = []

    func execute(_ task: MyTask<JavaInstallTask.Model>) {
        executedTaskNames.append(task.name)
    }
}

private final class FakeTaskRouteNavigator: TaskRouteNavigating {
    private(set) var showTasksCallCount = 0

    func showTasksPage() {
        showTasksCallCount += 1
    }
}

private func makeSearchResponse() throws -> ModrinthAPIClient.SearchResponse {
    let json = #"{"hits":[{"project_id":"AABBCCDD","slug":"sodium","project_type":"mod","title":"Sodium","description":"Fast","downloads":1,"updated":"2026-04-28T00:00:00Z","categories":["fabric"],"client_side":"required","versions":["1.21.1"]}],"offset":0,"limit":40,"total_hits":1}"#
    return try JSONDecoder.shared.decode(ModrinthAPIClient.SearchResponse.self, from: Data(json.utf8))
}

private func makeProject() throws -> ModrinthProject {
    let json = #"{"project_id":"AABBCCDD","slug":"sodium","project_type":"mod","title":"Sodium","description":"Fast","downloads":1,"updated":"2026-04-28T00:00:00Z","categories":["fabric"],"client_side":"required","versions":["1.21.1"]}"#
    return try JSONDecoder.shared.decode(ModrinthProject.self, from: Data(json.utf8))
}

private func waitUntil(timeoutNanoseconds: UInt64, condition: @escaping () -> Bool) async throws {
    let start = DispatchTime.now().uptimeNanoseconds
    while !condition() {
        if DispatchTime.now().uptimeNanoseconds - start > timeoutNanoseconds {
            throw SimpleError("等待条件超时")
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}
