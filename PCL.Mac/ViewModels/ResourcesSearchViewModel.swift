//
//  ResourcesSearchViewModel.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/16.
//

import Foundation
import Core

class ResourcesSearchViewModel: ObservableObject {
    enum SearchSource: String, CaseIterable, Identifiable {
        case modrinth

        var id: String { rawValue }
        var localizedName: String { "Modrinth" }
    }

    enum SortOption: String, CaseIterable, Identifiable {
        case relevance
        case downloads
        case follows
        case newest
        case updated

        var id: String { rawValue }

        var localizedName: String {
            switch self {
            case .relevance: "默认"
            case .downloads: "下载量"
            case .follows: "关注数"
            case .newest: "最新创建"
            case .updated: "最近更新"
            }
        }

        var index: ModrinthAPIClient.SearchIndex {
            switch self {
            case .relevance: .relevance
            case .downloads: .downloads
            case .follows: .follows
            case .newest: .newest
            case .updated: .updated
            }
        }
    }

    @Published public private(set) var searchResults: [ProjectListItemModel] = []
    @Published public private(set) var phase: Phase = .loading
    @Published public private(set) var query: String = ""
    @Published public private(set) var isRefreshing: Bool = false
    @Published public private(set) var isLoadingNextPage: Bool = false
    @Published public private(set) var inlineErrorMessage: String?
    @Published public private(set) var selectedSource: SearchSource = .modrinth
    @Published public private(set) var selectedVersion: String?
    @Published public private(set) var selectedLoader: ModLoader?
    @Published public private(set) var selectedSort: SortOption = .relevance
    public let type: ModrinthProjectType
    public let requiredCategories: [String]
    public let loadingVM: MyLoadingViewModel = .init(text: "加载中")
    private let dependencies: AppDependencies
    private var lastSearchResponse: ModrinthAPIClient.SearchResponse?
    private var searchTask: Task<Void, Never>?

    public var totalPages: Int {
        guard let lastSearchResponse else { return 0 }
        return Int(ceil(Double(lastSearchResponse.totalHits) / Double(lastSearchResponse.limit)))
    }

    public var availableSources: [SearchSource] {
        SearchSource.allCases
    }

    public var availableVersions: [String] {
        CoreState.versionManifest.versions
            .filter { $0.type == .release }
            .prefix(24)
            .map(\.id)
    }

    public var availableLoaders: [ModLoader] {
        guard supportsLoaderFilter else { return [] }
        return [.fabric, .forge, .neoforge]
    }

    public var availableSortOptions: [SortOption] {
        SortOption.allCases
    }

    public var supportsLoaderFilter: Bool {
        requiredCategories.isEmpty && (type == .mod || type == .modpack)
    }

    public init(type: ModrinthProjectType, requiredCategories: [String] = [], dependencies: AppDependencies = .live) {
        self.type = type
        self.requiredCategories = requiredCategories
        self.dependencies = dependencies
    }

    deinit {
        searchTask?.cancel()
    }

    public func loadInitialResults() {
        submitSearch("")
    }

    public func submitSearch(_ query: String) {
        runSearch(query: query, pageIndex: 0)
    }

    public func submitPageChange(_ page: Int) {
        runSearch(query: query, pageIndex: page)
    }

    public func retry() {
        runSearch(query: query, pageIndex: 0)
    }

    public func updateSource(_ source: SearchSource) {
        guard selectedSource != source else { return }
        selectedSource = source
        runSearch(query: query, pageIndex: 0)
    }

    public func updateVersion(_ version: String?) {
        guard selectedVersion != version else { return }
        selectedVersion = version
        runSearch(query: query, pageIndex: 0)
    }

    public func updateLoader(_ loader: ModLoader?) {
        guard selectedLoader != loader else { return }
        selectedLoader = loader
        runSearch(query: query, pageIndex: 0)
    }

    public func updateSort(_ sort: SortOption) {
        guard selectedSort != sort else { return }
        selectedSort = sort
        runSearch(query: query, pageIndex: 0)
    }

    private func runSearch(query: String, pageIndex: Int) {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            await self.prepareForRequest(query: query, pageIndex: pageIndex)
            do {
                let response: ModrinthAPIClient.SearchResponse = try await self.dependencies.modrinthService.search(
                    type: self.type,
                    query,
                    forVersion: self.selectedVersion,
                    loaders: self.selectedLoader.map { [$0] } ?? [],
                    requiredCategories: self.requiredCategories,
                    index: self.selectedSort.index,
                    pageIndex: pageIndex,
                    limit: 40
                )
                guard !Task.isCancelled else { return }
                let projects = response.hits
                    .filter { $0.clientCompatibility != .unsupported }
                    .map(ProjectListItemModel.init(_:))
                await MainActor.run {
                    self.lastSearchResponse = response
                    self.searchResults = projects
                    self.inlineErrorMessage = nil
                    self.isRefreshing = false
                    self.isLoadingNextPage = false
                    self.phase = projects.isEmpty ? .empty : .content
                }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isRefreshing = false
                    self.isLoadingNextPage = false
                    if self.searchResults.isEmpty {
                        let wrappedError = AppError.wrap(error, category: .network, action: "搜索\(self.type.localizedName)失败")
                        self.phase = .failure(message: wrappedError.localizedDescription)
                        self.loadingVM.fail(with: wrappedError.localizedDescription)
                    } else {
                        self.inlineErrorMessage = AppError.wrap(error, category: .network, action: "刷新失败").localizedDescription
                        self.phase = .content
                    }
                }
            }
        }
    }

    @MainActor
    private func prepareForRequest(query: String, pageIndex: Int) {
        self.query = query
        self.inlineErrorMessage = nil
        let hasExistingContent = !searchResults.isEmpty
        if pageIndex > 0 {
            isLoadingNextPage = true
            return
        }

        if hasExistingContent {
            isRefreshing = true
        } else {
            loadingVM.reset()
            phase = .loading
        }
    }

    enum Phase: Equatable {
        case loading
        case content
        case empty
        case failure(message: String)
    }
}
