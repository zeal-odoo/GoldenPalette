// 调色领域模型：目标色、三色角色、原料用量、操作步骤以及经过校验的单份配方。
// 本色检查 200 滴总量；新阴影/高光检查 20 滴本色底料和追加量，兼容旧版独立配方。
import Foundation

/// 注入界面的异步生成接口，便于复用真实服务或固定测试响应。
typealias MixingGenerator = @Sendable (MixingTarget, PaintReference?, MixingPaintSet, AIConfiguration) async throws -> MixingPalette

/// 用于屏幕预览和 AI 输入的整数 sRGB，通道范围为 0...255。
struct MixingTarget: Codable, Equatable, Sendable {
    let red: Int
    let green: Int
    let blue: Int

    /// 将编辑器的浮点通道夹紧并四舍五入成有效整数。
    init(red: Double, green: Double, blue: Double) {
        self.red = Int(ColorInfo.clampedRGB(red).rounded())
        self.green = Int(ColorInfo.clampedRGB(green).rounded())
        self.blue = Int(ColorInfo.clampedRGB(blue).rounded())
    }

    /// 严格解析三个通道输入；不接受空值、小数或越界整数。
    init?(redText: String, greenText: String, blueText: String) {
        let channels = [redText, greenText, blueText].compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard channels.count == 3, channels.allSatisfy({ (0...255).contains($0) }) else { return nil }
        self.init(red: Double(channels[0]), green: Double(channels[1]), blue: Double(channels[2]))
    }

    /// 供界面、提示词和导出文本共用的 RGB 表示。
    var description: String { "RGB \(red), \(green), \(blue)" }
    /// 使用两位大写十六进制展示各通道。
    var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }

    /// 先解除 sRGB 编码再计算相对亮度，用于比较屏幕色的明暗方向。
    /// Compare sRGB reference swatches in linear light, not by averaging encoded RGB.
    /// https://www.w3.org/WAI/GL/wiki/Relative_luminance
    var relativeLuminance: Double {
        // 将编码通道还原为线性光强，不能直接对屏幕 RGB 求亮度加权和。
        func linear(_ channel: Int) -> Double {
            let value = Double(channel) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// 由相对亮度换算屏幕预览的 CIE L*，用于三色层次检查，不表示实测颜料色差。
    /// CIE L* lightness of the preview, using sRGB's D65 white (Yn = 1).
    /// This compares screen targets, not measured paint colors or Delta E.
    /// https://www.w3.org/TR/css-color-4/#color-conversion-code
    var perceptualLightness: Double {
        let luminance = relativeLuminance
        let lightness = luminance > 216.0 / 24_389.0
            ? 116 * pow(luminance, 1.0 / 3.0) - 16
            : (24_389.0 / 27.0) * luminance
        return min(100, max(0, lightness))
    }

    /// 纯黑已无更暗的屏幕目标，允许阴影达到相同边界。
    var isBlack: Bool { red == 0 && green == 0 && blue == 0 }
    /// 纯白已无更亮的屏幕目标，允许高光达到相同边界。
    var isWhite: Bool { red == 255 && green == 255 && blue == 255 }

    /// 新建 RGB 调色任务时使用的初始预览色。
    static let initial = MixingTarget(red: 128, green: 160, blue: 128)
}

/// 一组调色方案中的本色、阴影和高光，原始值同时用于存档。
enum MixingRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case base
    case shadow
    case highlight

    /// 枚举原始值作为选择器和列表的稳定身份。
    var id: String { rawValue }

    /// 显示给用户的色阶角色名称。
    var title: String {
        switch self {
        case .base: return "本色"
        case .shadow: return "阴影色"
        case .highlight: return "高光色"
        }
    }
}

/// 配方用量表中的一种原料；未使用的套装颜料可记录为 0 滴。
struct PaintDose: Codable, Equatable, Sendable {
    let paintCode: String
    let drops: Int
}

/// 一次加入一种颜料的实际操作，同一颜料可分多步加入。
struct MixingStep: Codable, Equatable, Sendable {
    let paintCode: String
    let drops: Int
    let instruction: String
}

