import Foundation

/// A catalog color to reproduce, separate from the paints used in a recipe.
struct PaintReference: Codable, Equatable, Sendable {
    let series: PaintSeries
    let paintCode: String
    // Freeze the preview so a catalog update cannot invalidate an existing recipe.
    private let previewTargetSnapshot: MixingTarget?

    init(series: PaintSeries, paintCode: String) {
        self.series = series
        self.paintCode = paintCode
        previewTargetSnapshot = Self.catalogPreview(series: series, paintCode: paintCode)
    }

    var paint: CatalogPaint? { series.paints.first { $0.code == paintCode } }
    var previewTarget: MixingTarget? { previewTargetSnapshot }

    var summary: String {
        "\(series.title) · #\(paintCode) · \(paint?.mixingName ?? paintCode)"
    }

    var previewNote: String {
        if previewTargetSnapshot != Self.catalogPreview(series: series, paintCode: paintCode) {
            return "参考 RGB 保留保存时的预览值，当前色库已更新。实际成色请以干燥小样为准。"
        }
        return series.previewNote
    }

    private enum CodingKeys: String, CodingKey {
        case series, paintCode, previewTargetSnapshot
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        series = try values.decode(PaintSeries.self, forKey: .series)
        paintCode = try values.decode(String.self, forKey: .paintCode)
        previewTargetSnapshot = try values.decodeIfPresent(MixingTarget.self, forKey: .previewTargetSnapshot)
            ?? (series == .goldenFluid ? Self.legacyFluidPreviews[paintCode] : nil)
            ?? Self.catalogPreview(series: series, paintCode: paintCode)
        try validate()
    }

    func validate() throws {
        guard paint != nil else {
            throw MixingError.invalidRecipe("参考色号不在所选品牌色库中，请重新选择。")
        }
        guard let previewTarget,
              [previewTarget.red, previewTarget.green, previewTarget.blue].allSatisfy({ (0...255).contains($0) }) else {
            throw MixingError.invalidRecipe("参考色预览 RGB 超出 0～255。")
        }
    }

    func validate(target: MixingTarget) throws {
        try validate()
        guard previewTarget == target else {
            throw MixingError.invalidRecipe("参考色与预览颜色不一致，请重新选择标准色，或使用 RGB 输入。")
        }
    }

    static func forColor(_ color: ColorInfo) -> PaintReference? {
        let target = MixingTarget(red: color.red, green: color.green, blue: color.blue)
        if let code = color.paintCode {
            let reference = PaintReference(series: PaintSeries.forColor(color), paintCode: code)
            if reference.previewTarget == target { return reference }
        }
        // A shadow/highlight must not be mistaken for the original reference color.
        if let reference = color.mixingRecipe?.referencePaint, reference.previewTarget == target {
            return reference
        }
        return nil
    }

    private static func catalogPreview(series: PaintSeries, paintCode: String) -> MixingTarget? {
        series.paints.first { $0.code == paintCode }.map {
            MixingTarget(red: $0.red, green: $0.green, blue: $0.blue)
        }
    }

    // v1.0.7–1.0.8 stored only series/code. All three tones must restore the same
    // original reference, even though only the base recipe target equals its RGB.
    private static let legacyFluidPreviews: [String: MixingTarget] = [
        "2009": MixingTarget(red: 244, green: 229, blue: 43),
        "2008": MixingTarget(red: 235, green: 197, blue: 45),
        "2210": MixingTarget(red: 218, green: 53, blue: 37),
        "2305": MixingTarget(red: 167, green: 22, blue: 88),
        "2260": MixingTarget(red: 21, green: 40, blue: 100),
        "2255": MixingTarget(red: 12, green: 64, blue: 106),
        "2270": MixingTarget(red: 7, green: 80, blue: 71),
        "2275": MixingTarget(red: 36, green: 93, blue: 55),
        "2040": MixingTarget(red: 32, green: 32, blue: 32),
        "2380": MixingTarget(red: 243, green: 244, blue: 240),
        "2276": MixingTarget(red: 236, green: 81, blue: 39),
        "2150": MixingTarget(red: 48, green: 32, blue: 62),
        "2407": MixingTarget(red: 179, green: 138, blue: 59)
    ]
}
