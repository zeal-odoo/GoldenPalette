// AI 调色工作界面：支持 RGB、商品标准色及比例合色三种输入，统一生成和保存三色方案。
// 生成器从外部注入；本视图管理输入草稿、请求身份、取消及结果展示。
import SwiftUI
import AppKit

/// 主线程协调输入与异步结果，避免已取消或已过期请求写回当前界面。
@MainActor
struct AIMixingView: View {
    @Environment(\.dismiss) private var dismiss
    // MARK: - 输入草稿与生成状态
    @State private var redText: String
    @State private var greenText: String
    @State private var blueText: String
    @State private var inputMode: MixingInputMode
    /// 用户实际拥有的调色原料套装，与商品目标参考系列分别保存。
    @State private var paintSet: MixingPaintSet
    @State private var blendEntries: [ColorBlendEntry]
    @State private var result: MixingPalette?
    @State private var errorMessage: String?
    /// 当前请求身份；取消或输入变化后旧请求不得继续提交结果。
    @State private var requestID: UUID?
    @State private var generationTask: Task<Void, Never>?
    /// 请求开始时的模型快照，用于等待提示及生成来源展示。
    @State private var activeModel: AIModelSelection?
    // 参考系列和色号仅描述要复现的目标，不改变实际调色原料。
    @State private var referenceSeries: PaintSeries
    @State private var selectedPaintCode: String?
    @State private var paintSearchText = ""

    // MARK: - 项目上下文与注入能力
    let projectName: String
    let configuration: AIConfiguration
    let canSave: Bool
    let generateRecipe: MixingGenerator
    let generateBlend: BlendMixingGenerator
    /// 将完整三色交给原项目保存；只有保存成功才关闭窗口。
    let onSave: (MixingPalette) -> Bool

    /// 根据初始参考色选择输入模式，并建立独立的 RGB 与比例合色草稿。
    init(
        projectName: String,
        initialTarget: MixingTarget = .initial,
        initialReferencePaint: PaintReference? = nil,
        initialPaintSet: MixingPaintSet = .defaultSelection,
        configuration: AIConfiguration,
        canSave: Bool,
        generateBlend: @escaping BlendMixingGenerator = { request, paintSet, configuration in
            try await CodexMixingService().generate(from: request, paintSet: paintSet, configuration: configuration)
        },
        generateRecipe: @escaping MixingGenerator,
        onSave: @escaping (MixingPalette) -> Bool
    ) {
        _paintSet = State(initialValue: initialPaintSet.isSelectable ? initialPaintSet : .defaultSelection)
        _referenceSeries = State(initialValue: initialReferencePaint?.series ?? .tamiyaAcrylic)
        _selectedPaintCode = State(initialValue: initialReferencePaint?.paintCode)
        _inputMode = State(initialValue: initialReferencePaint == nil ? .single : .reference)
        _redText = State(initialValue: String(initialTarget.red))
        _greenText = State(initialValue: String(initialTarget.green))
        _blueText = State(initialValue: String(initialTarget.blue))
        _blendEntries = State(initialValue: [
            ColorBlendEntry(target: initialTarget, percentage: 50),
            ColorBlendEntry(target: MixingTarget(red: 255, green: 255, blue: 255), percentage: 50)
        ])
        self.projectName = projectName
        self.configuration = configuration
        self.canSave = canSave
        self.generateRecipe = generateRecipe
        self.generateBlend = generateBlend
        self.onSave = onSave
    }

    /// 从当前参考系列和色号构造商品引用。
    private var selectedReference: PaintReference? {
        guard let selectedPaintCode else { return nil }
        return PaintReference(series: referenceSeries, paintCode: selectedPaintCode)
    }

    /// 只有标准色模式才向服务传入商品引用，避免残留选择影响其他输入模式。
    private var activeReference: PaintReference? {
        inputMode == .reference ? selectedReference : nil
    }

