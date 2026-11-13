// 启动检查回归：真实子进程边界使用临时假 CLI，避免依赖网络或用户账户。
import Foundation
import Darwin
import Testing
@testable import Golden调色

struct CodexHealthCheckTests {
    /// 验证真实参数传递、随机校验码响应及请求临时文件清理。
    @Test
    func testHealthCheckUsesConfiguredCLIModelAndEffort() async throws {
        let stub = try Stub(mode: "success")
        defer { stub.remove() }
        let report = try await CodexHealthCheckService().check(configuration: stub.configuration)
        #expect(report.configuration == stub.configuration)
        #expect(report.executablePath == stub.executable.path)
        #expect(abs(report.checkedAt.timeIntervalSinceNow) < 5)
        let arguments = try String(contentsOf: stub.directory.appendingPathComponent("arguments.txt"), encoding: .utf8)
        #expect(arguments.contains("--model\nconnection-check-model\n"))
        #expect(arguments.contains("model_reasoning_effort=\"max\""))
        #expect(arguments.contains("web_search=\"disabled\""))
        #expect(arguments.contains("--ignore-user-config"))
        #expect(arguments.contains("--sandbox\nread-only\n"))
        let values = arguments.split(separator: "\n").map(String.init)
        let directoryIndex = try #require(values.firstIndex(of: "--cd"))
        #expect(!FileManager.default.fileExists(atPath: values[directoryIndex + 1]))
        #expect(stub.configuration.model.reasoningEffort == .max)
        #expect(AIReasoningEffort.max.generationTimeout == 1_200)
    }

    /// 程序退出成功也不代表模型有效响应；旧校验码和不完整 JSON 都必须拒绝。
    @Test(arguments: ["wrong-nonce", "malformed"])
    func testHealthCheckRejectsInvalidHandshake(_ mode: String) async throws {
        let stub = try Stub(mode: mode)
        defer { stub.remove() }
        do {
            _ = try await CodexHealthCheckService().check(configuration: stub.configuration)
            Issue.record("无效响应被当作连接成功")
        } catch CodexHealthCheckError.invalidReply { }
    }

    /// 认证失败沿用正式服务的中文处理提示。
    @Test
    func testHealthCheckSurfacesAuthenticationFailure() async throws {
        let stub = try Stub(mode: "unauthorized")
        defer { stub.remove() }
        do {
            _ = try await CodexHealthCheckService().check(configuration: stub.configuration)
            Issue.record("认证失败被当作成功")
        } catch {
            #expect(error.localizedDescription.contains("codex login"))
        }
    }

    /// 找不到指定程序时立即失败，不回退到另一份已安装 CLI。
    @Test
    func testMissingCLIIsReportedBeforeConnecting() async throws {
        let configuration = AIConfiguration(executablePath: "/missing-\(UUID().uuidString)/codex")
        do {
            _ = try await CodexHealthCheckService().check(configuration: configuration)
            Issue.record("不存在的 CLI 被接受")
        } catch MixingError.cliNotFound { }
    }

    /// 空模型配置不能启动子进程。
    @Test
    func testInvalidConfigurationDoesNotLaunchCLI() async throws {
        let stub = try Stub(mode: "success")
        defer { stub.remove() }
        var configuration = stub.configuration
        configuration.model.modelID = " "
        do {
            _ = try await CodexHealthCheckService().check(configuration: configuration)
            Issue.record("空模型配置被接受")
        } catch MixingError.invalidConfiguration { }
        #expect(!FileManager.default.fileExists(atPath: stub.directory.appendingPathComponent("arguments.txt").path))
    }

    /// 启动探测采用独立短时限，超时后必须回收它拥有的进程。
    @Test
    func testHealthCheckTimeoutStopsItsProcess() async throws {
        let stub = try Stub(mode: "stall")
        defer { stub.remove() }
        do {
            _ = try await CodexHealthCheckService(timeout: 2).check(configuration: stub.configuration)
            Issue.record("未触发连接检查超时")
        } catch CodexHealthCheckError.timedOut { }
        try stub.expectProcessExited()
        #expect(CodexHealthCheckService.defaultTimeout == 90)
    }

