import SwiftUI
import AppKit

@MainActor
struct AIMixingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var redText: String
    @State private var greenText: String
    @State private var blueText: String
    @State private var inputMode: MixingInputMode
    @State private var paintSet: MixingPaintSet
    @State private var blendEntries: [ColorBlendEntry]
    @State private var result: MixingPalette?
    @State private var errorMessage: String?
    @State private var requestID: UUID?
    @State private var generationTask: Task<Void, Never>?
    @State private var activeModel: AIModelSelection?
    @State private var referenceSeries: PaintSeries
    @State private var selectedPaintCode: String?
    @State private var paintSearchText = ""

    let projectName: String
    let configuration: AIConfiguration
    let canSave: Bool
    let generateRecipe: MixingGenerator
    let generateBlend: BlendMixingGenerator
    let onSave: (MixingPalette) -> Bool

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

    private var selectedReference: PaintReference? {
        guard let selectedPaintCode else { return nil }
        return PaintReference(series: referenceSeries, paintCode: selectedPaintCode)
    }

    private var activeReference: PaintReference? {
        inputMode == .reference ? selectedReference : nil
    }

    private var target: MixingTarget? {
        if inputMode == .reference { return selectedReference?.previewTarget }
        return MixingTarget(redText: redText, greenText: greenText, blueText: blueText)
    }

    private var isGenerating: Bool { requestID != nil }

    private var blendRequest: ColorBlendRequest? { ColorBlendEntry.request(from: blendEntries) }
    private var hasValidInput: Bool { inputMode == .blend ? blendRequest != nil : target != nil }

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

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI 调色 · \(projectName)")
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                        .accessibilityIdentifier("mixingProjectTitle")
                    Text("调色用漆：\(paintSet.title) · \(paintSet.paints.count) 色 · 三份各 200 滴")
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
                            Text("AI 会生成本色、阴影色和高光色三份配方，逐色列出用量，每份各 200 滴。")
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

    private var generationControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("每色 200 滴 · 三色共 600 滴").font(.headline)
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

    private func channelField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.medium))
            TextField("0–255", text: text)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("目标 \(label)")
                .accessibilityIdentifier("mixing\(label)Field")
        }
    }

    private func clearResult() {
        result = nil
        activeModel = nil
        errorMessage = nil
        // Also handles system color-panel changes arriving while a request is running.
        if isGenerating { cancelGeneration() }
    }

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

    private func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        requestID = nil
    }
}

struct MixingPaletteDetails: View {
    let palette: MixingPalette
    @State private var selectedRole: MixingRole = .base

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("三色配方 · 每色 200 滴")
                .font(.headline)
            Text("三份分别调制，共 600 滴。点击色块查看该色的用量与步骤。")
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
                    .accessibilityValue("\(recipe.target.description)，200 滴")
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

struct MixingRecipeDetails: View {
    let recipe: MixingRecipe

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

            HStack {
                Text("各色用量").font(.headline)
                Spacer()
                Text("合计 200 滴").font(.headline.monospacedDigit())
                    .accessibilityIdentifier("mixingTotal")
            }

            VStack(spacing: 10) {
                ForEach(recipe.displayedPaints) { paint in
                    PaintDoseRow(paint: paint, drops: recipe.drops(for: paint.code))
                        .accessibilityIdentifier("recipePaint-\(paint.code)")
                }
            }

            Divider()
            Text("具体怎么调").font(.headline)
            ForEach(Array(recipe.response.steps.enumerated()), id: \.offset) { index, step in
                let paint = recipe.paints.first { $0.code == step.paintCode }
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(index + 1). 加入 \(paint?.series.title ?? "") · \(paint?.chineseName ?? step.paintCode) #\(step.paintCode) · \(step.drops) 滴")
                        .font(.subheadline.weight(.semibold))
                    Text(step.instruction)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
            Text("试调说明").font(.headline)
            Text(recipe.response.notes)
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

private struct PaintDoseRow: View {
    let paint: CatalogPaint
    let drops: Int?

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

struct SavedMixingRecipeButton: View {
    let recipe: MixingRecipe
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Label("查看\(recipe.role.title) · 200 滴", systemImage: "drop")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("viewMixingRecipeButton")
        .accessibilityLabel("查看\(recipe.role.title)配方")
    }
}

extension MixingTarget {
    var color: Color {
        Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }
}
