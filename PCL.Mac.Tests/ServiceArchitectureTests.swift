import Foundation
import Testing
@testable import PCL_Mac

struct ServiceArchitectureTests {
    @Test func skinServiceCanDecodeDefaultSkin() {
        let image = SkinService.decodeSkinImage(from: SkinService.defaultSkinData)
        #expect(image != nil)
    }

    @Test func launcherConfigMutateUpdatesSharedState() {
        let originalLaunchCount = LauncherConfig.shared.launchCount
        let originalHasEnteredLauncher = LauncherConfig.shared.hasEnteredLauncher

        LauncherConfig.mutate {
            $0.launchCount = originalLaunchCount + 1
            $0.hasEnteredLauncher = !originalHasEnteredLauncher
        }

        #expect(LauncherConfig.shared.launchCount == originalLaunchCount + 1)
        #expect(LauncherConfig.shared.hasEnteredLauncher == !originalHasEnteredLauncher)

        LauncherConfig.mutate {
            $0.launchCount = originalLaunchCount
            $0.hasEnteredLauncher = originalHasEnteredLauncher
        }
    }
}