/// AI 返回的单份原始配方，尚需 MixingRecipe 校验才可展示或保存。
struct MixingResponse: Codable, Equatable, Sendable {
    let name: String
    let ingredients: [PaintDose]
    let steps: [MixingStep]
    let notes: String
}

/// 阴影/高光取用的已混合本色快照；保存完整原配方，删除本色卡片后仍可重调。
/// 这里的 response 是 200 滴本色原配方，绝不能按比例四舍五入成 20 滴原料。
struct MixingBasePortion: Codable, Equatable, Sendable {
    static let standardDrops = 20
    /// 限制追加总量，避免以“追加”为名重新调制一大份颜料。
    static let maximumAdditionDrops = 20

    let target: MixingTarget
    let response: MixingResponse
    let drops: Int
}

/// 经过领域规则校验的单份配方；也保存生成时的模型、原料与参考色来源。
/// Only a validated response can become a displayed or saved recipe.
struct MixingRecipe: Codable, Equatable, Sendable {
    /// 本色及历史独立配方的总量；新伴随色使用 preparedTotalDrops。
    static let totalDrops = 200
    static let accuracyNote = "AI 配方是试调起点。颜料混合不是 RGB 平均；请使用等体积的滴量，先做小样，干燥后对色。"

    let target: MixingTarget
    let response: MixingResponse
    let role: MixingRole
    let model: AIModelSelection
    // Keep the original series when reading recipes saved before reference-color mixing.
    /// 兼容只记录单一系列的旧配方；新配方同时保存更精确的 paintSet。
    let paintSeries: PaintSeries
    /// 原料套装快照标识；nil 保留早期单系列配方的解释方式。
    let paintSet: MixingPaintSet?
    /// 要复现的商品标准色，与实际投入的 GOLDEN 原料分别记录。
    let referencePaint: PaintReference?
    /// 按比例合色的原始输入和估算说明，普通单色请求可以没有。
    let synthesis: ColorBlendSynthesis?
    /// nil 表示原有的 200 滴独立配方；有值时 response 只记录需要追加的原料。
    let basePortion: MixingBasePortion?

