// 启动连接检查的用户流程；使用调试专用响应，测试不会访问真实 Codex 账户。
import XCTest
import XCUIAutomation

@MainActor
final class CodexStartupUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { XCUIApplication().terminate() }

    /// 成功后自动进入工作台，并可从状态栏重新检查。
    func testSuccessfulStartupEntersWorkspaceAndCanRecheck() {
        let app = launch(behavior: "success")
        XCTAssertTrue(app.buttons["newRecipeButton"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["codexConnectionStatus"].value as? String, "Codex 已连接")
        app.buttons["retryCodexCheckButton"].click()
        let connected = app.staticTexts.matching(identifier: "codexConnectionStatus")
            .matching(NSPredicate(format: "value == %@", "Codex 已连接")).firstMatch
        XCTAssertTrue(connected.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["newRecipeButton"].exists)
    }

    /// 用户可在检查中进入颜色库；取消后不能显示绿色成功状态。
    func testPendingCheckCanBeCancelledWithoutBlockingLocalLibrary() {
        let app = launch(behavior: "pending")
        XCTAssertTrue(app.staticTexts["codexStartupProgress"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["newRecipeButton"].exists)
        app.buttons["continueWithoutCodexButton"].click()
        XCTAssertTrue(app.buttons["newRecipeButton"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["codexConnectionStatus"].value as? String, "Codex 尚未验证")
        app.buttons["newRecipeButton"].click()
        XCTAssertTrue(app.textFields["recipeNameField"].waitForExistence(timeout: 5))
    }

    /// 失败时显示处理建议；修改配置自动重查，通过后进入工作台。
    func testFailedStartupRecoversAfterSettingsChange() {
        let app = launch(behavior: "recover-after-settings")
        XCTAssertTrue(app.staticTexts["codexStartupFailure"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "codex login")).firstMatch.exists)
        XCTAssertFalse(app.buttons["newRecipeButton"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Codex 启动检查失败与恢复入口"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["retryCodexCheckButton"].click()
        XCTAssertTrue(app.staticTexts["codexStartupFailure"].waitForExistence(timeout: 8))
        app.buttons["aiSettingsButton"].firstMatch.click()
        let model = app.textFields["aiModelField"]
        XCTAssertTrue(model.waitForExistence(timeout: 5))
        model.click()
        model.typeKey("a", modifierFlags: .command)
        model.typeText("fixture-ready-model")
        XCTAssertTrue(app.buttons["newRecipeButton"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["codexConnectionStatus"].value as? String, "Codex 已连接")
    }

    /// 用启动参数注入检查结果，并隔离实际颜色库和 AI 偏好。
    private func launch(behavior: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["GOLDEN_UI_STARTUP_CHECK"] = behavior
        app.launch()
        app.activate()
        return app
    }
}