    /// 标准色使用目录预览，RGB 模式严格解析文本；合色模式另走 blendRequest。
    private var target: MixingTarget? {
        if inputMode == .reference { return selectedReference?.previewTarget }
        return MixingTarget(redText: redText, greenText: greenText, blueText: blueText)
    }

    /// 请求身份存在即表示正在生成，不依赖任务句柄是否仍被持有。
    private var isGenerating: Bool { requestID != nil }

    /// 将所有合色输入一起校验，任何一行无效时都不能生成。
    private var blendRequest: ColorBlendRequest? { ColorBlendEntry.request(from: blendEntries) }
    /// 按当前输入模式检查对应数据是否可提交。
    private var hasValidInput: Bool { inputMode == .blend ? blendRequest != nil : target != nil }

    /// 系统取色器与文本通道双向同步，先转换到 sRGB 再保存为整数输入。
    private var selectedColor: Binding<Color> {
        Binding(
            get: { target?.color ?? .gray },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                let selected = MixingTarget(
                    red: rgb.redComponent * 255,
                    green: rgb.greenComponent * 255,
                    blue: rgb.blueComponent * 255
                )
                redText = String(selected.red)
                greenText = String(selected.green)
                blueText = String(selected.blue)
            }
        )
    }

    /// 固定头部、错误区和保存区，中间输入与结果各自滚动。
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI 调色 · \(projectName)")
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                        .accessibilityIdentifier("mixingProjectTitle")
                    Text("调色用漆：\(paintSet.title) · \(paintSet.paints.count) 色 · 阴影/高光各用 20 滴本色追加")
                        .accessibilityIdentifier("mixingPaintSummary")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") {
                    cancelGeneration()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("closeAIMixingButton")
            }
            .padding(20)

            Divider()

            if let errorMessage {
                // Keep failures visible even when the ingredients or recipe were scrolled down.
                ScrollView {
                    Text(errorMessage)
                        .foregroundStyle(AppPalette.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("mixingError")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                .frame(height: 84)
                Divider()
            }

            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    inputPanel
                        .padding(20)
                }
                .accessibilityIdentifier("mixingInputScrollView")
                .frame(width: 296)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let result {
                            MixingPaletteDetails(palette: result)
                        } else if isGenerating {
                            VStack(alignment: .leading, spacing: 16) {
                                ProgressView()
                                Text(inputMode == .blend ? "AI 正在合成目标色并计算三色配方…" : "正在计算本色、阴影色和高光色…")
                                    .font(.headline)
                                Text((activeModel ?? configuration.model).reasoningEffort.generationWaitDescription)
                                    .accessibilityIdentifier("mixingWaitDescription")
                                    .foregroundStyle(.secondary)
                                Button("取消生成", action: cancelGeneration)
                                    .accessibilityIdentifier("cancelMixingButton")
                            }
                            .padding(.vertical, 40)
                        } else {
                            Text("调色原料 · GOLDEN \(paintSet.paints.count) 色").font(.headline)
                            Text("先调本色 200 滴，再各取 20 滴调阴影和高光。AI 会列出需追加的颜色和滴数，保持自然色相并拉开明暗。")
                                .foregroundStyle(.secondary)
                            Text("AI 只使用当前选择的这一套原料。品牌标准色用于确定目标，不会作为调色原料。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            LazyVStack(spacing: 12) {
                                ForEach(paintSet.series) { series in
                                    Text("\(series.title) · \(series.paints.count) 色")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.top, 8)
                                    Text(series.previewNote)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .accessibilityIdentifier("paintPreviewNote-\(series.rawValue)")
                                    ForEach(series.paints) { paint in
                                        PaintDoseRow(paint: paint, drops: nil)
                                            .accessibilityIdentifier("availablePaint-\(paint.code)")
                                    }
                                }
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(AppPalette.cardSurface)
                .accessibilityIdentifier("mixingResultsScrollView")
                // New requests and their results start at the top, so progress is always visible.
                .id(requestID)
            }

            Divider()

            HStack {
                Text(canSave ? "三份配方将添加到当前项目" : "项目已删除或无法写入，可复制配方后关闭")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("复制三色配方") {
                    guard let result else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.formattedText, forType: .string)
                }
                .disabled(result == nil || isGenerating)

                Button("保存到项目") {
                    guard let result else { return }
                    if onSave(result) {
                        dismiss()
                    } else {
                        errorMessage = "保存未完成，项目可能已被删除或无法写入。你可以先复制配方。"
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.primary)
                .disabled(result == nil || isGenerating || !canSave)
                .accessibilityIdentifier("saveAIMixingButton")
            }
            .padding(16)
        }
        .frame(width: 900, height: 680)
        .background(AppPalette.canvas)
        // 任一输入或套装变更都使旧配方失效；处理系统取色器仍可能异步返回的修改。
        .onChange(of: redText) { _ in clearResult() }
        .onChange(of: greenText) { _ in clearResult() }
        .onChange(of: blueText) { _ in clearResult() }
        .onChange(of: inputMode) { _ in clearResult() }
        .onChange(of: paintSet) { _ in clearResult() }
        .onChange(of: blendEntries) { _ in clearResult() }
        .onChange(of: referenceSeries) { _ in
            selectedPaintCode = nil
            paintSearchText = ""
            clearResult()
        }
        .onChange(of: selectedPaintCode) { _ in clearResult() }
        .onDisappear(perform: cancelGeneration)
    }

    // MARK: - 输入与操作区域
    /// 先选实际原料套装，再按模式展示目标输入和生成控制。
    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("调色原料").font(.headline)
                Picker("调色原料", selection: $paintSet) {
                    ForEach(MixingPaintSet.selectable) { set in
                        Text(set.selectionTitle).tag(set)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityIdentifier("mixingPaintSetPicker")
                Text("仅使用所选套装；切换后需重新生成配方。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("输入方式", selection: $inputMode) {
                ForEach(MixingInputMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isGenerating)
            .accessibilityIdentifier("mixingInputMode")

            switch inputMode {
            case .single:
                singleColorInput
            case .reference:
                referenceColorInput
                    .disabled(isGenerating)
            case .blend:
                ColorBlendEditor(entries: $blendEntries)
                    .disabled(isGenerating)
            }

            generationControls
        }
    }

    /// 搜索商品参考色并展示其来源与近似限制，不将品牌参考漆加入原料。
    private var referenceColorInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择要用所选原料复现的标准色。")
                .font(.caption)
                .foregroundStyle(.secondary)
            PaintSeriesPicker(selection: $referenceSeries, identifierPrefix: "reference")

            TextField("搜索标准色号或名称", text: $paintSearchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("referencePaintSearchField")

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(referenceSeries.matchingPaints(paintSearchText)) { paint in
                        Button {
                            selectedPaintCode = paint.code
                        } label: {
                            HStack {
                                PaintDoseRow(paint: paint, drops: nil)
                                if selectedPaintCode == paint.code {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppPalette.primary)
                                }
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedPaintCode == paint.code ? AppPalette.primaryContainer : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("选择标准色 \(paint.code) \(paint.mixingName)")
                        .accessibilityIdentifier("referencePaint-\(paint.code)")
                    }
                    if referenceSeries.matchingPaints(paintSearchText).isEmpty {
                        Text("未找到该色号，可切换漆系或改用 RGB 输入。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 156)
            .accessibilityIdentifier("referencePaintList")

            if let reference = selectedReference, let target = reference.previewTarget {
                RoundedRectangle(cornerRadius: 10)
                    .fill(target.color)
                    .frame(height: 48)
                Text("本色参考：\(reference.summary)")
                    .font(.caption.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("selectedReferencePaint")
                Text("屏幕预览 · \(target.description) · \(target.hex)")
                    .font(.caption.monospacedDigit())
                    .accessibilityIdentifier("referencePreviewRGB")
            } else {
                Text("请从色库中选择一个标准色。")
                    .font(.caption)
                    .foregroundStyle(AppPalette.primary)
            }
            Text("\(selectedReference?.previewNote ?? referenceSeries.previewNote) AI 会结合品牌、色号和名称，用所选套装配色。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 编辑单个 sRGB 目标，颜色预览与有效性提示实时同步。
    private var singleColorInput: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("本色（输入颜色）").font(.headline)
            RoundedRectangle(cornerRadius: 14)
                .fill(target?.color ?? .gray)
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(AppPalette.outlineVariant, lineWidth: 1)
                }
                .frame(height: 112)
                .accessibilityLabel("目标色预览")
                .accessibilityValue(target?.description ?? "RGB 输入无效")

            ColorPicker("选择颜色", selection: selectedColor, supportsOpacity: false)
                .disabled(isGenerating)
                .accessibilityIdentifier("mixingColorPicker")

            HStack(spacing: 10) {
                channelField("R", text: $redText)
                channelField("G", text: $greenText)
                channelField("B", text: $blueText)
            }
            .disabled(isGenerating)

            Text(target.map { "sRGB · \($0.hex)" } ?? "请输入 0～255 之间的 RGB 整数")
                .font(.caption.monospacedDigit())
                .foregroundStyle(target == nil ? AppPalette.primary : AppPalette.onSurfaceVariant)
                .accessibilityIdentifier("mixingRGBStatus")
        }
    }

    /// 展示当前生成来源和等待信息，按输入、配置和项目可写状态控制生成按钮。
    private var generationControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("本色 200 滴 · 阴影/高光各取 20 滴追加").font(.headline)
                Text((result?.base.model ?? (isGenerating ? activeModel : nil) ?? configuration.model).summary)
                    .accessibilityIdentifier("mixingModelSummary")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Button(action: generate) {
                Label(inputMode == .blend ? "AI 合成并调色" : (result == nil ? "生成三色配方" : "重新生成三色"), systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppPalette.primary)
            .controlSize(.large)
            .disabled(!hasValidInput || isGenerating || !configuration.isValid || !canSave)
            .accessibilityIdentifier("generateMixingButton")

            Text(MixingRecipe.accuracyNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !configuration.isValid {
                Text("请先在系统设置中填写模型 ID。")
                    .font(.caption)
                    .foregroundStyle(AppPalette.primary)
            }
            Text("模型与推理强度可在“系统设置 → AI 配置”中修改。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    /// 为 RGB 通道提供统一文本输入和可访问标识，解析由 MixingTarget 负责。
    private func channelField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.medium))
            TextField("0–255", text: text)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("目标 \(label)")
                .accessibilityIdentifier("mixing\(label)Field")
        }
    }

    // MARK: - 生成生命周期
    /// 输入变更时清空旧结果及错误，并取消仍运行的请求。
    private func clearResult() {
        result = nil
        activeModel = nil
        errorMessage = nil
        // Also handles system color-panel changes arriving while a request is running.
        if isGenerating { cancelGeneration() }
    }

    /// 对输入、套装和配置取快照，再调用相应生成器并验证返回来源一致。
    private func generate() {
        guard hasValidInput, !isGenerating, configuration.isValid, canSave else { return }
        let submittedTarget = target
        let submittedReference = activeReference
        let submittedPaintSet = paintSet
        let submittedBlend = inputMode == .blend ? blendRequest : nil
        result = nil
        errorMessage = nil
        let id = UUID()
        requestID = id
        // 运行中的请求保持启动时的配置，设置窗口后续改动仅影响下一次生成。
        // A running request retains the settings that were selected when it started.
        let requestConfiguration = configuration
        activeModel = configuration.model

        generationTask = Task { @MainActor in
            do {
                let recipe: MixingPalette
                if let submittedBlend {
                    recipe = try await generateBlend(submittedBlend, submittedPaintSet, requestConfiguration)
                } else if let submittedTarget {
                    recipe = try await generateRecipe(submittedTarget, submittedReference, submittedPaintSet, requestConfiguration)
                } else {
                    throw MixingError.invalidRecipe("请输入有效颜色。")
                }
                try Task.checkCancellation()
                // 身份和套装都要匹配，防止较晚到达的旧响应覆盖新任务。
                guard requestID == id, paintSet == submittedPaintSet else { return }
                guard recipe.recipes.allSatisfy({
                    $0.paintSet == submittedPaintSet && $0.referencePaint == submittedReference
                }) else {
                    throw MixingError.invalidRecipe("配方必须只使用当前所选套装，并保留所选参考标准，请重新生成。")
                }
                result = recipe
                activeModel = recipe.base.model
            } catch is CancellationError {
                // Cancelled responses must never replace the current target's result.
            } catch {
                guard requestID == id else { return }
                errorMessage = error.localizedDescription
            }
            if requestID == id {
                requestID = nil
                generationTask = nil
            }
        }
    }

    /// 取消任务并立即撤销请求身份，后续结果即使到达也不能被采用。
    private func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        requestID = nil
    }
}

// MARK: - 可复用的配方展示
/// 三色选择器及所选角色的配方详情。
struct MixingPaletteDetails: View {
    let palette: MixingPalette
    @State private var selectedRole: MixingRole = .base

    /// 并列展示三种目标色，选中角色后切换该份用量和步骤。
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("三色配方 · 从本色追加调制")
                .font(.headline)
            Text(palette.preparationSummary + "点击色块查看用量与步骤。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(MixingRole.allCases) { role in
                    let recipe = palette.recipe(for: role)
                    Button {
                        selectedRole = role
                    } label: {
                        VStack(spacing: 7) {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(recipe.target.color)
                                .frame(height: 44)
                            Text(role.title).font(.subheadline.weight(.semibold))
                            Text(recipe.target.hex).font(.caption.monospaced())
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedRole == role ? AppPalette.primaryContainer : AppPalette.canvas)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(selectedRole == role ? AppPalette.primary : AppPalette.outlineVariant)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("查看\(role.title)配方")
                    .accessibilityValue("\(recipe.target.description)，\(recipe.quantitySummary)")
                    .accessibilityAddTraits(selectedRole == role ? .isSelected : [])
                    .accessibilityIdentifier("mixingRole-\(role.rawValue)")
                }
            }

            Divider()
            MixingRecipeDetails(recipe: palette.recipe(for: selectedRole))
                .id(selectedRole)
        }
    }
}

