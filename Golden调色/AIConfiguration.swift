// AI 配置与生成来源：应用保存当前偏好，每份结果另存生成时的模型快照。
import Foundation

/// 可选择的推理强度；是否被接受由实际模型决定。
enum AIReasoningEffort: String, Codable, CaseIterable, Identifiable, Sendable {
    case modelDefault
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh
    case max
    case ultra

    /// 原始值用于选择器身份和持久化。
    var id: String { rawValue }

    /// 高推理强度可能较久没有输出，因此按档位给予不同的应用等待上限。
    // Higher efforts can spend several minutes reasoning before producing any output.
    var generationTimeout: TimeInterval {
        switch self {
        case .max, .ultra: return 20 * 60
        case .xhigh: return 10 * 60
        default: return 4 * 60
        }
    }

    /// 与实际超时规则保持一致的界面等待提示。
    var generationWaitDescription: String {
        "当前推理强度最多等待 \(Int(generationTimeout / 60)) 分钟，可随时取消。"
    }

    /// 显示中文解释并保留 CLI 原始参数值。
    var title: String {
        switch self {
        case .modelDefault: return "模型默认"
        case .none: return "无 · none"
        case .minimal: return "最低 · minimal"
        case .low: return "低 · low"
        case .medium: return "中 · medium"
        case .high: return "高 · high"
        case .xhigh: return "更高 · xhigh"
        case .max: return "最高 · max"
        case .ultra: return "极高 · ultra"
        }
    }
}

/// 随配方保存的模型与推理强度，后续改设置不会改写历史结果来源。
/// Stored with each recipe so later settings changes cannot relabel its origin.
struct AIModelSelection: Codable, Equatable, Sendable {
    var modelID = "gpt-6.1-sol"
    var reasoningEffort: AIReasoningEffort = .high

    /// 用于配方、报告和错误信息的生成模型摘要。
    var summary: String {
        "\(modelID) · \(reasoningEffort == .modelDefault ? "模型默认" : reasoningEffort.rawValue)"
    }
}

/// 当前应用配置；认证凭据由 Codex CLI 自行管理。
struct AIConfiguration: Equatable, Sendable {
    var model = AIModelSelection()
    /// 空字符串表示自动查找，否则使用用户指定的 CLI 文件路径。
    var executablePath = ""

    /// 仅检查本地必填字段，不据此判断模型权限或登录是否有效。
    var isValid: Bool {
        !model.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 发送请求前规范化输入，避免空模型名和路径首尾空白。
    func validated() throws -> AIConfiguration {
        guard isValid else {
            throw MixingError.invalidConfiguration("请先在系统设置的 AI 配置中填写模型 ID。")
        }
        var configuration = self
        configuration.model.modelID = model.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        configuration.executablePath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return configuration
    }

    /// 从偏好读取配置，无法识别的旧强度值回退为模型默认。
    static func load(from defaults: UserDefaults = .standard) -> AIConfiguration {
        var configuration = AIConfiguration()
        configuration.model.modelID = defaults.string(forKey: "CodexModelID") ?? configuration.model.modelID
        if let effort = defaults.string(forKey: "CodexReasoningEffort") {
            configuration.model.reasoningEffort = AIReasoningEffort(rawValue: effort) ?? .modelDefault
        }
        // Reuse the existing key to retain the CLI path configured in earlier releases.
        configuration.executablePath = defaults.string(forKey: "CodexExecutablePath") ?? ""
        return configuration
    }

    /// 保存非敏感的模型、强度和可执行路径，沿用既有偏好键。
    func save(to defaults: UserDefaults = .standard) {
        defaults.set(model.modelID, forKey: "CodexModelID")
        defaults.set(model.reasoningEffort.rawValue, forKey: "CodexReasoningEffort")
        defaults.set(executablePath, forKey: "CodexExecutablePath")
    }
}
