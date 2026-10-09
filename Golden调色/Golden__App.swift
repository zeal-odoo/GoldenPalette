import SwiftUI

@main
struct Golden__App: App {
    @State private var library = initialLibrary()
    @State private var configuration = initialConfiguration()

    var body: some Scene {
        WindowGroup {
            ContentView(library: $library, configuration: configuration, generateBlend: { request, paintSet, configuration in
                try await Self.generateBlendedRecipe(request: request, paintSet: paintSet, configuration: configuration)
            }) { target, referencePaint, paintSet, configuration in
                try await Self.generateRecipe(target: target, referencePaint: referencePaint, paintSet: paintSet, configuration: configuration)
            }
        }

        Settings {
            AISettingsView(configuration: configurationBinding)
        }
    }

    private var configurationBinding: Binding<AIConfiguration> {
        Binding(
            get: { configuration },
            set: { value in
                configuration = value
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return }
                #endif
                value.save()
            }
        )
    }

    private static func generateRecipe(
        target: MixingTarget,
        referencePaint: PaintReference?,
        paintSet: MixingPaintSet,
        configuration: AIConfiguration
    ) async throws -> MixingPalette {
        let configuration = try configuration.validated()
        #if DEBUG
        let process = ProcessInfo.processInfo
        if process.arguments.contains("--ui-testing"),
           let fixture = process.environment["GOLDEN_UI_MIXING_RESPONSE"] {
            // UI automation injects a response; normal app launches always call Codex.
            try Task.checkCancellation()
            return try MixingPalette.decode(Data(fixture.utf8), for: target, model: configuration.model, paintSet: paintSet, referencePaint: referencePaint)
        }
        #endif
        return try await CodexMixingService().generate(for: target, referencePaint: referencePaint, paintSet: paintSet, configuration: configuration)
    }

    private static func generateBlendedRecipe(
        request: ColorBlendRequest,
        paintSet: MixingPaintSet,
        configuration: AIConfiguration
    ) async throws -> MixingPalette {
        let configuration = try configuration.validated()
        #if DEBUG
        let process = ProcessInfo.processInfo
        if process.arguments.contains("--ui-testing") {
            guard let fixture = process.environment["GOLDEN_UI_BLEND_RESPONSE"] else {
                throw MixingError.invalidRecipe("界面验证未提供颜色合成响应。")
            }
            try Task.checkCancellation()
            return try request.decodePalette(Data(fixture.utf8), model: configuration.model, paintSet: paintSet)
        }
        #endif
        return try await CodexMixingService().generate(from: request, paintSet: paintSet, configuration: configuration)
    }

    private static func initialConfiguration() -> AIConfiguration {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            return AIConfiguration()
        }
        #endif
        return AIConfiguration.load()
    }

    private static func initialLibrary() -> RecipeLibrary {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            return RecipeLibrary(previewItems: [])
        }
        #endif
        return RecipeLibrary(legacyPreferencesURL: RecipeLibrary.legacyPreferencesURL)
    }
}
