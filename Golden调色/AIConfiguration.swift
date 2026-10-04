import Foundation

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

    var id: String { rawValue }

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

/// Stored with each recipe so later settings changes cannot relabel its origin.
struct AIModelSelection: Codable, Equatable, Sendable {
    var modelID = "gpt-6.1-sol"
    var reasoningEffort: AIReasoningEffort = .high

    var summary: String {
        "\(modelID) · \(reasoningEffort == .modelDefault ? "模型默认" : reasoningEffort.rawValue)"
    }
}

struct AIConfiguration: Equatable, Sendable {
    var model = AIModelSelection()
    var executablePath = ""

    var isValid: Bool {
        !model.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func validated() throws -> AIConfiguration {
        guard isValid else {
            throw MixingError.invalidConfiguration("请先在系统设置的 AI 配置中填写模型 ID。")
        }
        var configuration = self
        configuration.model.modelID = model.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        configuration.executablePath = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return configuration
    }

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

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(model.modelID, forKey: "CodexModelID")
        defaults.set(model.reasoningEffort.rawValue, forKey: "CodexReasoningEffort")
        defaults.set(executablePath, forKey: "CodexExecutablePath")
    }
}
