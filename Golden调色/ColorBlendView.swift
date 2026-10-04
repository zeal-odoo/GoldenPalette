import SwiftUI
import AppKit

enum MixingInputMode: String, CaseIterable, Identifiable {
    case single
    case blend

    var id: String { rawValue }
    var title: String { self == .single ? "单个颜色" : "多色合成" }
}

struct ColorBlendEntry: Identifiable, Equatable {
    let id = UUID()
    var redText: String
    var greenText: String
    var blueText: String
    var percentageText: String

    init(target: MixingTarget, percentage: Double) {
        redText = String(target.red)
        greenText = String(target.green)
        blueText = String(target.blue)
        percentageText = String(format: "%g", percentage)
    }

    var target: MixingTarget? {
        MixingTarget(redText: redText, greenText: greenText, blueText: blueText)
    }

    var source: ColorBlendSource? {
        guard let target,
              let percentage = Double(percentageText.trimmingCharacters(in: .whitespacesAndNewlines)),
              percentage.isFinite, percentage > 0, percentage <= 100 else { return nil }
        return ColorBlendSource(target: target, percentage: percentage)
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
            Text("填写多个 RGB 和占比，由 AI 合成一个本色目标。")
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
                entries.append(ColorBlendEntry(target: .initial, percentage: 25))
            } label: {
                Label("添加一组 RGB", systemImage: "plus")
            }
            .accessibilityIdentifier("addBlendSourceButton")

            if let request = ColorBlendEntry.request(from: entries) {
                Text("占比合计 \(request.totalPercentageText)% · 按相对比例换算为 100%")
                    .accessibilityIdentifier("blendPercentageStatus")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("至少两组有效颜色；RGB 为 0～255 整数，占比大于 0 且不超过 100%。")
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
                ColorPicker("颜色 \(index + 1)", selection: selectedColor, supportsOpacity: false)
                    .accessibilityIdentifier("blendColorPicker-\(index)")
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

            HStack(spacing: 8) {
                channel("R", text: $entry.redText)
                channel("G", text: $entry.greenText)
                channel("B", text: $entry.blueText)
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
                Text("\(index + 1). \(source.target.description) · \(source.percentageText)%")
                    .font(.caption.monospacedDigit())
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
