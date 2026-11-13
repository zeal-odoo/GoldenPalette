// 应用入口：持有跨窗口共享的颜色库与 AI 配置，向各界面注入生成配方的能力。
import SwiftUI

/// 连接主窗口、设置窗口和持久化配置的应用根节点。
@main
struct Golden__App: App {
    // 根状态由各窗口通过绑定共享；测试启动时使用隔离的内存数据。
    @State private var library = initialLibrary()
    @State private var configuration = initialConfiguration()
    /// 每次启动重新检查；多个工作窗口共享本次结果。
    @State private var startup = CodexStartupState()

    /// 注册主工作窗口与 macOS 设置窗口。
    var body: some Scene {
        WindowGroup {
            CodexStartupView(
                state: $startup, configuration: configuration,
                check: { configuration in try await Self.checkCodex(configuration: configuration) }
            ) {
                ContentView(library: $library, configuration: configuration, generateBlend: { request, paintSet, configuration in
                    try await Self.generateBlendedRecipe(request: request, paintSet: paintSet, configuration: configuration)
                }) { target, referencePaint, paintSet, configuration in
                    try await Self.generateRecipe(target: target, referencePaint: referencePaint, paintSet: paintSet, configuration: configuration)
                }
            }
        }

        Settings {
            AISettingsView(configuration: configurationBinding)
        }
    }

    /// 配置改变后立即保存；自动化测试只更新内存，避免修改用户偏好。
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

    /// 正常启动验证真实连接；测试宿主和界面测试不触碰实际账户或消耗模型额度。
    private static func checkCodex(configuration: AIConfiguration) async throws -> CodexHealthReport {
        #if DEBUG
        let process = ProcessInfo.processInfo
        let isUITest = process.arguments.contains("--ui-testing")
        let isUnitTest = process.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
        if isUITest || isUnitTest {
            if isUITest {
                let behavior = process.environment["GOLDEN_UI_STARTUP_CHECK"] ?? "success"
                if behavior == "pending" {
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                }
                if behavior == "failure"
                    || (behavior == "recover-after-settings" && configuration.model.modelID == AIModelSelection().modelID) {
                    throw MixingError.cliFailed("Codex 登录已失效或尚未登录。请在终端执行 codex login 后重试。")
                }
            }
            try Task.checkCancellation()
            return CodexHealthReport(
                configuration: configuration, executablePath: "/test-fixtures/codex", checkedAt: Date()
            )
        }
        #endif
        return try await CodexHealthCheckService().check(configuration: configuration)
    }

    /// 生成指定 RGB 的配方；调试测试可注入固定响应，其余情况调用 Codex 服务。
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

    /// 生成实体颜色合成配方；界面测试必须提供固定响应，避免意外联网。
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

    /// 普通启动读取持久化配置，界面测试使用确定的默认配置。
    private static func initialConfiguration() -> AIConfiguration {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            return AIConfiguration()
        }
        #endif
        return AIConfiguration.load()
    }

    /// 普通启动加载并尝试迁移颜色库，界面测试从空库开始。
    private static func initialLibrary() -> RecipeLibrary {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            return RecipeLibrary(previewItems: [])
        }
        #endif
        return RecipeLibrary(legacyPreferencesURL: RecipeLibrary.legacyPreferencesURL)
    }
}
