// 启动连接检查：使用应用真实的 CLI 参数和模型发起一次最小请求。
import Foundation

/// 可注入的检查接口，便于界面预览与自动化测试隔离真实账户。
typealias CodexHealthChecker = @Sendable (AIConfiguration) async throws -> CodexHealthReport

/// 只记录本次验证的配置、程序路径和时间，不持久化登录凭据。
struct CodexHealthReport: Equatable, Sendable {
    let configuration: AIConfiguration
    let executablePath: String
    let checkedAt: Date
}

/// 检查成功必须收到本次随机校验码，不能只根据程序存在或退出码判断。
struct CodexHealthCheckService: Sendable {
    /// 连接探测采用独立时限，不降低用户选择的推理强度或改变调色等待时间。
    static let defaultTimeout: TimeInterval = 90
    var timeout: TimeInterval = defaultTimeout

    /// 复用正式请求的可执行路径、账户、权限、模型参数及进程回收机制。
    func check(configuration: AIConfiguration) async throws -> CodexHealthReport {
        try Task.checkCancellation()
        let configuration = try configuration.validated()
        guard let executable = CodexMixingService.executableURL(customPath: configuration.executablePath) else {
            throw MixingError.cliNotFound
        }
        let nonce = UUID().uuidString
        let schema = try JSONSerialization.data(withJSONObject: [
            "type": "object",
            "properties": [
                "status": ["type": "string", "enum": ["ok"]],
                "nonce": ["type": "string", "enum": [nonce]]
            ],
            "required": ["status", "nonce"],
            "additionalProperties": false
        ], options: [.sortedKeys])
        let prompt = """
        Connection check. Return exactly the following JSON. Do not use tools or read files.
        {"status":"ok","nonce":"\(nonce)"}
        """
        let data: Data
        do {
            data = try await CodexMixingService().request(
                prompt: prompt, schema: schema, configuration: configuration, timeout: timeout
            )
        } catch MixingError.timedOut {
            throw CodexHealthCheckError.timedOut
        }
        try Task.checkCancellation()
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              reply.status == "ok", reply.nonce == nonce else {
            throw CodexHealthCheckError.invalidReply
        }
        return CodexHealthReport(
            configuration: configuration, executablePath: executable.path, checkedAt: Date()
        )
    }

    /// 仅接受连接探测所需的最小响应。
    private struct Reply: Decodable {
        let status: String
        let nonce: String
    }
}

/// 启动检查使用独立提示，避免把连接失败描述为调色失败。
enum CodexHealthCheckError: LocalizedError {
    case timedOut
    case invalidReply

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "连接检查未在限定时间内收到响应，已停止本次检查。请检查网络和 Codex 账户后重试，也可以先使用本地颜色库。"
        case .invalidReply:
            return "Codex 返回的连接检查结果无效。请确认 CLI 路径、模型配置及版本后重试。"
        }
    }
}
