import Foundation

typealias MixingGenerator = @Sendable (MixingTarget, AIConfiguration) async throws -> MixingPalette

struct MixingTarget: Codable, Equatable, Sendable {
    let red: Int
    let green: Int
    let blue: Int

    init(red: Double, green: Double, blue: Double) {
        self.red = Int(ColorInfo.clampedRGB(red).rounded())
        self.green = Int(ColorInfo.clampedRGB(green).rounded())
        self.blue = Int(ColorInfo.clampedRGB(blue).rounded())
    }

    init?(redText: String, greenText: String, blueText: String) {
        let channels = [redText, greenText, blueText].compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard channels.count == 3, channels.allSatisfy({ (0...255).contains($0) }) else { return nil }
        self.init(red: Double(channels[0]), green: Double(channels[1]), blue: Double(channels[2]))
    }

    var description: String { "RGB \(red), \(green), \(blue)" }
    var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }

    /// Compare sRGB reference swatches in linear light, not by averaging encoded RGB.
    /// https://www.w3.org/WAI/GL/wiki/Relative_luminance
    var relativeLuminance: Double {
        func linear(_ channel: Int) -> Double {
            let value = Double(channel) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    var isBlack: Bool { red == 0 && green == 0 && blue == 0 }
    var isWhite: Bool { red == 255 && green == 255 && blue == 255 }

    static let initial = MixingTarget(red: 128, green: 160, blue: 128)
}

enum MixingRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case base
    case shadow
    case highlight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .base: return "本色"
        case .shadow: return "阴影色"
        case .highlight: return "高光色"
        }
    }
}

struct PaintDose: Codable, Equatable, Sendable {
    let paintCode: String
    let drops: Int
}

struct MixingStep: Codable, Equatable, Sendable {
    let paintCode: String
    let drops: Int
    let instruction: String
}

struct MixingResponse: Codable, Equatable, Sendable {
    let name: String
    let ingredients: [PaintDose]
    let steps: [MixingStep]
    let notes: String
}

/// Only a validated response can become a displayed or saved recipe.
struct MixingRecipe: Codable, Equatable, Sendable {
    static let totalDrops = 200
    static let accuracyNote = "AI 配方是试调起点。颜料混合不是 RGB 平均；请使用等体积的滴量，先做小样，干燥后对色。"

    let target: MixingTarget
    let response: MixingResponse
    let role: MixingRole
    let model: AIModelSelection
    let synthesis: ColorBlendSynthesis?

    init(
        target: MixingTarget,
        response: MixingResponse,
        role: MixingRole = .base,
        model: AIModelSelection = AIModelSelection(),
        synthesis: ColorBlendSynthesis? = nil
    ) throws {
        let codes = Set(GoldenPaint.all.map(\.code))
        guard [target.red, target.green, target.blue].allSatisfy({ (0...255).contains($0) }) else {
            throw MixingError.invalidRecipe("目标 RGB 超出 0～255。")
        }
        guard !response.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              response.name.count <= 80,
              !response.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MixingError.invalidRecipe("缺少配方名称或试调说明。")
        }
        guard response.ingredients.count == codes.count,
              Set(response.ingredients.map(\.paintCode)) == codes,
              response.ingredients.allSatisfy({ (0...Self.totalDrops).contains($0.drops) }) else {
            throw MixingError.invalidRecipe("配方必须列出指定的 12 种颜料，且每种仅出现一次，滴数为非负整数。")
        }
        guard response.ingredients.reduce(0, { $0 + $1.drops }) == Self.totalDrops else {
            throw MixingError.invalidRecipe("各色滴数之和不是 200，已拒绝这份结果，请重新生成。")
        }
        guard !response.steps.isEmpty, response.steps.count <= 36 else {
            throw MixingError.invalidRecipe("缺少可执行的调色步骤。")
        }