    /// 校验目标、原料、滴数与来源一致性；失败时不创建可保存的配方。
    init(
        target: MixingTarget,
        response: MixingResponse,
        role: MixingRole = .base,
        model: AIModelSelection = AIModelSelection(),
        paintSeries: PaintSeries = .goldenSoFlat,
        paintSet: MixingPaintSet? = nil,
        synthesis: ColorBlendSynthesis? = nil,
        referencePaint: PaintReference? = nil,
        basePortion: MixingBasePortion? = nil
    ) throws {
        // A missing paintSet represents an older single-series recipe, never an expanded palette.
        guard paintSet == nil || paintSeries == paintSet?.primarySeries else {
            throw MixingError.invalidRecipe("配方原料套装与漆系不一致。")
        }
        if let basePortion {
            guard role != .base, paintSet != nil,
                  basePortion.drops == MixingBasePortion.standardDrops else {
                throw MixingError.invalidRecipe("阴影和高光必须各取 20 滴已调好的本色。")
            }
            // 本色快照也经过同样的校验，防止损坏存档绕过原料、来源和 200 滴约束。
            _ = try MixingRecipe(
                target: basePortion.target, response: basePortion.response, model: model,
                paintSeries: paintSeries, paintSet: paintSet,
                synthesis: synthesis, referencePaint: referencePaint
            )
        }
        let maximumDrops = basePortion == nil ? Self.totalDrops : MixingBasePortion.maximumAdditionDrops
        let paints = paintSet?.paints ?? paintSeries.paints
        let codes = Set(paints.map(\.code))
        let requiresAllPaints = paintSet != nil || paintSeries == .goldenSoFlat
        let paintsTitle = paintSet?.title ?? paintSeries.title
        guard [target.red, target.green, target.blue].allSatisfy({ (0...255).contains($0) }) else {
            throw MixingError.invalidRecipe("目标 RGB 超出 0～255。")
        }
        guard !response.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              response.name.count <= 80,
              !response.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MixingError.invalidRecipe("缺少配方名称或试调说明。")
        }
        // 新套装配方必须列全色号，未用填 0；旧版部分系列允许只列实际用到的颜料。
        let suppliedCodes = Set(response.ingredients.map(\.paintCode))
        let minimumDrops = requiresAllPaints ? 0 : 1
        guard !response.ingredients.isEmpty,
              response.ingredients.count <= min(codes.count, 36),
              suppliedCodes.count == response.ingredients.count,
              suppliedCodes.isSubset(of: codes),
              response.ingredients.allSatisfy({ (minimumDrops...maximumDrops).contains($0.drops) }),
              !requiresAllPaints || suppliedCodes == codes else {
            throw MixingError.invalidRecipe(
                "配方只能使用 \(paintsTitle) 色库中的颜料，色号不能重复，滴数必须有效。"
                    + (requiresAllPaints ? "本配方须列全 \(paints.count) 色，未用填 0。" : "")
            )
        }
        let ingredientDrops = response.ingredients.reduce(0) { $0 + $1.drops }
        if let basePortion {
            guard ingredientDrops <= MixingBasePortion.maximumAdditionDrops else {
                throw MixingError.invalidRecipe("20 滴本色的追加颜料合计不能超过 20 滴，请重新生成节省颜料的配方。")
            }
            let unchangedBoundary = target == basePortion.target
                && ((role == .shadow && target.isBlack) || (role == .highlight && target.isWhite))
            guard ingredientDrops > 0 || unchangedBoundary else {
                throw MixingError.invalidRecipe("阴影或高光缺少追加颜料，不能只改目标 RGB。")
            }
            // 相同比例的原料加回本色不会形成新色阶；比较整数比例，避免浮点误差。
            let repeatsBaseRatio = response.ingredients.allSatisfy { dose in
                let baseDrops = basePortion.response.ingredients.first { $0.paintCode == dose.paintCode }?.drops ?? 0
                return dose.drops * Self.totalDrops == baseDrops * ingredientDrops
            }
            guard unchangedBoundary || !repeatsBaseRatio else {
                throw MixingError.invalidRecipe("追加颜料与本色原配方比例相同，无法形成阴影或高光，请重新生成。")
            }
        } else if ingredientDrops != Self.totalDrops {
            throw MixingError.invalidRecipe("各色滴数之和不是 200，已拒绝这份结果，请重新生成。")
        }
        guard (ingredientDrops == 0 || !response.steps.isEmpty), response.steps.count <= 36 else {
            throw MixingError.invalidRecipe("缺少可执行的调色步骤。")
        }

        // 分步累计量必须逐色等于用量表，保证照步骤操作后仍恰好得到规定总量。
        var stepTotals: [String: Int] = [:]
        for step in response.steps {
            guard codes.contains(step.paintCode), (1...maximumDrops).contains(step.drops),
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
        // 合成来源的目标仅与本色绑定，阴影和高光保留各自的目标 RGB。
        guard role != .base || synthesis == nil || synthesis?.target == target else {
            throw MixingError.invalidRecipe("合成目标色与配方本色不一致。")
        }
        if let referencePaint {
            try referencePaint.validate()
            guard (paintSet != nil || paintSeries == .goldenSoFlat), synthesis == nil else {
                throw MixingError.invalidRecipe("品牌参考色配方必须使用指定的 GOLDEN 调色原料。")
            }
            if role == .base { try referencePaint.validate(target: target) }
        }
        self.referencePaint = referencePaint
        self.model = model
        self.paintSeries = paintSeries
        self.paintSet = paintSet
        self.synthesis = synthesis
        self.basePortion = basePortion
    }

    /// 保持存档字段稳定，新增字段通过兼容解码补默认值。
    private enum CodingKeys: String, CodingKey {
        case target, response, role, model, paintSeries, paintSet, synthesis, referencePaint, basePortion
    }

