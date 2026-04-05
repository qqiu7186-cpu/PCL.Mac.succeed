import Foundation
import Testing
import Core

struct AzulZuluPackageTests {
    @Test func decodePackage() throws {
        let json = #"[{"download_url":"https://cdn.azul.com/zulu/bin/zulu26.28.63-ca-fx-jdk26.0.0-macosx_aarch64.zip","java_version":[26,0,0],"latest":true,"name":"zulu26.28.63-ca-fx-jdk26.0.0-macosx_aarch64.zip"}]"#
        let packages = try JSONDecoder.shared.decode([AzulZuluPackage].self, from: Data(json.utf8))
        #expect(packages.count == 1)
        #expect(packages[0].versionString == "26.0.0")
        #expect(packages[0].downloadURL.absoluteString.contains("zulu26"))
    }
}
