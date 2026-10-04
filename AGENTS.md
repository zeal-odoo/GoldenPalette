# Repository Guidelines

## Project Structure & Module Organization

This is a small SwiftUI Xcode project for the `Golden调色` macOS app.

- `Golden调色/Golden调色/Golden__App.swift`: app entry point.
- `Golden调色/Golden调色/ContentView.swift`: main UI, data models, color editing, and persistence logic.
- `Golden调色/Golden调色/Assets.xcassets`: app asset catalog.
- `Golden调色/Golden调色/Preview Content/`: SwiftUI preview assets.
- `Golden调色/Golden调色Tests/`: unit tests.
- `Golden调色/Golden调色UITests/`: UI and launch tests.
- `Golden调色.xcodeproj`: Xcode project file.

Keep feature changes close to the relevant SwiftUI view or model. Avoid broad refactors unless they are required for the requested change.

## Build, Test, and Development Commands

Open and run locally with Xcode:

```sh
open Golden调色.xcodeproj
```

Build from the command line:

```sh
xcodebuild -project Golden调色.xcodeproj -scheme Golden调色 build
```

Run all tests:

```sh
xcodebuild -project Golden调色.xcodeproj -scheme Golden调色 test
```

Use Xcode for interactive SwiftUI previews and simulator/device runs. If command-line builds fail because the destination is ambiguous, add an explicit `-destination` matching your local macOS or simulator environment.

## Coding Style & Naming Conventions

Use Swift and SwiftUI conventions already present in the project:

- 4-space indentation.
- `PascalCase` for types, such as `ColorInfo`.
- `camelCase` for properties and functions, such as `selectedItemID`.
- Prefer `let` for constants and `@State private var` for SwiftUI state.
- Keep imports simple and explicit, usually `import SwiftUI` or `import XCTest`.
- Avoid force unwrapping. Use `guard`, optional binding, and strong Swift types.

No formatter or linter is currently configured. Match the surrounding file style.

## Testing Guidelines

Tests currently use `XCTest`. Unit test files live in `Golden调色Tests`, and UI tests live in `Golden调色UITests`.

Name tests with the `test...` prefix, for example `testColorInfoEncodingPreservesValues`. Add focused tests for persistence, model encoding, and user workflows when changing behavior. UI changes should include either UI test coverage or a clear manual verification note.

## Commit & Pull Request Guidelines

Recent history uses short Chinese commit messages with a type prefix, for example:

```text
功能：采用玻璃风格分栏界面并新增 golden 技能
```

Prefer concise messages in the same style, such as `修复：保存颜色名称时保留调色方法`.

Pull requests should include a brief summary, testing performed, screenshots for UI changes, and linked issues when applicable. Call out any SDK or macOS version requirements, especially when using newer SwiftUI APIs such as glass effects.

## Versioning & Release Iterations

The user requires a version update for every app iteration. Treat this as a persistent project requirement.

- Before delivering each iteration that changes app code, behavior, or resources, increment both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. Keep Debug and Release values consistent.
- Read the current values from Xcode before changing them. Unless the user specifies a version, increment the patch version and the integer build number, for example `1.0` (build `1`) → `1.0.1` (build `2`).
- Bump once per delivered iteration, not once per intermediate build or test run. Questions, diagnostics without app changes, and updates to project instructions alone do not create a new app release.
- When packaging a DMG, use the new app version in its filename, checksum filename, and installation notes. Verify the packaged app's version and build number, and preserve previously delivered DMGs.
- Report the new version and build number in the delivery message.

## Security & Configuration Tips

Do not commit user-specific Xcode settings, derived data, or local secrets. The app currently stores color data in `UserDefaults`; avoid placing sensitive user data there without a dedicated privacy review.
