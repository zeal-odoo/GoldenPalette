---
name: golden
description: Develop and iterate a Swift/SwiftUI app for recording color-mixing workflows, including RGB values, naming, process notes, and persistence. Use when requests involve building or improving this repository's color-tracking features, modernizing to the latest Swift APIs, refactoring SwiftUI state/view structure, or adding related tests.
---

# Golden

## Scope
Implement features for a color-mixing recorder app in SwiftUI. Prefer incremental, working changes that keep current behavior stable while improving structure, usability, and data safety.

## Trigger Examples
- "Add a workflow to record each color-mixing step and method notes."
- "Refactor `ContentView.swift` into smaller SwiftUI components."
- "Migrate this project to newer SwiftUI APIs and keep compatibility."
- "Add tests for persistence and editing behavior."

## Workflow
1. Inspect current state
Read `Golden调色/Golden调色/ContentView.swift` and test targets first. Preserve existing data model behavior unless change is requested.
2. Prefer latest Apple APIs
Use current Swift and SwiftUI patterns. When uncertain, verify with Apple docs via `DocumentationSearch` before implementing.
3. Implement minimal focused changes
Keep edits scoped to requested behavior. Use `@State private var` for local UI state and extract reusable views/types when complexity grows.
4. Preserve persistence and editing flows
Keep RGB value handling, naming, and method-note persistence reliable. Avoid force unwraps and unsafe assumptions.
5. Validate
Run fast diagnostics on touched files, then build/test the project when practical.
6. Run Git checks after every change
Run `git status --short` and review `git diff` for touched files after each edit batch. Keep diffs scoped to the requested task.

## Implementation Rules
- Use 4-space indentation and Swift naming conventions (`PascalCase` types, `camelCase` members).
- Prefer async/await APIs over Combine for new asynchronous work.
- Add concise comments only for non-obvious logic.
- Add or update XCTest/XCUITest coverage for changed behavior.

## Done Criteria
- Requested feature works in UI and does not regress existing color entry/editing flows.
- Modified files compile cleanly.
- Relevant tests are added/updated or explicit test gaps are reported.
- Git working tree has been reviewed with `git status --short` and `git diff`.
