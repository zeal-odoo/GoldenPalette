import Foundation

enum PaintSwatchSource: String, Sendable {
    case encycolorpedia
    case tamiyaChart
    case mrHobbyChart
    case goldenSoFlatSwatch

    var note: String {
        switch self {
        case .encycolorpedia:
            return "色块采用 Encycolorpedia 对应田宫珐琅色号的 sRGB，仅作屏幕参考，非官方实测 RGB。"
        case .tamiyaChart:
            return "色块取自田宫官方色卡并转换为 sRGB，仅作屏幕参考，非官方实测 RGB。"
        case .mrHobbyChart:
            return "色块取自郡士对应漆系的官方色卡并转换为 sRGB，仅作屏幕参考，非官方实测 RGB。"
        case .goldenSoFlatSwatch:
            return "色块取自 GOLDEN SoFlat 官方色样，按内嵌 sRGB 配置取样；属于近似屏幕参考，并非官方公布的实测 RGB。"
        }
    }
}

struct PaintSwatch: Sendable {
    let hex: String
    let source: PaintSwatchSource
}

/// Verified 2026-10-09. These are digital references, not measured paint standards.
/// See docs/paint-swatch-sources.json for source URLs, hashes, profiles and sampling regions.
/// Existing catalog tables retain pre-1.0.12 RGB solely for old reference decoding.
enum PaintSwatchData {
    static func swatch(series: PaintSeries, code: String) -> PaintSwatch? {
        swatches["\(series.rawValue):\(code)"]
    }

    private static let swatches: [String: PaintSwatch] = {
        let entries = table.split(separator: "\n").compactMap { line -> (String, PaintSwatch)? in
            let fields = line.split(separator: "|").map(String.init)
            guard fields.count == 4,
                  let series = PaintSeries(rawValue: fields[0]),
                  let source = PaintSwatchSource(rawValue: fields[3]),
                  fields[2].count == 6, Int(fields[2], radix: 16) != nil else { return nil }
            return ("\(series.rawValue):\(fields[1])", PaintSwatch(hex: fields[2], source: source))
        }
        return Dictionary(uniqueKeysWithValues: entries)
    }()

