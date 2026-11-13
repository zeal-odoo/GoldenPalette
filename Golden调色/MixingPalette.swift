// 三色配方组合：固定本色目标，验证阴影和高光的方向、明度差与用量差异。
// 此文件也集中定义三色生成提示词和 JSON 输出结构。
import Foundation

/// 阴影或高光的 AI 原始响应；recipe 仅包含往本色中追加的颜料。
struct MixingToneResponse: Codable, Equatable, Sendable {
    let target: MixingTarget
    let recipe: MixingResponse
    /// 必须由 AI 明确返回 20，缺失或其他值都拒绝，避免误读旧版独立配方。
    let baseDrops: Int

    init(target: MixingTarget, recipe: MixingResponse, baseDrops: Int = MixingBasePortion.standardDrops) {
        self.target = target
        self.recipe = recipe
        self.baseDrops = baseDrops
    }
}

/// 一次请求返回三种色阶；本色 RGB 来自输入，因此 base 不重复返回目标。
struct MixingPaletteResponse: Codable, Equatable, Sendable {
    let base: MixingResponse
    let shadow: MixingToneResponse
    let highlight: MixingToneResponse
}

/// 本色调制 200 滴；阴影、高光各分取 20 滴本色并追加颜料，保证三色形成可用层次。
struct MixingPalette: Equatable, Sendable {
    /// 限制完整响应大小，避免异常输出无限占用内存。
    static let maximumResponseBytes = 384_000
    // App contrast policy; relax only the side that approaches black or white.
    /// 正常要求至少相差 18 个 L*；靠近黑白边界时改用剩余空间的 75%。
    private static let minimumLightnessDifference = 18.0
    private static let boundaryContrastFraction = 0.75

    let base: MixingRecipe
    let shadow: MixingRecipe
    let highlight: MixingRecipe

    /// 固定本色、阴影、高光顺序，供列表展示、复制和一次性保存使用。
    var recipes: [MixingRecipe] { [base, shadow, highlight] }

    /// 先验证三份配方，再检查明暗方向、层次差距以及是否照抄本色用量。
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
        // 本色目标由用户或合成结果决定；模型只可选择阴影和高光的目标。
        // The model chooses the two companion targets; the established base RGB is never replaced.
        base = try MixingRecipe(target: target, response: response.base, role: .base, model: model, paintSeries: paintSet.primarySeries, paintSet: paintSet, synthesis: synthesis, referencePaint: referencePaint)
        // 底料身份由已验证的本色生成，不接受 AI 回传另一份本色或稀释过的原料比例。
        let shadowPortion = MixingBasePortion(target: target, response: base.response, drops: response.shadow.baseDrops)
        let highlightPortion = MixingBasePortion(target: target, response: base.response, drops: response.highlight.baseDrops)
        shadow = try MixingRecipe(
            target: response.shadow.target, response: response.shadow.recipe, role: .shadow, model: model,
            paintSeries: paintSet.primarySeries, paintSet: paintSet, synthesis: synthesis,
            referencePaint: referencePaint, basePortion: shadowPortion
        )
        highlight = try MixingRecipe(
            target: response.highlight.target, response: response.highlight.recipe, role: .highlight, model: model,
            paintSeries: paintSet.primarySeries, paintSet: paintSet, synthesis: synthesis,
            referencePaint: referencePaint, basePortion: highlightPortion
        )

