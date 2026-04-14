# PCL.Mac Development Guide

This file defines the working conventions for this repository. Future development should follow these rules unless a specific file or subsystem already has a stronger local convention.

## 1. General Principles

- Prefer small, behavior-preserving refactors over large rewrites.
- Match existing code before introducing a new pattern.
- Keep UI code in `PCL.Mac/`, shared models/utilities in `PCL.Mac.Core/`, and tests in `PCL.Mac.Tests/`.
- When a file starts to mix orchestration, IO, parsing, and presentation, extract a focused service instead of growing the file further.
- Avoid speculative abstractions. Extract services only when a responsibility is clearly repeated or overly large.

## 2. Project Structure Expectations

- `PCL.Mac.Core/`
  - Pure/shared models, launch logic, repositories, utilities, protocol/data parsing.
  - Keep business logic here when it does not require SwiftUI/AppKit UI state.
- `PCL.Mac/`
  - SwiftUI views, view models, managers, installer packaging helpers, app lifecycle.
- `PCL.Mac/Services/`
  - Focused service units for heavy logic already extracted from views/managers/tasks.
  - Examples in the current codebase: crash report generation, launch preparation, runtime selection, skin loading, Java catalog aggregation.
- `PCL.Mac.Tests/`
  - Use for deterministic logic tests and targeted integration-style tests that match existing project practice.

## 3. Naming Rules

- Types: `PascalCase`
  - Examples: `InstanceManager`, `SkinService`, `MinecraftLaunchPreparationService`
- Methods/properties/local variables: `camelCase`
  - Examples: `switchInstance`, `currentRepository`, `loadSkinData`
- File names should match the primary type or responsibility.
- Prefer clear domain names over generic names.
  - Good: `JavaRuntimeSelectionService`
  - Bad: `Helper`, `Manager2`, `UtilMisc`
- Enums used as namespaces are acceptable when the type is stateless.

## 4. Architectural Conventions

### 4.1 Managers

- Managers may remain singleton-based where the project already depends on shared global state.
- Managers should primarily coordinate state and delegate heavy work to services.
- Do not keep growing managers with parsing, export, or filesystem-heavy logic.
- If a manager grows a large independent responsibility, extract it into a service.

### 4.2 Services

- Services should own focused responsibilities:
  - network aggregation
  - file enumeration
  - crash analysis/export
  - runtime selection
  - resource loading/caching
- Prefer stateless `enum` services with static methods when no mutable instance state is needed.
- Prefer small final classes only when stateful coordination is required.

### 4.3 ViewModels

- ViewModels should expose UI state and user actions, not large blocks of filesystem/network logic.
- If a ViewModel starts caching data, performing downloads, or parsing external payloads, consider extracting a service.
- Keep config synchronization explicit via small helper methods instead of repeated `didSet` side effects.

### 4.4 Views

- SwiftUI views should focus on composition and event wiring.
- Avoid embedding large IO or parsing blocks directly inside views.
- Repeated file/dialog/message-box workflows should move into helpers/services/view models.

## 5. Logging and User Feedback

- Use project logging helpers consistently:
  - `log(...)` for normal informational flow
  - `warn(...)` for recoverable issues / degraded behavior
  - `err(...)` for failures or unexpected states
  - `hint(...)` for user-facing transient hints
- Keep logs in Chinese unless there is a strong reason to preserve an external term.
- When logging sensitive launch data, redact:
  - access tokens
  - huge classpaths
  - credentials
- User-visible prompts should be concise, actionable, and Chinese-first.

## 6. Error Handling

- Prefer explicit recoverable errors using `throws`.
- Use `SimpleError` for domain/user-facing failures when a lightweight error is sufficient.
- Do not swallow errors silently.
- When recovery is possible, log the error and continue with a fallback.
- When an error message comes from external systems and is too raw, wrap it into a user-readable Chinese message.

## 7. Async / Concurrency Rules

