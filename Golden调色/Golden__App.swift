import SwiftUI

@main
struct Golden__App: App {
    @State private var library = initialLibrary()
    @State private var configuration = initialConfiguration()

    var body: some Scene {
        WindowGroup {
            ContentView(library: $library, configuration: configuration, generateBlend: { request, configuration in
                try await Self.generateBlendedRecipe(request: request, configuration: configuration)
            }) { target, configuration in
                try await Self.generateRecipe(target: target, configuration: configuration)
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
        configuration: AIConfiguration
    ) async throws -> MixingPalette {
        let configuration = try configuration.validated()
        #if DEBUG
        let process = ProcessInfo.processInfo
        if process.arguments.contains("--ui-testing"),
           let fixture = process.environment["GOLDEN_UI_MIXING_RESPONSE"] {
            // UI automation injects a response; normal app launches always call Codex.
            try Task.checkCancellation()
            return try MixingPalette.decode(Data(fixture.utf8), for: target, model: configuration.model)
        }
        #endif
        return try await CodexMixingService().generate(for: target, configuration: configuration)
    }

    private static func generateBlendedRecipe(
        request: ColorBlendRequest,
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
            return try request.decodePalette(Data(fixture.utf8), model: configuration.model)
        }
        #endif
        return try await CodexMixingService().generate(from: request, configuration: configuration)
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