        let hasDarkerShadow = shadow.target.relativeLuminance < target.relativeLuminance
        let hasLighterHighlight = highlight.target.relativeLuminance > target.relativeLuminance
        guard hasDarkerShadow || (target.isBlack && shadow.target == target) else {
            throw MixingError.invalidRecipe("阴影色没有比本色更暗，已拒绝这组结果，请重新生成。")
        }
        guard hasLighterHighlight || (target.isWhite && highlight.target == target) else {
            throw MixingError.invalidRecipe("高光色没有比本色更亮，已拒绝这组结果，请重新生成。")
        }
        // 明暗方向正确不代表差距够大；仅对新生成组合执行层次检查，保持旧配方可读。
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


    }

    /// 按角色读取相应配方，避免界面依赖数组位置。
    func recipe(for role: MixingRole) -> MixingRecipe {
        switch role {
        case .base: return base
        case .shadow: return shadow
        case .highlight: return highlight
        }
    }

    /// 两份底料从同一杯本色取出，计算总耗料时不重复计算这 40 滴。
    var totalPaintDrops: Int { base.preparedTotalDrops + shadow.ingredientDrops + highlight.ingredientDrops }
    var remainingBaseDrops: Int {
        base.preparedTotalDrops - (shadow.basePortion?.drops ?? 0) - (highlight.basePortion?.drops ?? 0)
    }

    var preparationSummary: String {
        "先调本色 200 滴，再分别取 20 滴做阴影和高光。本色剩余 \(remainingBaseDrops) 滴，加上两份追加颜料，共用原料 \(totalPaintDrops) 滴。"
    }

    /// 明确先调本色、分别取样、再追加的顺序；总耗料不重复计算本色底料。
    var formattedText: String {
        """
        三色调色配方 · \(base.response.name)
        \(base.referencePaint != nil ? "参考色预览" : (base.synthesis == nil ? "输入本色" : "AI 合成本色"))：\(base.target.description) · \(base.target.hex)
        \(preparationSummary)

        \(recipes.map(\.formattedText).joined(separator: "\n\n────────────\n\n"))
        """
    }

    /// 解码完整三色响应并执行组合校验；错误使用统一的用户提示。
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

    /// 根据自定义 RGB 或商品参考色生成目标说明，再拼接公共配方要求。
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

    /// RGB 调色和比例合色共用的原料范围、计量、明度及输出约束。
    static func recipeInstructions(paintSet: MixingPaintSet) -> String {
        let paints = paintSet.series.map { series in
            "\(series.title)（\(series.paints.count) 色）：\n\(series.previewNote)\n"
                + series.paints.map { "\($0.code): \($0.mixingName) · \($0.rgbDescription)" }.joined(separator: "\n")
        }.joined(separator: "\n\n")
        return """
        一次生成一组用于同一物体立体塑造的三色配方，顺序为本色、阴影色、高光色。
        用户希望节省颜料，并让阴影色、高光色自然且对比度稍强，三色并排时有清楚的深、中、浅层次。
        以中性光照为基础，优先拉开明度，保持本色色相协调，避免为了拉大色差而变成另一色系。
        不要只做轻微明暗微调，也不要把所有阴影、高光一律推成纯黑、纯白。

        base：逼近已确定的本色目标 RGB 的配方。不得改动本色目标。
        shadow：另取 20 滴已混合本色，加入你给出的追加颜料；返回更暗的目标 RGB 和追加配方。
        highlight：重新另取 20 滴已混合本色，加入你给出的追加颜料；返回更亮的目标 RGB 和追加配方。
        shadow.baseDrops 和 highlight.baseDrops 必须都为 20。两份来自同一原始本色，不串联调制。
        阴影和高光的 target 各有 red、green、blue 三个 0～255 的整数，
        这些数值是建议目标色，不是声称测得的真实颜料成色。
        用预览 RGB 的感知明度 L*（0～100）检查层次，通常让阴影降低、高光提高约 20～28 个明度点。
        这是本应用的对比目标，不是实测颜料的色差；不要用 RGB 算术平均或 HSL 的 L 代替。
        计算方法：各 sRGB 通道除以 255 得 c；c <= 0.04045 时取 c/12.92，否则取 ((c+0.055)/1.055)^2.4。
        线性化后 Y = 0.2126R + 0.7152G + 0.0722B，以 sRGB 的 D65 白点为基准；
        Y > 216/24389 时 L* = 116 × Y^(1/3) - 16，否则 L* = (24389/27) × Y。
        最低要求：本色 L* - 阴影 L* >= min(\(minimumLightnessDifference), 本色 L* × \(boundaryContrastFraction))；
        高光 L* - 本色 L* >= min(\(minimumLightnessDifference), (100 - 本色 L*) × \(boundaryContrastFraction))。
        先选协调的目标 RGB，再按上述要求检查；不足时调整目标并重新推断对应的追加配方。
        接近黑/白而没有足够明度空间时，利用该方向剩余空间的至少 \(Int(boundaryContrastFraction * 100))%，可到达边界，
        在对应 notes 中说明限制。纯黑的阴影可同为纯黑，纯白的高光可同为纯白。
        除上述纯黑/纯白边界外，阴影和高光必须有实际追加量支持深浅变化，不得仅修改目标 RGB，也不得按本色原料比例追加（这不会改变颜色）。

        用户选择的调色原料套装：\(paintSet.title) · \(paintSet.paints.count) 色。
        仅可使用下方这一套原料，禁止混入另一套 GOLDEN 原料，不得自行切换系列或跨套装调配。
        优先使用少量合适的颜料，不需要使用全部颜色。同名颜色也只能使用清单内的系列和色号，不可等量替换。
        \(paintSet.primarySeries == .goldenFluid ? "Fluid Acrylics 的透明度、着色力和遮盖力因颜料而异，酞菁等强着色颜料宜少量分步加入。" : "SoFlat 为哑光丙烯，结合清单中各颜料的着色力、明度和遮盖力分配用量。")
        田宫、郡士等品牌只可作为目标色参考，不得将其色号加入 ingredients 或 steps。
        不得使用其他品牌或清单以外的颜料；水或媒介另行处理。
        本任务匹配颜色，不保证复现参考漆的光泽与遮盖力。
        \(paints)

        先按 base 配方调好 200 滴本色并充分搅匀。然后从中各取 20 滴，分别做阴影和高光，本色剩余 160 滴。
        20 滴指已经混合好的本色，不是将本色原料逐项除以 10；不要重新从零调制两份 200 滴的伴随色。
        不要往全部本色里加料，不要用阴影去调高光，也不要将本色作为某个 paintCode 伪装成单一原料。
        滴数按等体积计量；原装瓶口和粘度会影响滴量，不要把不同瓶口的自然滴大小当成相同体积。
        每份 recipe 各有 name、ingredients、steps、notes。
        用实体颜料减色混合、着色力、明度和遮盖力推断，不要把 RGB 线性平均当作颜料混合。
        根据 base 的实际组成、强弱着色力与透明度，推断在 20 滴本色中加入多少颜料能形成目标色。
        阴影优先选择与本色色相协调的较暗颜料，必要时微量互补色降饱和度，避免发脏、死黑或变成另一色系。
        高光用合适的浅色提亮，必要时补少量原色维持色相，避免只加大量钛白造成粉白、灰浊或失去色彩。
        可有适度冷暖变化，但要像同一物体在中性光下的自然明暗；不要机械地只给出“加黑”或“加白”。
        优先用 1～3 种追加颜料、总计 1～8 滴；确有必要可增加，但每份追加量最多 \(MixingBasePortion.maximumAdditionDrops) 滴。
        最终阴影/高光总量是 20 + 追加滴数，通常 21～28 滴，上限 40 滴，不要求凑成固定总量。
        若整数滴和本套颜料不能同时达到理想自然度及明度，请在 notes 中坦诚说明预期限制，不编造物理成色。
        没有实测光谱或干燥色样，不得声称精确复现或编造 Delta E、测量值、匹配百分比，
        超出颜料色域时在 notes 中说明预期偏差。

        每份 ingredients 必须列出这 \(paintSet.paints.count) 个编号各一次，未用的填 0。所有 drops 都是非负整数。
        base 的 ingredients 总和必须严格等于 200；shadow/highlight 的 ingredients 只计追加原料，总和为 1～20。
        仅纯黑本色的阴影、纯白本色的高光允许无需追加：target 保持相同、ingredients 全为 0、steps 为空，并在 notes 说明边界。
        steps 按实际操作顺序排列，每步仅加入一种清单内的颜料，paintCode 和 drops 表示本步加入量。
        应用会自动在阴影和高光前添加“另取 20 滴本色”的第一步，AI 的 steps 只写之后的追加操作。
        可将同一颜料拆成多步，但每种颜料的步骤累计量必须等于该份 ingredients 中的用量。
        零滴颜料不出现在步骤中。instruction 简短说明充分搅匀、薄涂观察及干燥对色时机，不另写额外滴数。
        notes 说明为何这样追加能够保持自然色相并拉开明暗、此色用途、干燥对色和预期偏差。
        步骤及文字不得再要求表外追加任何颜料；水、稀释剂和媒介另行处理，不计入颜料滴数。
        name、instruction、notes 使用简体中文，说明清楚且简洁。name 只写色名，不要重复本色、阴影色或高光色标签。
        只返回符合给定 schema 的 JSON。这是调色请求，无需访问文件、运行命令、调用工具或搜索网络。
        """
    }

    /// 构造三色 JSON Schema，阴影与高光各包含目标 RGB 和单份配方结构。
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
            "properties": [
                "target": target,
                "baseDrops": ["type": "integer", "enum": [MixingBasePortion.standardDrops]],
                "recipe": MixingRecipe.responseSchema(paintSet: paintSet, isAddition: true)
            ],
            "required": ["target", "baseDrops", "recipe"]
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
