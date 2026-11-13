// 比例合色的界面草稿与输入组件。
// 文本草稿允许暂时无效，只有所有行通过校验后才转换为领域层请求。
import SwiftUI
import AppKit

/// AI 调色的三种目标输入方式。
enum MixingInputMode: String, CaseIterable, Identifiable {
    case single
    case reference
    case blend

    /// 原始值作为分段选择器的稳定身份。
    var id: String { rawValue }
    /// 各种输入方式的界面名称。
    var title: String {
        switch self {
        case .single: return "单个颜色"
        case .reference: return "品牌标准色"
        case .blend: return "多色合成"
        }
    }
}

/// 每一行比例输入可独立选择 RGB 或商品参考色。
enum ColorBlendInputMode: String, CaseIterable, Identifiable {
    case rgb
    case reference

    /// 为每行的输入方式选择器提供稳定身份。
    var id: String { rawValue }
    /// 输入方式的简短显示名称。
    var title: String { self == .rgb ? "RGB" : "品牌标准色" }
}

/// 尚在编辑的一行输入；字符串可保留空值等中间状态，不强制即时转成数字。
struct ColorBlendEntry: Identifiable, Equatable {
    /// 删除和插入行时以 UUID 识别草稿，避免依赖会变化的数组下标。
    let id = UUID()
    var redText: String
    var greenText: String
    var blueText: String
    var percentageText: String
    var inputMode: ColorBlendInputMode = .rgb
    /// 通过专用方法修改系列，以确保同步清除旧商品色号。
    private(set) var referenceSeries: PaintSeries = .tamiyaAcrylic
    var selectedPaintCode: String?

    /// 从一个有效颜色和初始占比创建文本草稿。
    init(target: MixingTarget, percentage: Double) {
        redText = String(target.red)
        greenText = String(target.green)
        blueText = String(target.blue)
        percentageText = String(format: "%g", percentage)
    }

    /// 只有标准色模式且已选色号时才创建商品引用。
    var referencePaint: PaintReference? {
        guard inputMode == .reference, let selectedPaintCode else { return nil }
        return PaintReference(series: referenceSeries, paintCode: selectedPaintCode)
    }

    /// 根据模式读取商品预览，或严格解析三个 RGB 文本通道。
    var target: MixingTarget? {
        if inputMode == .reference { return referencePaint?.previewTarget }
        return MixingTarget(redText: redText, greenText: greenText, blueText: blueText)
    }

    /// 切换漆系时清空旧色号；共享编号不能跨漆系自动沿用。
    mutating func selectReferenceSeries(_ series: PaintSeries) {
        guard referenceSeries != series else { return }
        referenceSeries = series
        // Shared codes (e.g. X-1) must not silently carry across different paint systems.
        selectedPaintCode = nil
    }

    /// 将单行转换为有效参考色和占比，无效草稿返回 nil 供界面提示。
    var source: ColorBlendSource? {
        guard let target,
              let percentage = Double(percentageText.trimmingCharacters(in: .whitespacesAndNewlines)),
              percentage.isFinite, percentage > 0, percentage <= 100 else { return nil }
        return ColorBlendSource(target: target, percentage: percentage, referencePaint: referencePaint)
    }

    /// 必须全部输入行都有效；不能通过 compactMap 静默忽略用户尚未填完的行。
    static func request(from entries: [ColorBlendEntry]) -> ColorBlendRequest? {
        let sources = entries.compactMap(\.source)
        guard sources.count == entries.count else { return nil }
        return try? ColorBlendRequest(sources: sources)
    }
}

/// 管理多行合色输入的增删，并说明占比按相对关系归一化。
struct ColorBlendEditor: View {
    @Binding var entries: [ColorBlendEntry]

    /// 始终保留至少两组输入，新行沿用上一行的模式和系列。
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("每组可输入 RGB 或选择品牌标准色，再填写占比，由 AI 合成一个本色目标。")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach($entries) { $entry in
                let entryID = entry.id
                let index = entries.firstIndex { $0.id == entryID } ?? 0
                ColorBlendInputRow(entry: $entry, index: index, canRemove: entries.count > 2) {
                    entries.removeAll { $0.id == entryID }
                }
            }

            Button {
                var entry = ColorBlendEntry(target: .initial, percentage: 25)
                if let previous = entries.last {
                    entry.inputMode = previous.inputMode
                    entry.selectReferenceSeries(previous.referenceSeries)
                }
                entries.append(entry)
            } label: {
                Label("添加一组颜色", systemImage: "plus")
            }
            .accessibilityIdentifier("addBlendSourceButton")

            if let request = ColorBlendEntry.request(from: entries) {
                Text("占比合计 \(request.totalPercentageText)% · 按相对比例换算为 100%")
                    .accessibilityIdentifier("blendPercentageStatus")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("至少两组颜色；每组须输入 0～255 的整数 RGB 或选择品牌标准色，占比大于 0 且不超过 100%。")
                    .font(.caption)
                    .foregroundStyle(AppPalette.primary)
                    .accessibilityIdentifier("blendInputError")
            }
        }
    }
}

/// 编辑一组参考色及占比，行删除动作由父视图按 UUID 处理。
private struct ColorBlendInputRow: View {
    @Binding var entry: ColorBlendEntry
    let index: Int
    let canRemove: Bool
    let onRemove: () -> Void

