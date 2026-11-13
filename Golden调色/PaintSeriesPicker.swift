// 复用的品牌与漆系联动选择器，供颜色编辑、标准色调色和比例合色使用。
import SwiftUI

/// 只维护最终系列选择，品牌由系列派生，避免两份状态不一致。
struct PaintSeriesPicker: View {
    @Binding var selection: PaintSeries
    /// 给不同使用位置生成独立的辅助功能标识，便于自动化定位。
    let identifierPrefix: String

    /// 切换品牌时重置到该品牌默认系列，防止保留不属于新品牌的选择。
    private var brand: Binding<PaintBrand> {
        Binding(
            get: { selection.brand },
            set: { selection = $0.defaultSeries }
        )
    }

    /// 先选品牌，再从其所属系列中选择具体漆系。
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("参考品牌", selection: brand) {
                ForEach(PaintBrand.allCases) { brand in
                    Text(brand.title).tag(brand)
                }
            }
            .accessibilityIdentifier("\(identifierPrefix)PaintBrandPicker")

            Picker("参考漆系", selection: $selection) {
                ForEach(selection.brand.series) { series in
                    Text(series.shortTitle).tag(series)
                }
            }
            .accessibilityIdentifier("\(identifierPrefix)PaintSeriesPicker")
        }
        .pickerStyle(.menu)
    }
}