    private static let table = """
tamiyaEnamel|X-1|000000|encycolorpedia
tamiyaEnamel|X-4|09337B|encycolorpedia
tamiyaEnamel|X-5|00441B|encycolorpedia
tamiyaEnamel|X-6|FF7F00|encycolorpedia
tamiyaEnamel|X-8|FDE601|encycolorpedia
tamiyaEnamel|X-9|4E2207|encycolorpedia
tamiyaEnamel|X-14|1E99C3|encycolorpedia
tamiyaEnamel|X-15|65B820|encycolorpedia
tamiyaEnamel|X-16|464A9F|encycolorpedia
tamiyaEnamel|X-17|F881AB|encycolorpedia
tamiyaEnamel|XF-4|B2C60F|encycolorpedia
tamiyaEnamel|XF-5|224311|encycolorpedia
tamiyaEnamel|XF-7|FD0000|encycolorpedia
tamiyaEnamel|XF-8|284C7C|encycolorpedia
tamiyaEnamel|XF-9|3E0E02|encycolorpedia
tamiyaEnamel|XF-10|3E2A09|encycolorpedia
tamiyaEnamel|XF-15|FDCCA1|encycolorpedia
tamiyaEnamel|XF-18|485B5F|encycolorpedia
tamiyaEnamel|XF-19|ADB7C0|encycolorpedia
tamiyaEnamel|XF-24|3F4448|encycolorpedia
tamiyaEnamel|XF-49|7E773D|encycolorpedia
tamiyaEnamel|XF-52|734835|encycolorpedia
tamiyaEnamel|XF-53|6D787C|encycolorpedia
tamiyaEnamel|XF-55|B6B187|encycolorpedia
tamiyaEnamel|XF-57|B7B36A|encycolorpedia
tamiyaEnamel|XF-58|1B3B14|encycolorpedia
tamiyaEnamel|XF-59|D89D43|encycolorpedia
tamiyaEnamel|XF-60|C6B141|encycolorpedia
tamiyaEnamel|XF-62|404A13|encycolorpedia
tamiyaEnamel|XF-64|66370B|encycolorpedia
tamiyaEnamel|XF-65|68856B|encycolorpedia
tamiyaEnamel|XF-66|677679|encycolorpedia
tamiyaEnamel|XF-67|326019|encycolorpedia
tamiyaEnamel|XF-68|732F07|encycolorpedia
tamiyaEnamel|XF-69|222423|encycolorpedia
goldenSoFlat|6755|F4F8F9|goldenSoFlatSwatch
goldenSoFlat|6745|1F241F|goldenSoFlatSwatch
goldenSoFlat|6660|017240|goldenSoFlatSwatch
goldenSoFlat|6610|0126D6|goldenSoFlatSwatch
goldenSoFlat|6505|FFF116|goldenSoFlatSwatch
goldenSoFlat|6550|F02B12|goldenSoFlatSwatch
goldenSoFlat|6645|02A7A8|goldenSoFlatSwatch
goldenSoFlat|6510|FFEB02|goldenSoFlatSwatch
goldenSoFlat|6570|EF4150|goldenSoFlatSwatch
goldenSoFlat|6530|FE660D|goldenSoFlatSwatch
goldenSoFlat|6595|6F3568|goldenSoFlatSwatch
goldenSoFlat|6675|AEE834|goldenSoFlatSwatch
tamiyaAcrylic|X-1|231916|tamiyaChart
tamiyaAcrylic|X-2|FFFFFF|tamiyaChart
tamiyaAcrylic|X-4|004EA2|tamiyaChart
tamiyaAcrylic|X-5|006C45|tamiyaChart
tamiyaAcrylic|X-6|ED6D00|tamiyaChart
tamiyaAcrylic|X-7|E60013|tamiyaChart
tamiyaAcrylic|X-8|FFDE00|tamiyaChart
tamiyaAcrylic|X-9|74372F|tamiyaChart
tamiyaAcrylic|X-14|00A5EA|tamiyaChart
tamiyaAcrylic|X-15|72BB2B|tamiyaChart
tamiyaAcrylic|X-16|564A8E|tamiyaChart
tamiyaAcrylic|X-17|EE85B2|tamiyaChart
tamiyaAcrylic|X-18|231916|tamiyaChart
tamiyaAcrylic|XF-1|231916|tamiyaChart
tamiyaAcrylic|XF-2|FFFFFF|tamiyaChart
tamiyaAcrylic|XF-3|FFE200|tamiyaChart
tamiyaAcrylic|XF-4|BAC327|tamiyaChart
tamiyaAcrylic|XF-5|5C8461|tamiyaChart
tamiyaAcrylic|XF-7|E6001D|tamiyaChart
tamiyaAcrylic|XF-8|006995|tamiyaChart
tamiyaAcrylic|XF-9|622D30|tamiyaChart
tamiyaAcrylic|XF-10|4F3833|tamiyaChart
tamiyaAcrylic|XF-15|FACE90|tamiyaChart
tamiyaAcrylic|XF-18|0978A0|tamiyaChart
tamiyaAcrylic|XF-19|CAD1CA|tamiyaChart
tamiyaAcrylic|XF-24|326978|tamiyaChart
tamiyaAcrylic|XF-49|9B9033|tamiyaChart
tamiyaAcrylic|XF-52|994930|tamiyaChart
tamiyaAcrylic|XF-53|71848E|tamiyaChart
tamiyaAcrylic|XF-55|CCBEA3|tamiyaChart
tamiyaAcrylic|XF-57|CBA77C|tamiyaChart
tamiyaAcrylic|XF-58|214837|tamiyaChart
tamiyaAcrylic|XF-59|F3C889|tamiyaChart
tamiyaAcrylic|XF-60|C8B341|tamiyaChart
tamiyaAcrylic|XF-62|485A3C|tamiyaChart
tamiyaAcrylic|XF-63|436878|tamiyaChart
tamiyaAcrylic|XF-64|503A28|tamiyaChart
tamiyaAcrylic|XF-65|3F6B76|tamiyaChart
tamiyaAcrylic|XF-66|526B77|tamiyaChart
tamiyaAcrylic|XF-67|275538|tamiyaChart
tamiyaAcrylic|XF-68|6A4B31|tamiyaChart
tamiyaAcrylic|XF-69|231916|tamiyaChart
tamiyaEnamel|X-2|FFFFFF|tamiyaChart
tamiyaEnamel|X-7|E60013|tamiyaChart
tamiyaEnamel|X-18|231916|tamiyaChart
tamiyaEnamel|XF-1|231916|tamiyaChart
tamiyaEnamel|XF-2|FFFFFF|tamiyaChart
tamiyaEnamel|XF-3|FFE200|tamiyaChart
tamiyaEnamel|XF-63|436878|tamiyaChart
tamiyaLacquer|LP-1|231916|tamiyaChart
tamiyaLacquer|LP-2|FFFFFF|tamiyaChart
tamiyaLacquer|LP-3|231916|tamiyaChart
tamiyaLacquer|LP-4|FFFFFF|tamiyaChart
tamiyaLacquer|LP-5|231916|tamiyaChart
tamiyaLacquer|LP-6|005BAC|tamiyaChart
tamiyaLacquer|LP-7|E60013|tamiyaChart
tamiyaLacquer|LP-8|FFF100|tamiyaChart
tamiyaLacquer|LP-12|717C85|tamiyaChart
tamiyaLacquer|LP-13|535860|tamiyaChart
tamiyaLacquer|LP-14|7E8186|tamiyaChart
tamiyaLacquer|LP-15|646C75|tamiyaChart
tamiyaLacquer|LP-16|BFB086|tamiyaChart
tamiyaLacquer|LP-17|5E4A33|tamiyaChart
tamiyaLacquer|LP-18|974229|tamiyaChart
tamiyaLacquer|LP-21|E60013|tamiyaChart
tamiyaLacquer|LP-25|7F5C2E|tamiyaChart
tamiyaLacquer|LP-26|1A603A|tamiyaChart
tamiyaLacquer|LP-27|436878|tamiyaChart
tamiyaLacquer|LP-28|485A3C|tamiyaChart
tamiyaLacquer|LP-29|3C5C37|tamiyaChart
tamiyaLacquer|LP-30|E5B877|tamiyaChart
tamiyaLacquer|LP-31|004234|tamiyaChart
tamiyaLacquer|LP-32|CAD2C3|tamiyaChart
tamiyaLacquer|LP-33|B9C4A8|tamiyaChart
tamiyaLacquer|LP-34|D1CEC1|tamiyaChart
tamiyaLacquer|LP-35|DDDCD7|tamiyaChart
tamiyaLacquer|LP-36|80A1B1|tamiyaChart
tamiyaLacquer|LP-37|98B4C2|tamiyaChart
tamiyaLacquer|LP-39|FFFEF7|tamiyaChart
tamiyaLacquer|LP-50|E60013|tamiyaChart
tamiyaLacquer|LP-51|F18D00|tamiyaChart
tamiyaSpray|TS-1|7F5A44|tamiyaChart
tamiyaSpray|TS-2|214E3E|tamiyaChart
tamiyaSpray|TS-3|C9B54C|tamiyaChart
tamiyaSpray|TS-4|485157|tamiyaChart
tamiyaSpray|TS-5|4A5E3D|tamiyaChart
tamiyaSpray|TS-6|231916|tamiyaChart
tamiyaSpray|TS-7|FFFEF7|tamiyaChart
tamiyaSpray|TS-8|E60013|tamiyaChart
tamiyaSpray|TS-9|00583B|tamiyaChart
tamiyaSpray|TS-10|0089D0|tamiyaChart
tamiyaSpray|TS-11|671A1F|tamiyaChart
tamiyaSpray|TS-12|F08300|tamiyaChart
tamiyaSpray|TS-14|231916|tamiyaChart
tamiyaSpray|TS-15|00479D|tamiyaChart
tamiyaSpray|TS-16|FFF100|tamiyaChart
tamiyaSpray|TS-17|DCDDDD|tamiyaChart
tamiyaSpray|TS-18|E6003E|tamiyaChart
tamiyaSpray|TS-19|0056A3|tamiyaChart
tamiyaSpray|TS-20|009F41|tamiyaChart
tamiyaSpray|TS-21|D6B400|tamiyaChart
tamiyaSpray|TS-22|DBE000|tamiyaChart
tamiyaSpray|TS-23|00A1E9|tamiyaChart
tamiyaSpray|TS-24|564A8E|tamiyaChart
tamiyaSpray|TS-25|F4B4D0|tamiyaChart
tamiyaSpray|TS-26|FFFFFF|tamiyaChart
tamiyaSpray|TS-27|FFFFFF|tamiyaChart
tamiyaSpray|TS-28|3C5C37|tamiyaChart
tamiyaSpray|TS-29|231916|tamiyaChart
tamiyaSpray|TS-30|DFDFDF|tamiyaChart
tamiyaSpray|TS-31|EA5505|tamiyaChart
tamiyaSpray|TS-32|6A909A|tamiyaChart
tamiyaSpray|TS-33|974229|tamiyaChart
tamiyaSpray|TS-34|FABF00|tamiyaChart
tamiyaSpray|TS-35|009944|tamiyaChart
tamiyaSpray|TS-36|E60013|tamiyaChart
tamiyaSpray|TS-37|601986|tamiyaChart
tamiyaSpray|TS-38|595757|tamiyaChart
tamiyaSpray|TS-39|C8171E|tamiyaChart
tamiyaSpray|TS-40|3F3B3A|tamiyaChart
tamiyaSpray|TS-41|01B1A8|tamiyaChart
tamiyaSpray|TS-42|898989|tamiyaChart
tamiyaSpray|TS-43|004C32|tamiyaChart
tamiyaSpray|TS-44|0066AE|tamiyaChart
tamiyaSpray|TS-45|FFFFFF|tamiyaChart
tamiyaSpray|TS-46|E5B877|tamiyaChart
tamiyaSpray|TS-47|FFE200|tamiyaChart
tamiyaSpray|TS-48|718895|tamiyaChart
tamiyaSpray|TS-49|E60013|tamiyaChart
tamiyaSpray|TS-50|00398E|tamiyaChart
tamiyaSpray|TS-51|003C90|tamiyaChart
tamiyaSpray|TS-52|23AC39|tamiyaChart
tamiyaSpray|TS-53|021C6A|tamiyaChart
tamiyaSpray|TS-54|007AAA|tamiyaChart
tamiyaSpray|TS-55|002F55|tamiyaChart
tamiyaSpray|TS-56|F08300|tamiyaChart
tamiyaSpray|TS-57|5977BA|tamiyaChart
tamiyaSpray|TS-58|7AA2CA|tamiyaChart
tamiyaSpray|TS-59|CF93A6|tamiyaChart
tamiyaSpray|TS-60|89C5A9|tamiyaChart
tamiyaSpray|TS-61|275538|tamiyaChart
tamiyaSpray|TS-62|6A4B31|tamiyaChart
tamiyaSpray|TS-63|302125|tamiyaChart
tamiyaSpray|TS-64|00243F|tamiyaChart
tamiyaSpray|TS-66|717C85|tamiyaChart
tamiyaSpray|TS-67|535860|tamiyaChart
tamiyaSpray|TS-68|BFB086|tamiyaChart
tamiyaSpray|TS-69|5E4A33|tamiyaChart
tamiyaSpray|TS-70|275538|tamiyaChart
tamiyaSpray|TS-71|CBC5C8|tamiyaChart
tamiyaSpray|TS-72|00AFD5|tamiyaChart
tamiyaSpray|TS-73|F18900|tamiyaChart
tamiyaSpray|TS-74|E60039|tamiyaChart
tamiyaSpray|TS-75|D2C89B|tamiyaChart
tamiyaSpray|TS-76|DCDDDD|tamiyaChart
tamiyaSpray|TS-77|FACE90|tamiyaChart
tamiyaSpray|TS-78|3F6B76|tamiyaChart
tamiyaSpray|TS-81|C1CBC9|tamiyaChart
tamiyaSpray|TS-82|231916|tamiyaChart
tamiyaSpray|TS-83|B9BCC5|tamiyaChart
tamiyaSpray|TS-84|C1AD49|tamiyaChart
tamiyaSpray|TS-85|E60013|tamiyaChart
tamiyaSpray|TS-86|E60013|tamiyaChart
tamiyaSpray|TS-87|DBCA94|tamiyaChart
tamiyaSpray|TS-88|DDDCCF|tamiyaChart
tamiyaSpray|TS-89|003C90|tamiyaChart
tamiyaSpray|TS-90|7F5C2E|tamiyaChart
tamiyaSpray|TS-91|1A603A|tamiyaChart
tamiyaSpray|TS-92|EE7800|tamiyaChart
tamiyaSpray|TS-93|005BAC|tamiyaChart
tamiyaSpray|TS-94|727172|tamiyaChart
tamiyaSpray|TS-95|DF0011|tamiyaChart
tamiyaSpray|TS-96|F7AB00|tamiyaChart
tamiyaSpray|TS-97|FFEA00|tamiyaChart
tamiyaSpray|TS-98|F39800|tamiyaChart
tamiyaSpray|TS-99|7E8186|tamiyaChart
tamiyaSpray|TS-100|717F87|tamiyaChart
tamiyaSpray|TS-101|FFFFFF|tamiyaChart
tamiyaSpray|TS-102|00A497|tamiyaChart
mrColor|C1|FFFFFF|mrHobbyChart
mrColor|C2|221815|mrHobbyChart
mrColor|C3|E50012|mrHobbyChart
mrColor|C4|FFE100|mrHobbyChart
mrColor|C5|004DA1|mrHobbyChart
mrColor|C6|006730|mrHobbyChart
mrColor|C7|C93929|mrHobbyChart
mrColor|C11|BDC2C4|mrHobbyChart
mrColor|C12|675832|mrHobbyChart
mrColor|C13|74858D|mrHobbyChart
mrColor|C14|004652|mrHobbyChart
mrColor|C19|9F8237|mrHobbyChart
mrColor|C20|4EBAA0|mrHobbyChart
mrColor|C21|B39242|mrHobbyChart
mrColor|C22|4F493C|mrHobbyChart
mrColor|C23|415D47|mrHobbyChart
mrColor|C26|D6E0AB|mrHobbyChart
mrColor|C29|552E34|mrHobbyChart
mrColor|C32|39555A|mrHobbyChart
mrColor|C33|221815|mrHobbyChart
mrColor|C34|008CD6|mrHobbyChart
mrColor|C39|BE9C5A|mrHobbyChart
mrColor|C40|103B41|mrHobbyChart
mrColor|C41|492F32|mrHobbyChart
mrColor|C42|3C3032|mrHobbyChart
mrColor|C43|694A31|mrHobbyChart
mrColor|C44|C9A865|mrHobbyChart
mrColor|C45|BFB77F|mrHobbyChart
mrColor|C51|E5B378|mrHobbyChart
mrColor|C54|20423A|mrHobbyChart
mrColor|C55|4E4F34|mrHobbyChart
mrColor|C58|EE7700|mrHobbyChart
mrColor|C59|E7370D|mrHobbyChart
mrColor|C62|FFFFFF|mrHobbyChart
mrColor|C63|EB6D94|mrHobbyChart
mrColor|C64|08A23B|mrHobbyChart
mrColor|C65|003F98|mrHobbyChart
mrColor|C66|009944|mrHobbyChart
mrColor|C67|3B217F|mrHobbyChart
mrColor|C68|D70D18|mrHobbyChart
mrColor|C69|F8F7F3|mrHobbyChart
mrColor|C70|20423A|mrHobbyChart
mrColor|C71|204146|mrHobbyChart
mrColor|C72|144C58|mrHobbyChart
mrColor|C79|E50012|mrHobbyChart
mrColor|C80|1D2087|mrHobbyChart
mrColor|C81|762A31|mrHobbyChart
mrColor|C92|221815|mrHobbyChart
mrColor|C97|B2BDB2|mrHobbyChart
mrColor|C100|AF1E31|mrHobbyChart
aqueous|H1|FFFFFF|mrHobbyChart
aqueous|H2|221815|mrHobbyChart
aqueous|H3|E50012|mrHobbyChart
aqueous|H4|FFE100|mrHobbyChart
aqueous|H5|004DA1|mrHobbyChart
aqueous|H6|008C46|mrHobbyChart
aqueous|H7|C93929|mrHobbyChart
aqueous|H11|FFFFFF|mrHobbyChart
aqueous|H12|221815|mrHobbyChart
aqueous|H13|D70D18|mrHobbyChart
aqueous|H14|E7370D|mrHobbyChart
aqueous|H15|003F98|mrHobbyChart
aqueous|H16|099E3B|mrHobbyChart
aqueous|H17|552E31|mrHobbyChart
aqueous|H19|EB6D94|mrHobbyChart
aqueous|H21|F8F7F3|mrHobbyChart
aqueous|H22|546572|mrHobbyChart
aqueous|H23|E50012|mrHobbyChart
aqueous|H24|EE7700|mrHobbyChart
aqueous|H25|008CD6|mrHobbyChart
aqueous|H26|009944|mrHobbyChart
aqueous|H27|C9A865|mrHobbyChart
aqueous|H29|EA5441|mrHobbyChart
aqueous|H32|103B41|mrHobbyChart
aqueous|H33|80292C|mrHobbyChart
aqueous|H34|E5A600|mrHobbyChart
aqueous|H35|1D2087|mrHobbyChart
aqueous|H37|694A31|mrHobbyChart
aqueous|H39|3B217F|mrHobbyChart
aqueous|H43|C8161D|mrHobbyChart
aqueous|H44|E5B378|mrHobbyChart
aqueous|H47|6C2C2F|mrHobbyChart
aqueous|H51|BDC2C4|mrHobbyChart
aqueous|H52|695D29|mrHobbyChart
aqueous|H53|546572|mrHobbyChart
aqueous|H54|004652|mrHobbyChart
aqueous|H55|221815|mrHobbyChart
aqueous|H56|144C58|mrHobbyChart
acrysion|N1|FFFFFF|mrHobbyChart
acrysion|N2|221815|mrHobbyChart
acrysion|N3|E50012|mrHobbyChart
acrysion|N4|FFE100|mrHobbyChart
acrysion|N5|004DA1|mrHobbyChart
acrysion|N6|008C46|mrHobbyChart
acrysion|N7|C93929|mrHobbyChart
acrysion|N11|FFFFFF|mrHobbyChart
acrysion|N12|221815|mrHobbyChart
acrysion|N13|D70D18|mrHobbyChart
acrysion|N14|E7370D|mrHobbyChart
acrysion|N15|003F98|mrHobbyChart
acrysion|N16|099E3B|mrHobbyChart
acrysion|N17|552E34|mrHobbyChart
acrysion|N19|EB6D94|mrHobbyChart
acrysion|N21|F8F7F3|mrHobbyChart
acrysion|N22|546572|mrHobbyChart
acrysion|N23|E50012|mrHobbyChart
acrysion|N24|EE7700|mrHobbyChart
acrysion|N25|008CD6|mrHobbyChart
acrysion|N26|009944|mrHobbyChart
acrysion|N27|C9A865|mrHobbyChart
acrysion|N32|103B41|mrHobbyChart
acrysion|N33|802830|mrHobbyChart
acrysion|N34|E5A600|mrHobbyChart
acrysion|N35|1D2087|mrHobbyChart
acrysion|N37|694A31|mrHobbyChart
acrysion|N39|3B217F|mrHobbyChart
acrysion|N43|AF1E31|mrHobbyChart
acrysion|N44|E5B378|mrHobbyChart
acrysion|N45|05B8EE|mrHobbyChart
acrysion|N46|00A050|mrHobbyChart
acrysion|N47|6C2C2F|mrHobbyChart
acrysion|N49|7384C0|mrHobbyChart
acrysion|N50|90B571|mrHobbyChart
acrysion|N51|BDC2C4|mrHobbyChart
acrysion|N52|695D29|mrHobbyChart
acrysion|N54|004652|mrHobbyChart
acrysion|N55|204146|mrHobbyChart
acrysion|N56|144C58|mrHobbyChart
"""
}