- Prefer `async/await` over callback-style code.
- Use `Task {}` or service-level async APIs for background work.
- Ensure UI updates happen on the main actor / main queue.
- Avoid doing recursive directory scans or expensive decoding synchronously on the main path when results can be cached or backfilled asynchronously.
- For repeated async work keyed by the same resource, use task deduplication patterns already used in the repo:
  - actor-held task map
  - cache first, async fill later

## 8. Filesystem and Resource Access

- Centralize repeated file enumeration into services instead of duplicating `FileManager.default.contentsOfDirectory(...)` in views.
- Use cached results for expensive folder-size scans or image/resource loads.
- Prefer standardized URLs when comparing filesystem locations.
- When editing repository/instance paths, ensure derived paths are recomputed dynamically rather than cached lazily.

## 9. Launch Pipeline Rules

- Keep launch flow split by responsibility:
  - runtime selection
  - launch preparation/precheck/resource completion
  - process execution and crash coordination
- Do not re-introduce large static utility blocks into `MinecraftLaunchTask` or `MinecraftLaunchManager`.
- New launch-time policies should go into the extracted services whenever possible.

## 10. Account and Auth Rules

- Account model types should remain responsible for account-specific refresh/configuration behavior.
- Different auth protocols belong in different services.
  - Microsoft auth stays separate from Yggdrasil/authlib-injector.
- Password input must use secure input UI.
- External auth endpoints should prefer HTTPS and validate downloaded support artifacts where feasible.

## 11. UI and UX Conventions

- Preserve the project’s existing `My*` component vocabulary (`MyButton`, `MyCard`, `MyListItem`, etc.).
- Prefer readable, practical Chinese copy over placeholder/funny text.
- For installer/packaging UX, ensure the visual background does not fight with the actual Finder icon positions.
- If a background image is used in DMG packaging, keep it aligned to the real Finder window size and actual icon positions.

## 12. Testing Conventions

- Use the `Testing` framework style already present in the repository.
- Test files usually group related behavior in a single `struct` per domain.
- Assertion style:
  - `#expect(...)`
  - `await #expect(throws: ...) { ... }`
- Add tests for:
  - service extraction behavior
  - serialization/deserialization compatibility
  - launch argument construction
  - version/range heuristics
  - pure logic and parser behavior
- Avoid adding fragile tests for UI layout details unless necessary.
- Network-heavy tests already exist in the project; do not expand them unless the benefit clearly outweighs instability.

## 13. Refactoring Rules

- Prefer extracting helpers/services without changing behavior first.
- Keep each extraction narrow and verifiable.
- After refactors, run at least:
  - project build
  - relevant tests, or full test suite when touching core flows
- When introducing new services, ensure old call sites are actually switched over; avoid leaving dead duplicate logic behind unless intentionally staging a later cleanup.

## 14. Configuration and Persistence

- Centralize shared config writes through helper/update entry points when possible.
- Avoid scattered direct mutation of config singletons from many unrelated call sites.
- When possible, prefer an explicit sync method or mutation closure over repeated one-off assignments.

## 15. Packaging Rules

- Installer artifacts should be reproducible from repository scripts/steps.
- Distinguish between:
  - source/resource changes worth versioning
  - temporary packaging directories that should be cleaned
- If binary artifacts are committed, ensure they are final deliverables, not temporary staging files.

## 16. What To Do Before Finishing a Change

- Check the touched files still follow local naming/style.
- Verify service extraction did not leave duplicate stale code paths if avoidable.
- Run build.
- Run relevant tests (or full suite for core changes).
- Keep the working tree clean unless intentionally leaving uncommitted work.

## 17. Default Rule For Future Development

When adding new code to this repository:

1. follow existing structure first,
2. prefer focused services over expanding god objects,
3. keep logs and prompts Chinese-first,
4. keep expensive IO off the hot UI path,
5. verify with build/tests before considering the work done.
