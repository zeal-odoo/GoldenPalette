import Foundation

struct MixingToneResponse: Codable, Equatable, Sendable {
    let target: MixingTarget
    let recipe: MixingResponse
}

struct MixingPaletteResponse: Codable, Equatable, Sendable {
    let base: MixingResponse
    let shadow: MixingToneResponse
    let highlight: MixingToneResponse
}

/// One request produces three independently validated 200-drop recipes.
struct MixingPalette: Equatable, Sendable {
    static let maximumResponseBytes = 384_000

    let base: MixingRecipe
    let shadow: MixingRecipe
    let highlight: MixingRecipe

    var recipes: [MixingRecipe] { [base, shadow, highlight] }

    init(
        target: MixingTarget,
        response: MixingPaletteResponse,
        model: AIModelSelection = AIModelSelection(),
        synthesis: ColorBlendSynthesis? = nil
    ) throws {
        guard synthesis == nil || synthesis?.target == target else {
            throw MixingError.invalidRecipe("合成目标色与配方本色不一致。")
        }
        // The model chooses the two companion targets; the established base RGB is never replaced.
        base = try MixingRecipe(target: target, response: response.base, role: .base, model: model, synthesis: synthesis)
        shadow = try MixingRecipe(target: response.shadow.target, response: response.shadow.recipe, role: .shadow, model: model, synthesis: synthesis)
        highlight = try MixingRecipe(target: response.highlight.target, response: response.highlight.recipe, role: .highlight, model: model, synthesis: synthesis)

        let hasDarkerShadow = shadow.target.relativeLuminance < target.relativeLuminance
        let hasLighterHighlight = highlight.target.relativeLuminance > target.relativeLuminance
        guard hasDarkerShadow || (target.isBlack && shadow.target == target) else {
            throw MixingError.invalidRecipe("阴影色没有比本色更暗，已拒绝这组结果，请重新生成。")
        }
        guard hasLighterHighlight || (target.isWhite && highlight.target == target) else {
            throw MixingError.invalidRecipe("高光色没有比本色更亮，已拒绝这组结果，请重新生成。")
        }
        // At pure black/white the corresponding tone may legitimately reach the same sRGB boundary.
        let sameShadowDoses = GoldenPaint.all.allSatisfy { base.drops(for: $0.code) == shadow.drops(for: $0.code) }
        let sameHighlightDoses = GoldenPaint.all.allSatisfy { base.drops(for: $0.code) == highlight.drops(for: $0.code) }
        guard target.isBlack || !sameShadowDoses, target.isWhite || !sameHighlightDoses else {
            throw MixingError.invalidRecipe("阴影或高光重复了本色的用量，未形成三色配方，请重新生成。")
        }
    }

    func recipe(for role: MixingRole) -> MixingRecipe {
        switch role {
        case .base: return base
        case .shadow: return shadow
        case .highlight: return highlight
        }
    }

    var formattedText: String {
        """
        三色调色配方 · \(base.response.name)
        \(base.synthesis == nil ? "输入本色" : "AI 合成本色")：\(base.target.description) · \(base.target.hex)
        本色、阴影色、高光色各 200 滴，三份共 600 滴，分别调制。

        \(recipes.map(\.formattedText).joined(separator: "\n\n────────────\n\n"))
        """
    }

    static func decode(
        _ data: Data,
        for target: MixingTarget,
        model: AIModelSelection = AIModelSelection()
    ) throws -> MixingPalette {
        guard data.count <= maximumResponseBytes else {
            throw MixingError.invalidRecipe("AI 返回内容过长，请重新生成。")
        }
        let response: MixingPaletteResponse
        do {
            response = try JSONDecoder().decode(MixingPaletteResponse.self, from: data)
        } catch {
            throw MixingError.invalidRecipe("AI 没有返回完整的本色、阴影色和高光色配方，请重新生成。")
        }
        return try MixingPalette(target: target, response: response, model: model)
    }

