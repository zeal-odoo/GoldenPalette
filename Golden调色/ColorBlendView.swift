import SwiftUI
import AppKit

enum MixingInputMode: String, CaseIterable, Identifiable {
    case single
    case reference
    case blend

    var id: String { rawValue }
    var title: String {
        switch self {
        case .single: return "单个颜色"
        case .reference: return "品牌标准色"
        case .blend: return "多色合成"
        }
    }
}

enum ColorBlendInputMode: String, CaseIterable, Identifiable {
    case rgb
    case reference

    var id: String { rawValue }
    var title: String { self == .rgb ? "RGB" : "品牌标准色" }
}

struct ColorBlendEntry: Identifiable, Equatable {
    let id = UUID()
    var redText: String
    var greenText: String
    var blueText: String
    var percentageText: String
    var inputMode: ColorBlendInputMode = .rgb
    private(set) var referenceSeries: PaintSeries = .tamiyaAcrylic
    var selectedPaintCode: String?

    init(target: MixingTarget, percentage: Double) {
        redText = String(target.red)
        greenText = String(target.green)
        blueText = String(target.blue)
        percentageText = String(format: "%g", percentage)
    }

    var referencePaint: PaintReference? {
        guard inputMode == .reference, let selectedPaintCode else { return nil }
        return PaintReference(series: referenceSeries, paintCode: selectedPaintCode)
    }

    var target: MixingTarget? {
        if inputMode == .reference { return referencePaint?.previewTarget }
        return MixingTarget(redText: redText, greenText: greenText, blueText: blueText)
    }

    mutating func selectReferenceSeries(_ series: PaintSeries) {
        guard referenceSeries != series else { return }
        referenceSeries = series
        // Shared codes (e.g. X-1) must not silently carry across different paint systems.
        selectedPaintCode = nil
    }

    var source: ColorBlendSource? {
        guard let target,
              let percentage = Double(percentageText.trimmingCharacters(in: .whitespacesAndNewlines)),
              percentage.isFinite, percentage > 0, percentage <= 100 else { return nil }
        return ColorBlendSource(target: target, percentage: percentage, referencePaint: referencePaint)
    }

    static func request(from entries: [ColorBlendEntry]) -> ColorBlendRequest? {
        let sources = entries.compactMap(\.source)
        guard sources.count == entries.count else { return nil }
        return try? ColorBlendRequest(sources: sources)
    }
}

struct ColorBlendEditor: View {
    @Binding var entries: [ColorBlendEntry]

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

private struct ColorBlendInputRow: View {
    @Binding var entry: ColorBlendEntry
    let index: Int
    let canRemove: Bool
    let onRemove: () -> Void

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

private struct ColorBlendReferenceInput: View {
    @Binding var entry: ColorBlendEntry
    let index: Int
    @State private var searchText = ""

    private var series: Binding<PaintSeries> {
        Binding(
            get: { entry.referenceSeries },
            set: {
                entry.selectReferenceSeries($0)
                searchText = ""
            }
        )
    }

    private var matchingPaints: [CatalogPaint] {
        entry.referenceSeries.matchingPaints(searchText)
    }

    private var displayedPaints: [CatalogPaint] {
        let matches = matchingPaints
        // Keep the selected tag available while filtering; searching alone doesn't change the input.
        if let selected = entry.referencePaint?.paint, !matches.contains(selected) {
            return [selected] + matches
        }
        return matches
    }

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

struct ColorBlendSynthesisDetails: View {
    let synthesis: ColorBlendSynthesis

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
