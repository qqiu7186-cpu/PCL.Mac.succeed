# PCL.Mac Agent Notes

## Sources of truth
- This repo is an **Xcode project**, not a Swift Package. Use `PCL.Mac.xcodeproj`, `Configs/*.xcconfig`, and `.github/workflows/*.yml` as the executable sources of truth.
- Existing PR review guidance lives in `.github/copilot-instructions.md`.

## Verified local commands
- List schemes: `xcodebuild -list -project "PCL.Mac.xcodeproj"`
- Debug build: `xcodebuild -project "PCL.Mac.xcodeproj" -scheme "PCL.Mac" -configuration Debug -destination 'platform=macOS' build`
- Release build: `xcodebuild -project "PCL.Mac.xcodeproj" -scheme "PCL.Mac" -configuration Release -destination 'platform=macOS' build`
- Focused test run: `xcodebuild test -project "PCL.Mac.xcodeproj" -scheme "PCL.Mac" -testPlan "PCL.Mac" -destination 'platform=macOS' -only-testing:PCL.Mac.Tests/ServiceArchitectureTests`
- CI parity build number comes from git history. Mirror CI with `CURRENT_PROJECT_VERSION=$(git rev-list --count HEAD)` on `xcodebuild` when version-sensitive changes matter.

## Test/runtime quirks
- Do **not** default to `swift test`; tests are wired through the `PCL.Mac` app scheme.
- The shared test plan is `Configs/PCL.Mac.xctestplan` and sets `PCL_MAC_TESTING=1`.
- Tests use the Swift `Testing` framework (`import Testing`, `@Test`, `#expect`), not XCTest-style assertions.

## Repo structure that matters
- `PCL.Mac/`: app target, SwiftUI views, app lifecycle, view models, managers, and macOS-specific services.
- `PCL.Mac.Core/`: shared framework target (`Core.framework`) for models, auth, launch logic, repositories, parsing, and utilities.
- `PCL.Mac.Tests/`: test bundle target. Tests run against the app target via `TEST_HOST`, so app-level changes can affect test execution.
- App entrypoint is `PCL.Mac/App/App.swift` (`@main`), with the main UI rooted through `AppWindow.swift`/`ContentView.swift` and singleton routing/state managers.

## Architecture conventions worth preserving
- Keep UI-facing code in `PCL.Mac/`; move shared or non-UI logic into `PCL.Mac.Core/`.
- This codebase already prefers **manager/service splits**: managers coordinate shared state, services hold heavier launch, filesystem, update, and parsing logic.
- The launch flow is intentionally split. When touching launch behavior, look at `JavaRuntimeSelectionService`, `MinecraftLaunchPreparationService`, `MinecraftLaunchExecutionCoordinator`, and `Task/MinecraftLaunchTask.swift` before adding new logic.
- Auth protocols stay separated in core services (`MicrosoftAuthService` vs `YggdrasilAuthService`).
- Config persistence goes through `LauncherConfig`; when updating shared config, prefer `LauncherConfig.mutate { ... }` over scattered direct mutation patterns.

## Repo-specific coding conventions
- Keep logs and user-facing prompts **Chinese-first**. The common helpers are `log(...)`, `warn(...)`, `err(...)`, and `hint(...)`.
- Preserve the existing `My*` UI component vocabulary (`MyButton`, `MyCard`, `MyListItem`, etc.) instead of introducing parallel naming.

## Packaging / release gotchas
- CI builds on `macos-26` and uses `xcodebuild` directly; PR CI currently validates **build only**, not a separate automated test step.
- `scripts/build-installer.sh` is the packaging path for the visual DMG installer. It performs a Release build, ad-hoc signs the app, generates the DMG background, and lays out Finder icons with AppleScript.
- Before relying on `scripts/build-installer.sh`, check its hardcoded `DERIVED_DATA_DIR` / `APP_PATH` values; the script expects the built app at a specific DerivedData location.

## Review / collaboration notes
- If asked to review a PR, write review comments in **Simplified Chinese**.
- When reviewing, call out misuse or misspellings explicitly; the repo’s copilot instructions ask for that.