    static func prompt(for target: MixingTarget) -> String {
        """
        你是实体丙烯颜料调色助手。用户提供的本色是 sRGB \(target.description)，\(target.hex)。
        \(recipeInstructions)
        """
    }

    static var recipeInstructions: String {
        let paints = GoldenPaint.all.map { "\($0.code): \($0.name)" }.joined(separator: "\n")
        return """
        一次生成一组用于同一物体立体塑造的三色配方，顺序为本色、阴影色、高光色。
        使用中性光照下的常规阴影和高光，保持色相协调，避免无依据的大幅改变色相。

        base：逼近已确定的本色目标 RGB 的配方。不得改动本色目标。
        shadow：你选择的阴影目标 RGB 和其独立配方，视觉上必须比本色更暗。
        highlight：你选择的高光目标 RGB 和其独立配方，视觉上必须比本色更亮。
        阴影和高光的 target 各有 red、green、blue 三个 0～255 的整数，
        这些数值是建议目标色，不是声称测得的真实颜料成色。
        根据线性化 sRGB 相对亮度判断明暗，不要只比较 RGB 数值的算术平均。
        若本色为纯黑，阴影目标可同为纯黑；若本色为纯白，高光目标可同为纯白，
        并在对应 notes 中明确说明色域边界。其他情况下三色要有可辨别的明暗层次，
        阴影和高光不得照抄本色颜料用量；本色若很接近黑/白，可将对应目标推到边界。

        仅允许以下 GOLDEN SoFlat 12 种颜料（编号是唯一标识）：
        \(paints)

        三种颜色各自从原始颜料开始调制，每份恰好 200 滴，三份共 600 滴。
        不要先调本色再往里面追加颜料，也不要把 200 滴拆分成三份。
        每份各有 name、ingredients、steps、notes。
        用实体颜料减色混合、着色力、明度和遮盖力推断，不要把 RGB 线性平均当作颜料混合。
        阴影应考虑协调地降低明度并控制饱和度，高光应提亮并尽量保留本色色相；
        根据这套颜料决定用量，不要机械地只给出“加黑”或“加白”。
        没有实测光谱或干燥色样，不得声称精确复现或编造 Delta E、测量值、匹配百分比，
        超出颜料色域时在 notes 中说明预期偏差。

        每份 ingredients 都必须列出这 12 个编号各一次，未用的填 0，
        所有 drops 都是非负整数，每份相加必须严格等于 200。优先使用少量合适的颜料。
        steps 按实际操作顺序排列，每步仅加入一种颜料，paintCode 和 drops 表示本步加入量。
        可将同一颜料拆成多步，但每种颜料的步骤累计量必须等于该份 ingredients 中的用量。
        零滴颜料不出现在步骤中。instruction 简短说明搅拌方式和观察时机，不另写额外滴数。
        notes 简短说明此色在三色中的用途、与本色的关系、干燥对色和预期偏差。
        不得在每份 200 滴之外追加颜料，不得引入其他颜料，也不得将水或媒介计入 200 滴。
        name、instruction、notes 使用简体中文，说明清楚且简洁。name 只写色名，不要重复本色、阴影色或高光色标签。
        只返回符合给定 schema 的 JSON。这是调色请求，无需访问文件、运行命令、调用工具或搜索网络。
        """
    }

    static func outputSchema() throws -> Data {
        let channel: [String: Any] = ["type": "integer", "minimum": 0, "maximum": 255]
        let target: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": ["red": channel, "green": channel, "blue": channel],
            "required": ["red", "green", "blue"]
        ]
        let tone: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": ["target": target, "recipe": MixingRecipe.responseSchema],
            "required": ["target", "recipe"]
        ]
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": ["base": MixingRecipe.responseSchema, "shadow": tone, "highlight": tone],
            "required": ["base", "shadow", "highlight"]
        ]
        return try JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])
    }
}