    /// 用户跳过检查时取消任务，不能留下继续消耗资源的 CLI 子进程。
    @Test
    func testCancellingHealthCheckStopsItsProcess() async throws {
        let stub = try Stub(mode: "stall")
        defer { stub.remove() }
        let task = Task { try await CodexHealthCheckService().check(configuration: stub.configuration) }
        defer { task.cancel() }
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: stub.pidURL.path), Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(FileManager.default.fileExists(atPath: stub.pidURL.path))
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("取消后的检查返回了成功")
        } catch is CancellationError { }
        try stub.expectProcessExited()
    }

    /// 同次启动多个窗口共享一次验证，新一次启动仍需重新验证。
    @Test
    func testStartupChecksOncePerConfigurationAndLaunch() throws {
        var state = CodexStartupState()
        let configuration = AIConfiguration()
        #expect(!state.workspaceAvailable)
        let idRequest = state.begin(configuration: configuration)
        let id = try #require(idRequest)
        let additionalRequest1 = state.begin(configuration: configuration)
        #expect(additionalRequest1 == nil)
        state.succeed(report(configuration), for: id)
        #expect(state.workspaceAvailable)
        let additionalRequest2 = state.begin(configuration: configuration)
        #expect(additionalRequest2 == nil)
        var nextLaunch = CodexStartupState()
        let additionalRequest3 = nextLaunch.begin(configuration: configuration)
        #expect(additionalRequest3 != nil)
        #expect(!nextLaunch.workspaceAvailable)
    }

    /// 修改配置后只有新请求可以完成验证，旧配置响应不得解锁工作台。
    @Test
    func testChangedConfigurationRejectsStaleSuccessAndFailure() throws {
        var state = CodexStartupState()
        let first = AIConfiguration()
        var second = first
        second.model.modelID = "another-model"
        let oldIDRequest = state.begin(configuration: first)
        let oldID = try #require(oldIDRequest)
        let newIDRequest = state.begin(configuration: second)
        let newID = try #require(newIDRequest)
        state.succeed(report(first), for: oldID)
        state.fail("stale failure", for: oldID)
        #expect(state.phase == .checking)
        #expect(!state.workspaceAvailable)
        state.succeed(report(second), for: newID)
        #expect(state.phase == .ready(report(second)))
    }

    /// 跳过检查只能进入未验证状态，重试及失败均不销毁已打开的工作台。
    @Test
    func testSkippingCheckDoesNotTurnLateResponseIntoSuccess() throws {
        var state = CodexStartupState()
        let configuration = AIConfiguration()
        let oldIDRequest = state.begin(configuration: configuration)
        let oldID = try #require(oldIDRequest)
        state.continueInWorkspace(configuration: configuration)
        state.succeed(report(configuration), for: oldID)
        state.cancel(oldID)
        #expect(state.phase == .skipped)
        #expect(state.workspaceAvailable)
        let additionalRequest4 = state.begin(configuration: configuration)
        #expect(additionalRequest4 == nil)
        state.retry()
        let newIDRequest = state.begin(configuration: configuration)
        let newID = try #require(newIDRequest)
        state.fail("offline", for: newID)
        #expect(state.phase == .failed("offline"))
        #expect(state.workspaceAvailable)
        state.continueInWorkspace(configuration: configuration)
        #expect(state.phase == .failed("offline"))
    }

    /// 失败后重试可以恢复；取消拥有者后其他窗口可以接续检查。
    @Test
    func testFailedAndCancelledChecksCanRetry() throws {
        var state = CodexStartupState()
        let configuration = AIConfiguration()
        let failedIDRequest = state.begin(configuration: configuration)
        let failedID = try #require(failedIDRequest)
        state.fail("offline", for: failedID)
        #expect(!state.workspaceAvailable)
        state.retry()
        let cancelledIDRequest = state.begin(configuration: configuration)
        let cancelledID = try #require(cancelledIDRequest)
        state.cancel(cancelledID)
        let currentIDRequest = state.begin(configuration: configuration)
        let currentID = try #require(currentIDRequest)
        state.fail("late failure", for: cancelledID)
        state.succeed(report(configuration), for: currentID)
        #expect(state.phase == .ready(report(configuration)))
        #expect(state.workspaceAvailable)
    }

    /// 固定时间保证状态比较只关注请求归属。
    private func report(_ configuration: AIConfiguration) -> CodexHealthReport {
        CodexHealthReport(configuration: configuration, executablePath: "/fixture/codex",
                          checkedAt: Date(timeIntervalSince1970: 0))
    }

    /// 每例使用独立目录和程序，录制参数并可模拟认证、无效响应及进程挂起。
    private struct Stub {
        let directory: URL
        let executable: URL
        var pidURL: URL { directory.appendingPathComponent("pid.txt") }
        var configuration: AIConfiguration {
            AIConfiguration(
                model: AIModelSelection(modelID: "connection-check-model", reasoningEffort: .max),
                executablePath: executable.path
            )
        }

        init(mode: String) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("Golden CLI Check-\(UUID().uuidString)")
            executable = directory.appendingPathComponent("fake-codex")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(mode.utf8).write(to: directory.appendingPathComponent("mode.txt"))
            let script = #"""
            #!/bin/sh
            set -eu
            fixture_dir=${0%/*}
            echo $$ > "$fixture_dir/pid.txt"
            printf '%s\n' "$@" > "$fixture_dir/arguments.txt"
            output_path=''
            while [ "$#" -gt 0 ]; do
                case "$1" in
                    --output-last-message) output_path=$2; shift ;;
                esac
                shift
            done
            cat > "$fixture_dir/prompt.txt"
            case "$(cat "$fixture_dir/mode.txt")" in
                stall)
                    exec /bin/sleep 30 ;;
                unauthorized)
                    echo '401 Unauthorized' >&2
                    exit 1 ;;
                wrong-nonce)
                    printf '{"status":"ok","nonce":"stale"}' > "$output_path" ;;
                malformed)
                    printf '{"status":"ok"}' > "$output_path" ;;
                success)
                    nonce=$(/usr/bin/sed -n 's/.*"nonce":"\([^"]*\)".*/\1/p' "$fixture_dir/prompt.txt")
                    printf '{"status":"ok","nonce":"%s"}\n' "$nonce" > "$output_path" ;;
            esac
            """#
            try Data(script.utf8).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }

        /// 只检查本用例记录的子进程，确认取消和超时已完成回收。
        func expectProcessExited() throws {
            let text = try String(contentsOf: pidURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            let pid = try #require(Int32(text))
            #expect(kill(pid, 0) == -1)
            #expect(errno == ESRCH)
        }

        func remove() { try? FileManager.default.removeItem(at: directory) }
    }
}
