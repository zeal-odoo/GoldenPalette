import SwiftUI

struct PaintSeriesPicker: View {
    @Binding var selection: PaintSeries
    let identifierPrefix: String

    private var brand: Binding<PaintBrand> {
        Binding(
            get: { selection.brand },
            set: { selection = $0.defaultSeries }
        )
    }

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