/// 单份配方详情，生成结果页与已保存配方窗口共用。
struct MixingRecipeDetails: View {
    let recipe: MixingRecipe

    /// 依次显示目标、原料、参考来源、用量、步骤和试调说明。
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(recipe.target.color)
                    .frame(width: 48, height: 48)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10).strokeBorder(.gray.opacity(0.2))
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(recipe.role.title) · \(recipe.response.name)")
                        .font(.title2.weight(.semibold))
                        .accessibilityIdentifier("mixingRoleTitle")
                    Text("\(recipe.role == .base ? (recipe.referencePaint != nil ? "参考色预览" : (recipe.synthesis == nil ? "输入本色" : "AI 合成本色")) : "AI 建议目标") \(recipe.target.description) · \(recipe.target.hex)")
                        .accessibilityIdentifier("mixingTargetRGB")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text("调色用漆：\(recipe.paintsTitle)")
                .font(.subheadline.weight(.medium))
                .accessibilityIdentifier("savedMixingPaintSeries")

            if let reference = recipe.referencePaint {
                Text("本色参考标准：\(reference.summary)")
                    .font(.subheadline)
                    .accessibilityIdentifier("savedReferencePaint")
                Text("\(reference.previewNote) 实际使用 \(recipe.paintsTitle) 调制。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let synthesis = recipe.synthesis {
                ColorBlendSynthesisDetails(synthesis: synthesis)
                Divider()
            }

            if let portion = recipe.basePortion {
                Text("本色底料：\(portion.response.name) · \(portion.drops) 滴 · \(portion.target.hex)")
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("mixingBasePortion")
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(recipe.basePortion == nil ? "各色用量" : "需要追加的颜色")
                    .font(.headline)
                Text(recipe.quantitySummary).font(.subheadline.monospacedDigit())
                    .accessibilityIdentifier("mixingTotal")
            }

            if recipe.basePortion != nil && recipe.ingredientDrops == 0 {
                Text("无需追加，已到达此方向的黑/白边界。")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(recipe.displayedPaints) { paint in
                    PaintDoseRow(paint: paint, drops: recipe.drops(for: paint.code))
                        .accessibilityIdentifier("recipePaint-\(paint.code)")
                }
            }

            Divider()
            Text("具体怎么调").font(.headline)
            if let instruction = recipe.basePortionInstruction {
                Text("1. " + instruction)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("mixingBaseStep")
            }
            ForEach(Array(recipe.response.steps.enumerated()), id: \.offset) { index, step in
                let paint = recipe.paints.first { $0.code == step.paintCode }
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(index + (recipe.basePortion == nil ? 1 : 2)). 加入 \(paint?.series.title ?? "") · \(paint?.chineseName ?? step.paintCode) #\(step.paintCode) · \(step.drops) 滴")
                        .font(.subheadline.weight(.semibold))
                    Text(step.instruction)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
            Text("试调说明").font(.headline)
            Text(recipe.response.notes)
            if let base = recipe.basePreparation {
                // 随伴随色保存完整本色快照，独立查看时仍能找回配制依据。
                DisclosureGroup("查看本色原配方（先调 200 滴，再取 20 滴）") {
                    Text(base.formattedText)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                        .accessibilityIdentifier("mixingBasePreparation")
                }
            }
            Text(MixingRecipe.accuracyNote)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(recipe.model.summary)
                .accessibilityIdentifier("savedMixingModelSummary")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .textSelection(.enabled)
    }
}

