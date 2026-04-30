import Foundation
import Core

protocol ModrinthProjectServicing {
    func search(
        type: ModrinthProjectType,
        _ query: String?,
        forVersion gameVersion: String?,
        loaders: [ModLoader],
        requiredCategories: [String],
        index: ModrinthAPIClient.SearchIndex,
        pageIndex: Int,
        limit: Int
    ) async throws -> ModrinthAPIClient.SearchResponse
    func project(_ slug: String, revalidate: Bool) async throws -> ModrinthProject
    func versions(ofProject slug: String, revalidate: Bool) async throws -> [ModrinthVersion]
}

extension ModrinthAPIClient: ModrinthProjectServicing {}

struct AppDependencies {
    let modrinthService: ModrinthProjectServicing

    static let live = AppDependencies(modrinthService: ModrinthAPIClient.shared)
}
