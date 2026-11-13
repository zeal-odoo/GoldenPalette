// 商品参考色的稳定身份与预览快照。
// 将“要复现的目标色”与“实际参与调色的原料”分开，并兼容色库更新前的配方。
import Foundation

/// 描述目标商品色，系列和色号共同确定身份。
/// A catalog color to reproduce, separate from the paints used in a recipe.
struct PaintReference: Codable, Equatable, Sendable {
    let series: PaintSeries
    let paintCode: String
    // Freeze the preview so a catalog update cannot invalidate an existing recipe.
    /// 固定创建时的预览 RGB，避免日后色库更新改变已保存配方的目标。
    private let previewTargetSnapshot: MixingTarget?

    /// 创建新参考色时从当前色库捕获预览快照。
    init(series: PaintSeries, paintCode: String) {
        self.series = series
        self.paintCode = paintCode
        previewTargetSnapshot = Self.catalogPreview(series: series, paintCode: paintCode)
    }

    /// 在所属系列中查找商品元数据，避免跨系列重复色号导致误匹配。
    var paint: CatalogPaint? { series.paints.first { $0.code == paintCode } }
    /// 供界面及配方校验使用的保存时预览，而非实时色库值。
    var previewTarget: MixingTarget? { previewTargetSnapshot }

    /// 保留系列、色号和中英文名，方便对照实际商品。
    var summary: String {
        "\(series.title) · #\(paintCode) · \(paint?.mixingName ?? paintCode)"
    }

    /// 色库已更新时说明正在使用历史预览，否则沿用商品的近似色说明。
    var previewNote: String {
        if previewTargetSnapshot != Self.catalogPreview(series: series, paintCode: paintCode) {
            return "参考 RGB 保留保存时的预览值，当前色库已更新。实际成色请以干燥小样为准。"
        }
        return paint?.previewNote ?? series.previewNote
    }

    /// 快照作为可选兼容字段，与旧版仅有系列和色号的存档共存。
    private enum CodingKeys: String, CodingKey {
        case series, paintCode, previewTargetSnapshot
    }

    /// 优先恢复已保存快照，其次恢复历史预览，最后才使用当前色库。
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        series = try values.decode(PaintSeries.self, forKey: .series)
        paintCode = try values.decode(String.self, forKey: .paintCode)
        previewTargetSnapshot = try values.decodeIfPresent(MixingTarget.self, forKey: .previewTargetSnapshot)
            ?? Self.legacyPreview(series: series, paintCode: paintCode)
            ?? Self.catalogPreview(series: series, paintCode: paintCode)
        try validate()
    }

    /// 确认商品存在且预览 RGB 有效；不把屏幕预览视作实测颜色。
    func validate() throws {
        guard paint != nil else {
            throw MixingError.invalidRecipe("参考色号不在所选品牌色库中，请重新选择。")
        }
        guard let previewTarget,
              [previewTarget.red, previewTarget.green, previewTarget.blue].allSatisfy({ (0...255).contains($0) }) else {
            throw MixingError.invalidRecipe("参考色预览 RGB 超出 0～255。")
        }
    }

    /// 在生成或恢复本色时额外检查参考色与目标 RGB 一致。
    func validate(target: MixingTarget) throws {
        try validate()
        guard previewTarget == target else {
            throw MixingError.invalidRecipe("参考色与预览颜色不一致，请重新选择标准色，或使用 RGB 输入。")
        }
    }

    /// 从项目颜色恢复参考身份；RGB 已变化的阴影、高光或手工颜色不会误认成本色。
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

    /// 从当前系列目录提取预览 RGB，供新建引用使用。
    private static func catalogPreview(series: PaintSeries, paintCode: String) -> MixingTarget? {
        series.paints.first { $0.code == paintCode }.map {
            MixingTarget(red: $0.red, green: $0.green, blue: $0.blue)
        }
    }

    /// 无快照的旧引用需恢复当时的预览，避免色库更新使原配方失效。
    // References without a snapshot predate the sourced color update. Restore the
    // original reference for every tone, rather than substituting the new catalog RGB.
    private static func legacyPreview(series: PaintSeries, paintCode: String) -> MixingTarget? {
        if series == .goldenFluid { return legacyFluidPreviews[paintCode] }
        guard let paint = series.paints.first(where: { $0.code == paintCode }),
              let rgb = Int(paint.legacyHex, radix: 16) else { return nil }
        return MixingTarget(
            red: Double((rgb >> 16) & 0xFF), green: Double((rgb >> 8) & 0xFF), blue: Double(rgb & 0xFF)
        )
    }

    // 保留早期 Fluid 预览作为迁移数据；这些值不能随当前色库一起更新。
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