    /// 读取旧存档时仍走同一校验入口，缺失角色、模型和系列时沿用历史默认值。
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            target: values.decode(MixingTarget.self, forKey: .target),
            response: values.decode(MixingResponse.self, forKey: .response),
            role: values.decodeIfPresent(MixingRole.self, forKey: .role) ?? .base,
            model: values.decodeIfPresent(AIModelSelection.self, forKey: .model) ?? AIModelSelection(),
            paintSeries: values.decodeIfPresent(PaintSeries.self, forKey: .paintSeries) ?? .goldenSoFlat,
            paintSet: values.decodeIfPresent(MixingPaintSet.self, forKey: .paintSet),
            synthesis: values.decodeIfPresent(ColorBlendSynthesis.self, forKey: .synthesis),
            referencePaint: values.decodeIfPresent(PaintReference.self, forKey: .referencePaint),
            basePortion: values.decodeIfPresent(MixingBasePortion.self, forKey: .basePortion)
        )
    }

    /// 解码受大小限制的单份响应，然后交给构造器执行完整领域校验。
    static func decode(
        _ data: Data, for target: MixingTarget, referencePaint: PaintReference? = nil,
        paintSet: MixingPaintSet = .defaultSelection
    ) throws -> MixingRecipe {
        try paintSet.validateForGeneration()
        guard data.count <= 128_000 else {
            throw MixingError.invalidRecipe("AI 返回内容过长，请重新生成。")
        }
        let response: MixingResponse
        do {
            response = try JSONDecoder().decode(MixingResponse.self, from: data)
        } catch {
            throw MixingError.invalidRecipe("AI 未返回有效的整数滴数配方，请重新生成。")
        }
        return try MixingRecipe(
            target: target, response: response, paintSeries: paintSet.primarySeries,
            paintSet: paintSet, referencePaint: referencePaint
        )
    }

    /// 追加型配方的用量表不含本色底料，最终总量需要把底料加回。
    var ingredientDrops: Int { response.ingredients.reduce(0) { $0 + $1.drops } }
    var preparedTotalDrops: Int { (basePortion?.drops ?? 0) + ingredientDrops }

    /// 界面和导出共用同一句计量说明，避免旧的“200 滴”误标。
    var quantitySummary: String {
        if let basePortion {
            return "\(basePortion.drops) 滴本色 + \(ingredientDrops) 滴追加 · 合计 \(preparedTotalDrops) 滴"
        }
        return "合计 \(preparedTotalDrops) 滴"
    }

    /// 第一步由本地生成，AI 的 steps 只描述后续追加，不会重复计入本色。
    var basePortionInstruction: String? {
        basePortion.map {
            "另取干净调色杯，加入已充分搅匀的本色「\($0.response.name)」\($0.drops) 滴（\($0.target.hex)）。阴影和高光各取一份，不要往整杯本色或另一色阶中追加。"
        }
    }

    /// 将验证过的快照还原为独立本色详情；不依赖项目里是否还保留本色卡片。
    var basePreparation: MixingRecipe? {
        guard let basePortion else { return nil }
        return try? MixingRecipe(
            target: basePortion.target, response: basePortion.response, model: model,
            paintSeries: paintSeries, paintSet: paintSet,
            synthesis: synthesis, referencePaint: referencePaint
        )
    }

    /// 用量表未列出的色号按 0 滴展示，便于兼容早期精简配方。
    func drops(for code: String) -> Int {
        response.ingredients.first { $0.paintCode == code }?.drops ?? 0
    }

    /// 优先按保存的套装解释原料；旧配方回退到所属系列。
    var paints: [CatalogPaint] { paintSet?.paints ?? paintSeries.paints }
    /// 显示生成时所用套装或历史系列名称。
    var paintsTitle: String { paintSet?.title ?? paintSeries.title }

    /// 重新调色时映射到当前可选套装，同时保持已保存旧配方的原料范围不变。
    /// Reopening AI mixing restores a single kit without modifying any saved recipe.
    var paintSetForNewMixing: MixingPaintSet {
        if let paintSet, paintSet.isSelectable { return paintSet }
        if paintSet == .fluid13 || (paintSet == nil && paintSeries == .goldenFluid) { return .fluid15 }
        return .defaultSelection
    }

    /// 追加配方只列需要加的颜色；本色及历史配方保留原来的用量表。
    var displayedPaints: [CatalogPaint] {
        paints.filter { basePortion == nil ? (paintSet != nil || paintSeries == .goldenSoFlat || drops(for: $0.code) > 0) : drops(for: $0.code) > 0 }
    }

    /// 输出可复制的用量表、步骤和来源说明，明确各份配方的计量及试调限制。
    var formattedText: String {
        let doses = displayedPaints.map {
            "\($0.ingredientName) #\($0.code)：\(drops(for: $0.code)) 滴"
        }.joined(separator: "\n")
        let steps = response.steps.enumerated().map { index, step in
            let paint = paints.first { $0.code == step.paintCode }
            return "\(index + (basePortion == nil ? 1 : 2)). 加入 \(paint?.ingredientName ?? step.paintCode) #\(step.paintCode) \(step.drops) 滴。\n\(step.instruction)"
        }.joined(separator: "\n\n")
        return """
        \(role.title) · \(response.name)
        目标：\(target.description) · \(target.hex)
        调色用漆：\(paintsTitle) · \(quantitySummary)
        \(referencePaint.map { "本色参考标准：" + $0.summary + "\n" + $0.previewNote } ?? "")
        \(model.summary)

        \(basePortion == nil ? "各色用量" : "追加颜料（不含 20 滴本色）")
        \(doses.isEmpty ? "无需追加；已到达此方向的黑/白边界。" : doses)

        调色步骤
        \(basePortionInstruction.map { "1. " + $0 + "\n\n" } ?? "")\(steps)

        试调说明
        \(response.notes)

        \(Self.accuracyNote)
        \(synthesis.map { "\n" + $0.formattedText } ?? "")
        \(basePreparation.map { "\n本色原配方快照（先调好再取 20 滴，不要将原料滴数除以 10）\n" + $0.formattedText } ?? "")
        """
    }

    /// 为 AI 输出限制色号、整数滴数和步骤结构；总量与逐色累计量由构造器复核。
    static func responseSchema(paintSet: MixingPaintSet, isAddition: Bool = false) -> [String: Any] {
        let maximumDrops = isAddition ? MixingBasePortion.maximumAdditionDrops : totalDrops
        let paints = paintSet.paints
        let code: [String: Any] = ["type": "string", "enum": paints.map(\.code)]
        let dose: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "paintCode": code,
                "drops": ["type": "integer", "minimum": 0, "maximum": maximumDrops]
            ],
            "required": ["paintCode", "drops"]
        ]
        let step: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "paintCode": code,
                "drops": ["type": "integer", "minimum": 1, "maximum": maximumDrops],
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
                    "minItems": paints.count, "maxItems": paints.count
                ],
                "steps": ["type": "array", "items": step, "minItems": isAddition ? 0 : 1, "maxItems": 36],
                "notes": ["type": "string"]
            ],
            "required": ["name", "ingredients", "steps", "notes"]
        ]
        return schema
    }
}

/// 调色配置、CLI 执行及响应校验共用的可展示错误。
enum MixingError: LocalizedError {
    case invalidConfiguration(String)
    case cliNotFound
    case launchFailed(String)
    case cliFailed(String)
    case timedOut(after: TimeInterval)
    case invalidRecipe(String)

    /// 将底层失败映射为中文提示，并按实际等待上限描述超时。
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
        case .timedOut(let timeout):
            return "Codex 调色超过 \(max(1, Int(ceil(timeout / 60)))) 分钟，已停止本次请求。高推理强度可能需要更长时间；可选择 high 或模型默认后重试，也请检查网络和账户状态。"
        case .invalidRecipe(let reason):
            return reason
        }
    }
}

// MARK: - SoFlat 原料显示名称
extension GoldenPaint {
    /// 按稳定商品色号提供中文名称；未知色号保留原始名称。
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

    /// 调色列表同时展示中英文名，便于用户对照颜料瓶身。
    var mixingName: String { "\(chineseName) · \(name)" }
}