/// 商品色样与可选滴数行，兼用于可用原料目录和配方用量表。
private struct PaintDoseRow: View {
    let paint: CatalogPaint
    /// nil 表示仅展示可用原料；0 表示本份配方明确未使用该颜料。
    let drops: Int?

    /// 色块保留来源提示，并让辅助功能将名称、系列和滴数作为一项朗读。
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(.sRGB, red: paint.red / 255, green: paint.green / 255, blue: paint.blue / 255))
                .frame(width: 28, height: 28)
                .overlay {
                    RoundedRectangle(cornerRadius: 5).strokeBorder(.gray.opacity(0.2))
                }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(paint.chineseName) · #\(paint.code)")
                    .font(.subheadline.weight(.medium))
                Text("\(paint.series.title) · \(paint.name)").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if let drops {
                Text("\(drops) 滴")
                    .font(.body.monospacedDigit().weight(drops > 0 ? .semibold : .regular))
                    .foregroundStyle(drops > 0 ? AppPalette.onSurface : AppPalette.onSurfaceVariant)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(paint.ingredientName)，色号 \(paint.code)，\(drops.map { "\($0) 滴" } ?? "可用调色原料")")
        .help("\(paint.rgbDescription)\n\(paint.previewNote)")
    }
}

/// 在项目颜色卡片中打开相应角色的已保存配方。
struct SavedMixingRecipeButton: View {
    let recipe: MixingRecipe
    let onOpen: () -> Void

    /// 用角色名称和统一计量标识呈现查看入口。
    var body: some View {
        Button(action: onOpen) {
            Label("查看\(recipe.role.title) · \(recipe.preparedTotalDrops) 滴", systemImage: "drop")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("viewMixingRecipeButton")
        .accessibilityLabel("查看\(recipe.role.title)配方")
    }
}

/// 将领域层的整数目标色适配为 SwiftUI 预览，不在数据模型中引入界面依赖。
extension MixingTarget {
    /// 显式采用 sRGB 色彩空间，通道由 0...255 换算为 0...1。
    var color: Color {
        Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }
}
