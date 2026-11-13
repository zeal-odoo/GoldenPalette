//
//  Golden__UITestsLaunchTests.swift
//  Golden调色UITests
//
//  Created by Ming Liu on 2025/2/6.
//

// 启动烟雾测试：按测试计划的应用界面配置启动，并保留启动画面供诊断。
import XCTest

/// 验证应用能够启动到可截图状态，不承担具体业务流程测试。
final class Golden__UITestsLaunchTests: XCTestCase {

    /// 对测试计划支持的各目标界面配置重复运行启动检查。
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    /// 启动流程失败后立即停止，避免继续采集误导性的结果。
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 启动应用并将当前窗口画面作为长期保留的测试附件。
    func testLaunch() throws {
        let app = XCUIApplication()
        // 启动烟雾测试复用检查替身，不在每次采集画面时发起真实模型请求。
        app.launchArguments = ["--ui-testing"]
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