    /// 将系统取色器返回的颜色转换为 sRGB 后同步到该行的文本通道。
    private var selectedColor: Binding<Color> {
        Binding(
            get: { entry.target?.color ?? .gray },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                let target = MixingTarget(
                    red: rgb.redComponent * 255, green: rgb.greenComponent * 255, blue: rgb.blueComponent * 255
                )
                entry.redText = String(target.red)
                entry.greenText = String(target.green)
                entry.blueText = String(target.blue)
            }
        )
    }

    /// 按行模式展示 RGB 或商品参考输入，并保留独立占比字段。
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if entry.inputMode == .rgb {
                    ColorPicker("颜色 \(index + 1)", selection: selectedColor, supportsOpacity: false)
                        .accessibilityIdentifier("blendColorPicker-\(index)")
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(entry.target?.color ?? .gray)
                        .frame(width: 20, height: 20)
                    Text("颜色 \(index + 1)")
                }
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(!canRemove)
                .help("删除颜色 \(index + 1)")
                .accessibilityLabel("删除合成输入颜色 \(index + 1)")
                .accessibilityIdentifier("removeBlendSource-\(index)")
            }

            Picker("输入方式", selection: $entry.inputMode) {
                ForEach(ColorBlendInputMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("blendInputMode-\(index)")

            if entry.inputMode == .reference {
                ColorBlendReferenceInput(entry: $entry, index: index)
            } else {
                HStack(spacing: 8) {
                    channel("R", text: $entry.redText)
                    channel("G", text: $entry.greenText)
                    channel("B", text: $entry.blueText)
                }
            }

            HStack {
                Text("占比").font(.caption)
                TextField("百分比", text: $entry.percentageText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 76)
                    .accessibilityLabel("颜色 \(index + 1) 占比")
                    .accessibilityIdentifier("blendPercentageField-\(index)")
                Text("%").font(.caption)
                Spacer()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(AppPalette.cardSurface))
    }

    /// 生成带行号标识的通道输入框，便于辅助功能和自动化定位。
    private func channel(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2)
            TextField("0–255", text: text)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("颜色 \(index + 1) \(label)")
                .accessibilityIdentifier("blend\(label)Field-\(index)")
        }
    }
}

/// 一行中的商品色选择区，搜索仅改变候选展示，不隐式更改已选输入。
private struct ColorBlendReferenceInput: View {
    @Binding var entry: ColorBlendEntry
    let index: Int
    @State private var searchText = ""

    /// 把系列选择接入草稿的切换方法，同时清除当前搜索词。
    private var series: Binding<PaintSeries> {
        Binding(
            get: { entry.referenceSeries },
            set: {
                entry.selectReferenceSeries($0)
                searchText = ""
            }
        )
    }

    /// 使用当前参考系列的统一名称/色号搜索规则。
    private var matchingPaints: [CatalogPaint] {
        entry.referenceSeries.matchingPaints(searchText)
    }

    /// 筛选结果外的已选商品仍保留在 Picker 选项中，保证 selection 始终有对应 tag。
    private var displayedPaints: [CatalogPaint] {
        let matches = matchingPaints
        // Keep the selected tag available while filtering; searching alone doesn't change the input.
        if let selected = entry.referencePaint?.paint, !matches.contains(selected) {
            return [selected] + matches
        }
        return matches
    }

    /// 联动品牌、系列与色号，并展示选中色的预览说明。
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaintSeriesPicker(selection: series, identifierPrefix: "blend\(index)")

            TextField("搜索色号或名称", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("blendPaintSearchField-\(index)")

            Picker("标准色", selection: $entry.selectedPaintCode) {
                Text("请选择色号").tag(String?.none)
                ForEach(displayedPaints) { paint in
                    Text("\(paint.code) · \(paint.chineseName)").tag(Optional(paint.code))
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("blendPaintCodePicker-\(index)")

            if matchingPaints.isEmpty {
                Text("未找到匹配色号，请修改搜索条件。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let reference = entry.referencePaint, let target = reference.previewTarget {
                Text("\(reference.summary)\n\(target.description) · \(target.hex)")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("blendSelectedReference-\(index)")
                Text(reference.previewNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("请选择这一组的品牌标准色。")
                    .font(.caption)
                    .foregroundStyle(AppPalette.primary)
            }
        }
    }
}

/// 保存后的合色来源说明，展示原始输入、估算目标和 AI 的分析文字。
struct ColorBlendSynthesisDetails: View {
    let synthesis: ColorBlendSynthesis

    /// 使用保存的来源快照展示结果，避免后续输入修改影响历史配方说明。
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI 合成目标色").font(.headline)
            HStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(synthesis.target.color)
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(synthesis.target.description)
                        .accessibilityIdentifier("blendTargetRGB")
                    Text(synthesis.target.hex)
                }
                .font(.callout.monospacedDigit())
            }
            ForEach(Array(synthesis.sources.enumerated()), id: \.offset) { index, source in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(index + 1). \(source.colorDescription) · \(source.percentageText)%")
                        .font(.caption.monospacedDigit())
                        .accessibilityIdentifier("blendSourceSummary-\(index)")
                    if let reference = source.referencePaint {
                        Text(reference.previewNote)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            Text("输入按相对比例换算为 100%。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(synthesis.explanation)
                .accessibilityIdentifier("blendExplanation")
                .font(.callout)
        }
        .textSelection(.enabled)
    }
}
