import Foundation
import Testing
import Core

struct JavaRuntimeMirrorResolverTests {
    @Test func runtimeListURLsContainMirrors() {
        let urls = JavaRuntimeMirrorResolver.runtimeListURLs.map(\.absoluteString)
        #expect(urls.contains("https://launchermeta.mojang.com/v1/products/java-runtime/2ec0cc96c44e5a76b9c8b7c39df7210883d12871/all.json"))
        #expect(urls.contains("https://piston-meta.mojang.com/v1/products/java-runtime/2ec0cc96c44e5a76b9c8b7c39df7210883d12871/all.json"))
        #expect(urls.contains("https://bmclapi2.bangbang93.com/v1/products/java-runtime/2ec0cc96c44e5a76b9c8b7c39df7210883d12871/all.json"))
    }

    @Test func packageURLsExpandToMirrorCandidates() {
        let original = URL(string: "https://piston-data.mojang.com/v1/objects/test/runtime.tar.gz")!
        let urls = JavaRuntimeMirrorResolver.candidateURLs(for: original).map(\.absoluteString)
        #expect(urls.first == original.absoluteString)
        #expect(urls.contains("https://launcher.mojang.com/v1/objects/test/runtime.tar.gz"))
        #expect(urls.contains("https://bmclapi2.bangbang93.com/v1/objects/test/runtime.tar.gz"))
        #expect(urls.contains("https://bmclapi.bangbang93.com/v1/objects/test/runtime.tar.gz"))
    }

    @Test func bmclURLsStillContainOfficialFallbacks() {
        let original = URL(string: "https://bmclapi2.bangbang93.com/v1/objects/test/runtime.tar.gz")!
        let urls = JavaRuntimeMirrorResolver.candidateURLs(for: original).map(\.absoluteString)
        #expect(urls.contains("https://piston-data.mojang.com/v1/objects/test/runtime.tar.gz"))
        #expect(urls.contains("https://launcher.mojang.com/v1/objects/test/runtime.tar.gz"))
    }
}