        var stepTotals: [String: Int] = [:]
        for step in response.steps {
            guard codes.contains(step.paintCode), (1...Self.totalDrops).contains(step.drops),
                  !step.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MixingError.invalidRecipe("步骤中包含未知颜料、无效滴数或空说明。")
            }
            stepTotals[step.paintCode, default: 0] += step.drops
        }
        guard response.ingredients.allSatisfy({ stepTotals[$0.paintCode, default: 0] == $0.drops }) else {
            throw MixingError.invalidRecipe("步骤中的加入量与滴数表不一致，已拒绝这份结果，请重新生成。")
        }

        self.target = target
        self.response = response
        self.role = role
        guard role != .base || synthesis == nil || synthesis?.target == target else {
            throw MixingError.invalidRecipe("合成目标色与配方本色不一致。")
        }
        self.model = model
        self.synthesis = synthesis
    }

    private enum CodingKeys: String, CodingKey {
        case target, response, role, model, synthesis
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            target: values.decode(MixingTarget.self, forKey: .target),
            response: values.decode(MixingResponse.self, forKey: .response),
            role: values.decodeIfPresent(MixingRole.self, forKey: .role) ?? .base,
            model: values.decodeIfPresent(AIModelSelection.self, forKey: .model) ?? AIModelSelection(),
            synthesis: values.decodeIfPresent(ColorBlendSynthesis.self, forKey: .synthesis)
        )
    }

    static func decode(_ data: Data, for target: MixingTarget) throws -> MixingRecipe {
        guard data.count <= 128_000 else {
            throw MixingError.invalidRecipe("AI 返回内容过长，请重新生成。")
        }
        let response: MixingResponse
        do {
            response = try JSONDecoder().decode(MixingResponse.self, from: data)
        } catch {
            throw MixingError.invalidRecipe("AI 未返回有效的整数滴数配方，请重新生成。")
        }
        return try MixingRecipe(target: target, response: response)
    }

    func drops(for code: String) -> Int {
        response.ingredients.first { $0.paintCode == code }?.drops ?? 0
    }

    var formattedText: String {
        let doses = GoldenPaint.all.map {
            "\($0.mixingName) #\($0.code)：\(drops(for: $0.code)) 滴"
        }.joined(separator: "\n")
        let steps = response.steps.enumerated().map { index, step in
            let paint = GoldenPaint.all.first { $0.code == step.paintCode }
            return "\(index + 1). 加入 \(paint?.mixingName ?? step.paintCode) \(step.drops) 滴。\n\(step.instruction)"
        }.joined(separator: "\n\n")
        return """
        \(role.title) · \(response.name)
        目标：\(target.description) · \(target.hex)
        GOLDEN SoFlat · 总量 200 滴
        \(model.summary)

        \(doses)

        调色步骤
        \(steps)

        试调说明
        \(response.notes)

        \(Self.accuracyNote)
        \(synthesis.map { "\n" + $0.formattedText } ?? "")
        """
    }

    static var responseSchema: [String: Any] {
        let code: [String: Any] = ["type": "string", "enum": GoldenPaint.all.map(\.code)]
        let dose: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "paintCode": code,
                "drops": ["type": "integer", "minimum": 0, "maximum": totalDrops]
            ],
            "required": ["paintCode", "drops"]
        ]
        let step: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "paintCode": code,
                "drops": ["type": "integer", "minimum": 1, "maximum": totalDrops],
                "instruction": ["type": "string"]
            ],
            "required": ["paintCode", "drops", "instruction"]
        ]
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "name": ["type": "string"],
                "ingredients": [
                    "type": "array", "items": dose,
                    "minItems": GoldenPaint.all.count, "maxItems": GoldenPaint.all.count
                ],
                "steps": ["type": "array", "items": step, "minItems": 1, "maxItems": 36],
                "notes": ["type": "string"]
            ],
            "required": ["name", "ingredients", "steps", "notes"]
        ]
        return schema
    }
}

enum MixingError: LocalizedError {
    case invalidConfiguration(String)
    case cliNotFound
    case launchFailed(String)
    case cliFailed(String)
    case timedOut
    case invalidRecipe(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let reason):
            return reason
        case .cliNotFound:
            return "未找到 Codex CLI。请先安装并在终端执行 codex login，或在系统设置的 AI 配置中选择可执行文件。"
        case .launchFailed(let reason):
            return "无法启动 Codex CLI：\(reason)"
        case .cliFailed(let reason):
            return reason
        case .timedOut:
            return "Codex 调色超过 4 分钟，已停止本次请求。请检查网络后重试。"
        case .invalidRecipe(let reason):
            return reason
        }
    }
}

extension GoldenPaint {
    var chineseName: String {
        switch code {
        case "6755": return "钛白"
        case "6745": return "黑色"
        case "6660": return "永久绿"
        case "6610": return "群青"
        case "6505": return "镉浅黄"
        case "6550": return "萘酚浅红"
        case "6645": return "钴青"
        case "6510": return "钒酸铋黄"
        case "6570": return "萘酚粉红"
        case "6530": return "镉橙"
        case "6595": return "红紫"
        case "6675": return "黄绿"
        default: return name
        }
    }

    var mixingName: String { "\(chineseName) · \(name)" }
}
