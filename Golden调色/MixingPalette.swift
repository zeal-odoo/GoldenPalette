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
    // App contrast policy; relax only the side that approaches black or white.
    private static let minimumLightnessDifference = 15.0
    private static let boundaryContrastFraction = 0.75

    let base: MixingRecipe
    let shadow: MixingRecipe
    let highlight: MixingRecipe

    var recipes: [MixingRecipe] { [base, shadow, highlight] }

    init(
        target: MixingTarget,
        response: MixingPaletteResponse,
        model: AIModelSelection = AIModelSelection(),
        paintSet: MixingPaintSet = .defaultSelection,
        synthesis: ColorBlendSynthesis? = nil,
        referencePaint: PaintReference? = nil
    ) throws {
        try paintSet.validateForGeneration()
        guard synthesis == nil || synthesis?.target == target else {
            throw MixingError.invalidRecipe("合成目标色与配方本色不一致。")
        }
        // The model chooses the two companion targets; the established base RGB is never replaced.
        base = try MixingRecipe(target: target, response: response.base, role: .base, model: model, paintSeries: paintSet.primarySeries, paintSet: paintSet, synthesis: synthesis, referencePaint: referencePaint)
        shadow = try MixingRecipe(target: response.shadow.target, response: response.shadow.recipe, role: .shadow, model: model, paintSeries: paintSet.primarySeries, paintSet: paintSet, synthesis: synthesis, referencePaint: referencePaint)
        highlight = try MixingRecipe(target: response.highlight.target, response: response.highlight.recipe, role: .highlight, model: model, paintSeries: paintSet.primarySeries, paintSet: paintSet, synthesis: synthesis, referencePaint: referencePaint)

        let hasDarkerShadow = shadow.target.relativeLuminance < target.relativeLuminance
        let hasLighterHighlight = highlight.target.relativeLuminance > target.relativeLuminance
        guard hasDarkerShadow || (target.isBlack && shadow.target == target) else {
            throw MixingError.invalidRecipe("阴影色没有比本色更暗，已拒绝这组结果，请重新生成。")
        }
        guard hasLighterHighlight || (target.isWhite && highlight.target == target) else {
            throw MixingError.invalidRecipe("高光色没有比本色更亮，已拒绝这组结果，请重新生成。")
        }
        // A one-channel RGB change is darker/lighter but does not create useful tonal separation.
        // Apply this to new palettes only, so previously saved individual recipes remain readable.
        let baseLightness = target.perceptualLightness
        let shadowDifference = baseLightness - shadow.target.perceptualLightness
        let highlightDifference = highlight.target.perceptualLightness - baseLightness
        let requiredShadowDifference = min(Self.minimumLightnessDifference, baseLightness * Self.boundaryContrastFraction)
        let requiredHighlightDifference = min(Self.minimumLightnessDifference, (100 - baseLightness) * Self.boundaryContrastFraction)
        guard shadowDifference >= requiredShadowDifference else {
            throw MixingError.invalidRecipe("阴影色与本色的明暗差距不足，请重新生成，让阴影更深一些。")
        }
        guard highlightDifference >= requiredHighlightDifference else {
            throw MixingError.invalidRecipe("高光色与本色的明暗差距不足，请重新生成，让高光更亮一些。")
        }

        // At pure black/white the corresponding tone may legitimately reach the same sRGB boundary.
        let sameShadowDoses = base.paints.allSatisfy { base.drops(for: $0.code) == shadow.drops(for: $0.code) }
        let sameHighlightDoses = base.paints.allSatisfy { base.drops(for: $0.code) == highlight.drops(for: $0.code) }
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
        \(base.referencePaint != nil ? "参考色预览" : (base.synthesis == nil ? "输入本色" : "AI 合成本色"))：\(base.target.description) · \(base.target.hex)
        本色、阴影色、高光色各 200 滴，三份共 600 滴，分别调制。

        \(recipes.map(\.formattedText).joined(separator: "\n\n────────────\n\n"))
        """
    }

    static func decode(
        _ data: Data,
        for target: MixingTarget,
        model: AIModelSelection = AIModelSelection(),
        paintSet: MixingPaintSet = .defaultSelection,
        referencePaint: PaintReference? = nil
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
        return try MixingPalette(target: target, response: response, model: model, paintSet: paintSet, referencePaint: referencePaint)
    }

    static func prompt(
        for target: MixingTarget, referencePaint: PaintReference? = nil,
        paintSet: MixingPaintSet = .defaultSelection
    ) -> String {
        let targetDescription: String
        if let referencePaint {
            targetDescription = """
            用户选择的本色参考标准：\(referencePaint.summary)。
            请只用用户选择的 \(paintSet.title) 调色原料，调出尽可能接近该品牌色号的本色及其阴影、高光。
            参考品牌、漆系和色号用于描述目标；实际原料只能从下方 GOLDEN 清单选取。
            参考色屏幕预览：sRGB \(target.description)，\(target.hex)。
            \(referencePaint.previewNote)
            将品牌、色号和名称作为对色依据，结合预览理解色相；屏幕 RGB 不代表实物颜料的精确成色。
            本色预览保留输入 RGB；说明中应明确实际颜料与标准色可能存在偏差。
            """
        } else {
            targetDescription = "用户提供的本色是 sRGB \(target.description)，\(target.hex)。"
        }
        return """
        你是实体颜料调色助手。
        \(targetDescription)
        \(recipeInstructions(paintSet: paintSet))
        """
    }

    static func recipeInstructions(paintSet: MixingPaintSet) -> String {
        let paints = paintSet.series.map { series in
            "\(series.title)（\(series.paints.count) 色）：\n\(series.previewNote)\n"
                + series.paints.map { "\($0.code): \($0.mixingName) · \($0.rgbDescription)" }.joined(separator: "\n")
        }.joined(separator: "\n\n")
        return """
        一次生成一组用于同一物体立体塑造的三色配方，顺序为本色、阴影色、高光色。
        用户希望阴影色、高光色与本色的色差更大一些，三色并排时要有清楚的深、中、浅层次。
        以中性光照为基础，优先拉开明度，保持本色色相协调，避免为了拉大色差而变成另一色系。
        不要只做轻微明暗微调，也不要把所有阴影、高光一律推成纯黑、纯白。

        base：逼近已确定的本色目标 RGB 的配方。不得改动本色目标。
        shadow：你选择的阴影目标 RGB 和其独立配方，视觉上必须比本色更暗。
        highlight：你选择的高光目标 RGB 和其独立配方，视觉上必须比本色更亮。
        阴影和高光的 target 各有 red、green、blue 三个 0～255 的整数，
        这些数值是建议目标色，不是声称测得的真实颜料成色。
        用预览 RGB 的感知明度 L*（0～100）检查层次，通常让阴影降低、高光提高约 20～25 个明度点。
        这是本应用的对比目标，不是实测颜料的色差；不要用 RGB 算术平均或 HSL 的 L 代替。
        计算方法：各 sRGB 通道除以 255 得 c；c <= 0.04045 时取 c/12.92，否则取 ((c+0.055)/1.055)^2.4。
        线性化后 Y = 0.2126R + 0.7152G + 0.0722B，以 sRGB 的 D65 白点为基准；
        Y > 216/24389 时 L* = 116 × Y^(1/3) - 16，否则 L* = (24389/27) × Y。
        最低要求：本色 L* - 阴影 L* >= min(\(minimumLightnessDifference), 本色 L* × \(boundaryContrastFraction))；
        高光 L* - 本色 L* >= min(\(minimumLightnessDifference), (100 - 本色 L*) × \(boundaryContrastFraction))。
        先选协调的目标 RGB，再按上述要求检查；不足时调整目标并重新推断对应的完整配方。
        接近黑/白而没有足够明度空间时，利用该方向剩余空间的至少 \(Int(boundaryContrastFraction * 100))%，可到达边界，
        在对应 notes 中说明限制。纯黑的阴影可同为纯黑，纯白的高光可同为纯白。
        除上述纯黑/纯白边界外，阴影和高光的颜料用量必须支持更明显的深浅变化，不得仅修改目标 RGB 或照抄本色用量。

        用户选择的调色原料套装：\(paintSet.title) · \(paintSet.paints.count) 色。
        仅可使用下方这一套原料，禁止混入另一套 GOLDEN 原料，不得自行切换系列或跨套装调配。
        优先使用少量合适的颜料，不需要使用全部颜色。同名颜色也只能使用清单内的系列和色号，不可等量替换。
        \(paintSet == .fluid13 ? "Fluid Acrylics 的透明度、着色力和遮盖力因颜料而异，酞菁等强着色颜料宜少量分步加入。" : "SoFlat 为哑光丙烯，结合清单中各颜料的着色力、明度和遮盖力分配用量。")
        田宫、郡士等品牌只可作为目标色参考，不得将其色号加入 ingredients 或 steps。
        不得使用其他品牌或清单以外的颜料；水或媒介另行处理。
        本任务匹配颜色，不保证复现参考漆的光泽与遮盖力。
        \(paints)

        三种颜色各自从原始颜料开始调制，每份恰好 200 滴，三份共 600 滴。
        滴数按等体积计量；原装瓶口和粘度会影响滴量，不要把不同瓶口的自然滴大小当成相同体积。
        不要先调本色再往里面追加颜料，也不要把 200 滴拆分成三份。
        每份各有 name、ingredients、steps、notes。
        用实体颜料减色混合、着色力、明度和遮盖力推断，不要把 RGB 线性平均当作颜料混合。
        阴影应考虑协调地降低明度并控制饱和度，高光应提亮并尽量保留本色色相；
        根据这套颜料决定用量，不要机械地只给出“加黑”或“加白”。
        没有实测光谱或干燥色样，不得声称精确复现或编造 Delta E、测量值、匹配百分比，
        超出颜料色域时在 notes 中说明预期偏差。

        每份 ingredients 必须列出这 \(paintSet.paints.count) 个编号各一次，未用的填 0。
        所有 drops 都是非负整数，每份相加必须严格等于 200。优先使用少量合适的颜料。
        steps 按实际操作顺序排列，每步仅加入一种颜料，paintCode 和 drops 表示本步加入量。
        可将同一颜料拆成多步，但每种颜料的步骤累计量必须等于该份 ingredients 中的用量。
        零滴颜料不出现在步骤中。instruction 简短说明搅拌方式和观察时机，不另写额外滴数。
        notes 简短说明此色在三色中的用途、与本色的关系、干燥对色和预期偏差。
        不得在每份 200 滴之外追加颜料，不得引入其他颜料，也不得将水、稀释剂或媒介计入 200 滴。
        name、instruction、notes 使用简体中文，说明清楚且简洁。name 只写色名，不要重复本色、阴影色或高光色标签。
        只返回符合给定 schema 的 JSON。这是调色请求，无需访问文件、运行命令、调用工具或搜索网络。
        """
    }

    static func outputSchema(paintSet: MixingPaintSet = .defaultSelection) throws -> Data {
        try paintSet.validateForGeneration()
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
            "properties": ["target": target, "recipe": MixingRecipe.responseSchema(paintSet: paintSet)],
            "required": ["target", "recipe"]
        ]
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": ["base": MixingRecipe.responseSchema(paintSet: paintSet), "shadow": tone, "highlight": tone],
            "required": ["base", "shadow", "highlight"]
        ]
        return try JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])
    }
}
