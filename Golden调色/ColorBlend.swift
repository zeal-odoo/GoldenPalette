import Foundation

typealias BlendMixingGenerator = @Sendable (ColorBlendRequest, AIConfiguration) async throws -> MixingPalette

struct ColorBlendSource: Codable, Equatable, Sendable {
    let target: MixingTarget
    let percentage: Double

    var percentageText: String { String(format: "%g", percentage) }
}

struct ColorBlendRequest: Equatable, Sendable {
    let sources: [ColorBlendSource]

    init(sources: [ColorBlendSource]) throws {
        guard sources.count >= 2,
              sources.allSatisfy({
                  $0.percentage.isFinite && $0.percentage > 0 && $0.percentage <= 100
                      && [$0.target.red, $0.target.green, $0.target.blue].allSatisfy { (0...255).contains($0) }
              }),
              sources.reduce(0, { $0 + $1.percentage }).isFinite else {
            throw MixingError.invalidRecipe("请填写至少两组颜色，RGB 为 0～255 的整数，占比大于 0 且不超过 100%。")
        }
        self.sources = sources
    }

    var totalPercentage: Double { sources.reduce(0) { $0 + $1.percentage } }
    var totalPercentageText: String { String(format: "%g", totalPercentage) }

    var sourceDescription: String {
        sources.enumerated().map { index, source in
            let normalized = source.percentage / totalPercentage * 100
            return "\(index + 1). \(source.target.description) · \(source.target.hex) · 输入 \(source.percentageText)%（归一化 \(String(format: "%.2f", normalized))%）"
        }.joined(separator: "\n")
    }

    var prompt: String {
        """
        你是实体丙烯颜料的色彩合成与调色助手。请由 AI 完成多颜色合成，并给出可执行的三色配方。
        用户提供的不是颜料编号，而是多个 sRGB 颜色参考和它们在合色中的相对占比：
        \(sourceDescription)
        输入比例合计 \(totalPercentageText)%。按照相对比例换算成 100%。
        不得将不足 100% 的部分补成白色、黑色、水、透明色或任何额外颜色。

        先综合颜色关系、占比、实体颜料减色混合和主导色，推断一个合成目标色，
        在 synthesis.target 返回 red、green、blue 三个 0～255 的整数。
        这一步必须由你分析，不要仅将编码后的 RGB 通道做算术平均当作颜料混合。
        synthesis.explanation 用简体中文简要说明各颜色和比例如何影响结果，并说明这是基于 RGB 参考的估算。
        没有输入颜料的光谱、着色力或实测混合数据，不得声称精确预测了物理混合结果。

        再以你确定的 synthesis.target 作为唯一的本色目标，在 palette 返回三色调色配方。
        合成输入占比与最终 12 种颜料的滴数是两种不同数据；不要直接把输入百分比乘以 200 当作颜料用量。
        \(MixingPalette.recipeInstructions)
        """
    }

    static func outputSchema() throws -> Data {
        let channel: [String: Any] = ["type": "integer", "minimum": 0, "maximum": 255]
        let target: [String: Any] = [
            "type": "object", "additionalProperties": false,
            "properties": ["red": channel, "green": channel, "blue": channel],
            "required": ["red", "green", "blue"]
        ]
        let synthesis: [String: Any] = [
            "type": "object", "additionalProperties": false,
            "properties": ["target": target, "explanation": ["type": "string"]],
            "required": ["target", "explanation"]
        ]
        let palette = try JSONSerialization.jsonObject(with: MixingPalette.outputSchema())
        return try JSONSerialization.data(withJSONObject: [
            "type": "object", "additionalProperties": false,
            "properties": ["synthesis": synthesis, "palette": palette],
            "required": ["synthesis", "palette"]
        ], options: [.sortedKeys])
    }

    func decodePalette(_ data: Data, model: AIModelSelection = AIModelSelection()) throws -> MixingPalette {
        guard data.count <= MixingPalette.maximumResponseBytes else {
            throw MixingError.invalidRecipe("AI 返回内容过长，请重新生成。")
        }
        let response: BlendPaletteResponse
        do {
            response = try JSONDecoder().decode(BlendPaletteResponse.self, from: data)
        } catch {
            throw MixingError.invalidRecipe("AI 未返回完整的合成颜色、说明和三色配方，请重新生成。")
        }
        // Keep the original inputs from this request; never replace them with an AI-generated echo.
        let synthesis = try ColorBlendSynthesis(
            sources: sources,
            target: response.synthesis.target,
            explanation: response.synthesis.explanation
        )
        return try MixingPalette(
            target: synthesis.target, response: response.palette, model: model, synthesis: synthesis
        )
    }

    private struct BlendPaletteResponse: Decodable {
        struct SynthesisResponse: Decodable {
            let target: MixingTarget
            let explanation: String
        }

        let synthesis: SynthesisResponse
        let palette: MixingPaletteResponse
    }
}

struct ColorBlendSynthesis: Codable, Equatable, Sendable {
    let sources: [ColorBlendSource]
    let target: MixingTarget
    let explanation: String

    init(sources: [ColorBlendSource], target: MixingTarget, explanation: String) throws {
        _ = try ColorBlendRequest(sources: sources)
        let explanation = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard [target.red, target.green, target.blue].allSatisfy({ (0...255).contains($0) }),
              !explanation.isEmpty, explanation.count <= 3_000 else {
            throw MixingError.invalidRecipe("AI 合成颜色的 RGB 或说明无效，请重新生成。")
        }
        self.sources = sources
        self.target = target
        self.explanation = explanation
    }

    private enum CodingKeys: String, CodingKey {
        case sources, target, explanation
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sources: values.decode([ColorBlendSource].self, forKey: .sources),
            target: values.decode(MixingTarget.self, forKey: .target),
            explanation: values.decode(String.self, forKey: .explanation)
        )
    }

    var formattedText: String {
        let inputs = sources.enumerated().map { index, source in
            "\(index + 1). \(source.target.description) · \(source.percentageText)%"
        }.joined(separator: "\n")
        return """
        AI 按比例合成
        \(inputs)
        按相对比例换算为 100%。
        AI 合成本色：\(target.description) · \(target.hex)
        合成说明：\(explanation)
        """
    }
}
