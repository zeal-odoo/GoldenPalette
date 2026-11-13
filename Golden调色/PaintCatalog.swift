// 商品色目录与可用调色套装。
// 品牌/漆系/色号用于查找参考色；MixingPaintSet 另外限定 AI 真正可以使用的原料。
import Foundation

/// 商品品牌，作为系列选择器的第一层筛选条件。
enum PaintBrand: String, CaseIterable, Identifiable, Sendable {
    case golden
    case tamiya
    case mrHobby

    /// 使用稳定原始值作为列表身份。
    var id: String { rawValue }

    /// 品牌的用户可读名称。
    var title: String {
        switch self {
        case .golden: return "GOLDEN"
        case .tamiya: return "田宫 Tamiya"
        case .mrHobby: return "郡士 Mr.Hobby"
        }
    }

    /// 切换品牌后选中的初始漆系，避免继续使用前一个品牌的系列。
    var defaultSeries: PaintSeries {
        switch self {
        case .golden: return .goldenSoFlat
        case .tamiya: return .tamiyaAcrylic
        case .mrHobby: return .mrColor
        }
    }

    /// 只提供属于当前品牌的漆系。
    var series: [PaintSeries] { PaintSeries.allCases.filter { $0.brand == self } }
}

/// 系列与色号共同持久化：同品牌不同漆系可能共享色号，但不能互换。
/// Persist the series as well as the code: Tamiya acrylic and enamel share X/XF numbers.
enum PaintSeries: String, Codable, CaseIterable, Identifiable, Sendable {
    case goldenSoFlat
    case goldenFluid
    case tamiyaAcrylic
    case tamiyaEnamel
    case tamiyaLacquer
    case tamiyaSpray
    case tamiyaAircraft
    case tamiyaPolycarbonate
    case mrColor
    case aqueous
    case acrysion

    /// 原始值同时作为存档值和目录索引的一部分。
    var id: String { rawValue }

    /// 由具体漆系确定所属品牌。
    var brand: PaintBrand {
        switch self {
        case .goldenSoFlat, .goldenFluid: return .golden
        case .tamiyaAcrylic, .tamiyaEnamel, .tamiyaLacquer, .tamiyaSpray, .tamiyaAircraft, .tamiyaPolycarbonate: return .tamiya
        case .mrColor, .aqueous, .acrysion: return .mrHobby
        }
    }

    /// 系列选择菜单中的简短名称，包含色号范围或指定套装信息。
    var shortTitle: String {
        switch self {
        case .goldenSoFlat: return "SoFlat · 指定 12 色"
        case .goldenFluid: return "Fluid Acrylics · 指定 15 色"
        case .tamiyaAcrylic: return "丙烯漆 · X / XF"
        case .tamiyaEnamel: return "珐琅漆 · X / XF"
        case .tamiyaLacquer: return "Lacquer 溶剂型漆 · LP"
        case .tamiyaSpray: return "喷罐漆 · TS"
        case .tamiyaAircraft: return "航空模型喷罐漆 · AS"
        case .tamiyaPolycarbonate: return "聚碳酸酯喷罐漆 · PS"
        case .mrColor: return "Mr.Color 溶剂型漆 · C"
        case .aqueous: return "水性 Hobby Color · H"
        case .acrysion: return "Acrysion 水性漆 · N"
        }
    }

    /// 项目颜色、配方和提示词中的完整系列名称。
    var title: String {
        switch self {
        case .goldenSoFlat: return "GOLDEN SoFlat"
        case .goldenFluid: return "GOLDEN Fluid Acrylics"
        default: return "\(brand.title) · \(shortTitle)"
        }
    }

    /// 从集中维护的目录获取该系列的商品色。
    var paints: [CatalogPaint] { PaintCatalog.paints(for: self) }

    /// 解释本应用收录范围及预览色限制，避免误认为包含全产品线。
    var catalogNote: String {
        switch self {
        case .goldenSoFlat:
            return "使用指定的 12 色。" + previewNote
        case .goldenFluid:
            return "10 色调色套装，另加吡咯橙、二噁嗪紫、黄赭石、群青蓝、永久浅绿，共 15 色。" + previewNote
        case .tamiyaAcrylic, .tamiyaEnamel, .tamiyaLacquer, .tamiyaSpray, .tamiyaAircraft, .tamiyaPolycarbonate:
            return "按田宫官网目录核对，收录 \(matchingPaints("").count) 个有色参考；不含无色罩光、消光添加剂或稀释剂。" + previewNote
        default:
            return "内置常用实色色号，不含透明漆、金属漆或添加剂。" + previewNote
        }
    }

    /// 根据系列说明屏幕色来源；单个商品可再提供更具体的来源。
    var previewNote: String {
        switch self {
        case .goldenFluid:
            return "色块采用 GOLDEN 官方调色器的 sRGB，仅作屏幕参考，实际成色请以干燥小样为准。"
        case .goldenSoFlat:
            return PaintSwatchSource.goldenSoFlatSwatch.note
        case .tamiyaEnamel:
            return "已匹配色号保留 Encycolorpedia 的 sRGB，其余取自田宫官方色卡。均为屏幕参考，非官方实测 RGB。" + Self.sprayEffectNote
        case .tamiyaAcrylic, .tamiyaLacquer, .tamiyaSpray, .tamiyaAircraft:
            return PaintSwatchSource.tamiyaChart.note + Self.sprayEffectNote
        case .tamiyaPolycarbonate:
            return PaintSwatchSource.tamiyaChart.note + Self.sprayEffectNote
                + "PS 是聚碳酸酯车壳用漆，此处只参考其颜色。"
        case .mrColor, .aqueous, .acrysion:
            return PaintSwatchSource.mrHobbyChart.note
        }
    }

    /// 特殊效果商品的 RGB 只能近似颜色，不能表达表面效果。
    static let sprayEffectNote = "特殊效果色仅匹配近似颜色，不复现金属、珠光、荧光、透明或随角度变化的效果。"

    /// 按中英文名称或色号搜索，忽略大小写并兼容省略连字符及 Perm 缩写。
    func matchingPaints(_ search: String) -> [CatalogPaint] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        // 未经当前官网确认的旧色号仅保留给历史配方，不再出现在新选色列表。
        let availablePaints = paints.filter(\.isSelectable)
        guard !query.isEmpty else { return availablePaints }
        let codeQuery = query.replacingOccurrences(of: "-", with: "")
        return availablePaints.filter {
            $0.mixingName.localizedCaseInsensitiveContains(query)
                || $0.name.replacingOccurrences(of: "Permanent ", with: "Perm ").localizedCaseInsensitiveContains(query)
                || $0.code.replacingOccurrences(of: "-", with: "").localizedCaseInsensitiveContains(codeQuery)
        }
    }

    /// 从项目颜色恢复系列，依次考虑显式商品字段、参考色和旧配方系列。
    static func forColor(_ color: ColorInfo) -> PaintSeries {
        if let series = allCases.first(where: { $0.title == color.paintSeries }) { return series }
        return color.mixingRecipe?.referencePaint?.series ?? color.mixingRecipe?.paintSeries ?? .goldenSoFlat
    }
}

/// 一个具体系列中的商品色，显示色可由带出处的色样表覆盖。
struct CatalogPaint: Identifiable, Equatable, Sendable {
    let series: PaintSeries
    let code: String
    let name: String
    let chineseName: String
    // Original preview before the sourced sRGB update, used only for legacy decoding.
    /// 保留旧 RGB 以兼容没有预览快照的历史参考色，不能随当前色样更新。
    let legacyHex: String

    /// 优先使用已记录出处的新色样；没有覆盖项时使用原目录预览。
    var hex: String { PaintSwatchData.swatch(series: series, code: code)?.hex ?? legacyHex }
    /// 旧版曾把丙烯 NATO 色号复制到珐琅；当前官方珐琅目录未确认这三项。
    /// 保留模型身份可读取旧配方，新搜索与选色只展示已核对商品。
    var isSelectable: Bool {
        series != .tamiyaEnamel || !["XF-67", "XF-68", "XF-69"].contains(code)
    }

    /// 当前色样来源与效果限制会同时进入界面、AI 提示和保存的配方说明。
    var previewNote: String {
        let sourceNote = PaintSwatchData.swatch(series: series, code: code)?.source.note ?? series.previewNote
        guard series.brand == .tamiya else { return sourceNote }
        let legacyNote = isSelectable ? "" : "此为旧版珐琅参考，当前官方目录未确认，请核对实际漆系。"
        let materialNote = series == .tamiyaPolycarbonate ? "PS 是聚碳酸酯车壳用漆，此处只参考其颜色。" : ""
        return sourceNote + PaintSeries.sprayEffectNote + materialNote + legacyNote
    }

    /// 组合系列与色号作为身份，避免 X/XF 等共享编号发生冲突。
    var id: String { "\(series.rawValue):\(code)" }
    /// 调色界面同时提供中文名和瓶身英文名。
    var mixingName: String { "\(chineseName) · \(name)" }
    /// 商品列表统一沿用中英文显示名。
    var displayName: String { mixingName }
    /// 用量表额外显示系列，防止同名颜料跨系列误用。
    var ingredientName: String { "\(series.title) · \(mixingName)" }
    // 将六位十六进制色样拆成 0...255 通道，供预览和目标色转换使用。
    var red: Double { Double((rgb >> 16) & 0xFF) }
    var green: Double { Double((rgb >> 8) & 0xFF) }
    var blue: Double { Double(rgb & 0xFF) }
    /// 用于悬浮提示和 AI 输入的屏幕色说明。
    var rgbDescription: String { "sRGB \(Int(red)), \(Int(green)), \(Int(blue)) · #\(hex)" }
    /// 无效色样使用中性灰回退，目录完整性由测试另行检查。
    private var rgb: Int { Int(hex, radix: 16) ?? 0xCCCCCC }
}

/// 新请求选择单一套装；历史枚举值继续解释旧配方的精确原料范围。
/// New requests use one kit; older cases retain the exact paints in saved recipes.
enum MixingPaintSet: String, Codable, Identifiable, Sendable {
    case soFlat12
    /// 旧 13 色 Fluid 套装，仅用于恢复已保存配方。
    case fluid13
    case fluid15
    /// 旧跨系列 25 色组合，仅用于读取历史结果，不再开放生成。
    case soFlatAndFluid25

    /// 界面可选项独立于全部历史枚举值，避免旧格式重新进入生成入口。
    static let selectable: [MixingPaintSet] = [.soFlat12, .fluid15]
    /// 新建任务默认使用指定的 SoFlat 12 色。
    static let defaultSelection = MixingPaintSet.soFlat12

    /// 稳定套装身份，用于存档和选择器。
    var id: String { rawValue }
    /// 判断套装是否允许用于新的 AI 请求。
    var isSelectable: Bool { Self.selectable.contains(self) }

    /// 套装所涉及的系列；旧组合仍返回两个系列。
    var series: [PaintSeries] {
        switch self {
        case .soFlat12: return [.goldenSoFlat]
        case .fluid13, .fluid15: return [.goldenFluid]
        case .soFlatAndFluid25: return [.goldenSoFlat, .goldenFluid]
        }
    }

    /// 对应旧配方的单一系列字段，供存档一致性校验使用。
    // Matches the series field used by older saved recipes.
    var primarySeries: PaintSeries {
        switch self {
        case .fluid13, .fluid15: return .goldenFluid
        case .soFlat12, .soFlatAndFluid25: return .goldenSoFlat
        }
    }

    /// 展开套装实际原料；旧 Fluid 和组合套装必须按冻结色号筛选。
    var paints: [CatalogPaint] {
        switch self {
        case .fluid13:
            return PaintSeries.goldenFluid.paints.filter { Self.legacyFluidCodes.contains($0.code) }
        case .soFlatAndFluid25:
            return Self.soFlat12.paints + Self.fluid13.paints
        case .soFlat12, .fluid15:
            return series.flatMap(\.paints)
        }
    }

    // 历史套装的色号集合保持不变，新增商品不会改变旧配方的列全色号规则。
    // Freeze the old kit so adding catalog colors cannot invalidate saved 13- or 25-color recipes.
    private static let legacyFluidCodes: Set<String> = [
        "2009", "2008", "2210", "2305", "2260", "2255", "2270",
        "2275", "2040", "2380", "2276", "2150", "2407"
    ]

    /// 在配方及用量说明中使用的原料套装名称。
    var title: String {
        switch self {
        case .soFlat12: return "GOLDEN SoFlat"
        case .fluid13, .fluid15: return "GOLDEN Fluid Acrylics"
        case .soFlatAndFluid25: return "GOLDEN SoFlat + Fluid Acrylics"
        }
    }

    /// 选择器中区分套装规模与旧版身份的名称。
    var selectionTitle: String {
        switch self {
        case .soFlat12: return "SoFlat 12 色"
        case .fluid13: return "Fluid Acrylics 13 色（旧版）"
        case .fluid15: return "Fluid Acrylics 15 色"
        case .soFlatAndFluid25: return "旧版组合 25 色"
        }
    }

    /// 拒绝使用仅为存档兼容而保留的旧套装生成新配方。
    func validateForGeneration() throws {
        guard isSelectable else {
            throw MixingError.invalidRecipe("请选择 SoFlat 12 色或 Fluid Acrylics 15 色，分别生成配方。")
        }
    }
}

// MARK: - 内置商品数据
/// 按漆系建立只读目录，统一封装文本表解析。
enum PaintCatalog {
    /// 获取指定系列的目录，未知键返回空列表。
    static func paints(for series: PaintSeries) -> [CatalogPaint] {
        catalogs[series] ?? []
    }

    /// 静态构建目录，避免每次视图刷新都重新解析文本表。
    private static let catalogs: [PaintSeries: [CatalogPaint]] = [
        .goldenSoFlat: GoldenPaint.all.map {
            CatalogPaint(series: .goldenSoFlat, code: $0.code, name: $0.name, chineseName: $0.chineseName, legacyHex: $0.legacyHex)
        },
        .goldenFluid: parse(goldenFluid, series: .goldenFluid),
        .tamiyaAcrylic: parse(tamiyaCommon + "\n" + TamiyaPaintAdditions.acrylic, series: .tamiyaAcrylic),
        .tamiyaEnamel: parse(tamiyaCommon + "\n" + TamiyaPaintAdditions.enamel, series: .tamiyaEnamel),
        .tamiyaLacquer: parse(tamiyaLacquer + "\n" + TamiyaPaintAdditions.lacquer, series: .tamiyaLacquer),
        .tamiyaSpray: parse(tamiyaSpray, series: .tamiyaSpray),
        .tamiyaAircraft: parse(TamiyaPaintAdditions.aircraft, series: .tamiyaAircraft),
        .tamiyaPolycarbonate: parse(TamiyaPaintAdditions.polycarbonate, series: .tamiyaPolycarbonate),
        .mrColor: parse(mrColor, series: .mrColor),
        .aqueous: parse(aqueous, series: .aqueous),
        .acrysion: parse(acrysion, series: .acrysion)
    ]

    /// 表字段依次为“色号 | 中文名 | 英文名 | 历史 HEX”，跳过结构不完整的行。
    private static func parse(_ table: String, series: PaintSeries) -> [CatalogPaint] {
        let paints = table.split(separator: "\n").compactMap { line -> CatalogPaint? in
            let fields = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 4 else { return nil }
            return CatalogPaint(series: series, code: fields[0], name: fields[2], chineseName: fields[1], legacyHex: fields[3])
        }
        // 按瓶身色号自然排序，增补条目回到对应编号位置，X-2 不会排在 X-19 后。
        return series.brand == .tamiya
            ? paints.sorted { $0.code.compare($1.code, options: .numeric) == .orderedAscending }
            : paints
    }

    // Fluid 指定原料由 10 色套装及 5 个补充色组成；保留商品 2xxx 色号和原有来源记录。
    // The requested Fluid Mixing Set (0928) plus five additional Fluid Acrylic colors.
    // https://goldenartistcolors.com/products/fluid-acrylics-mixing-set
    // https://goldenartistcolors.com/products/golden-artist-acrylics/fluid/pigment-data
    // Screen sRGB: official acrylic mixer, <mixer ID>.paintColor.srgb, checked 2026-10-09.
    // https://assets.goldenartistcolors.com/mixerPaintData/index.json
    // Mixer IDs use 1xxx; each mapped entry explicitly supports Fluid in paletteTags.
    // Keep retail Fluid 2xxx codes. The code-to-ID mapping is documented in README.md.
    // Added 2400/2250 from mixer IDs 1400/1250, including the "Perm Green Light" alias, checked 2026-11-11.
    private static let goldenFluid = """
2009|苯并咪唑酮浅黄|Benzimidazolone Yellow Light|F6CF00
2008|苯并咪唑酮中黄|Benzimidazolone Yellow Medium|FEC000
2210|萘酚浅红|Naphthol Red Light|C91F10
2305|喹吖啶酮品红|Quinacridone Magenta|5B172D
2260|酞菁蓝（红相）|Phthalo Blue (Red Shade)|1E1334
2255|酞菁蓝（绿相）|Phthalo Blue (Green Shade)|20114B
2270|酞菁绿（蓝相）|Phthalo Green (Blue Shade)|012833
2275|酞菁绿（黄相）|Phthalo Green (Yellow Shade)|002C2A
2040|炭黑|Carbon Black|232222
2380|钛白|Titanium White|F7F7F2
2276|吡咯橙|Pyrrole Orange|F33C00
2150|二噁嗪紫|Dioxazine Purple|281F1D
2407|黄赭石|Yellow Ochre|B2792F
2400|群青蓝|Ultramarine Blue|19123E
2250|永久浅绿|Permanent Green Light|007639
"""

    // 以下表中的 HEX 是历史兼容值；当前显示色优先来自 PaintSwatchData。
    // Codes and names: official Tamiya color chart (2024) and Mr.Hobby chart (2024–2025).
    // https://www.tamiya.com/cms/img/usr/inst/paints/202405_paints.pdf
    // https://www.mr-hobby.com/en/record-download/catalog/23
    // This is a curated solid-color mixing library, not the complete product catalogue.
    // Retain the old approximations for decoding saved references; PaintSwatchData supplies current sRGB.
    /// 保留旧版丙烯／珐琅共用基础表及历史 HEX；增补清单按漆系分别核对。
    private static let tamiyaCommon = """
X-1|黑色|Black|202020
X-2|白色|White|F5F5F0
X-4|蓝色|Blue|1553A4
X-5|绿色|Green|168448
X-6|橙色|Orange|F47A24
X-7|红色|Red|D3292E
X-8|柠檬黄|Lemon Yellow|F5DC22
X-9|棕色|Brown|734C35
X-14|天蓝|Sky Blue|62B5DF
X-15|浅绿|Light Green|86B94D
X-16|紫色|Purple|754781
X-17|粉红|Pink|EA95B2
X-18|半光黑|Semi Gloss Black|28292A
XF-1|消光黑|Flat Black|252525
XF-2|消光白|Flat White|F0F0EB
XF-3|消光黄|Flat Yellow|EED139
XF-4|黄绿|Yellow Green|B6B644
XF-5|消光绿|Flat Green|497653
XF-7|消光红|Flat Red|BD3C36
XF-8|消光蓝|Flat Blue|305D96
XF-9|舰底红|Hull Red|613D39
XF-10|消光棕|Flat Brown|69493A
XF-15|消光肤色|Flat Flesh|E8B18D
XF-18|中蓝|Medium Blue|4C6477
XF-19|天空灰|Sky Grey|B8BCB9
XF-24|深灰|Dark Grey|575B5A
XF-49|卡其|Khaki|97875C
XF-52|土棕|Flat Earth|987659
XF-53|中性灰|Neutral Grey|828687
XF-55|甲板棕|Deck Tan|C2B69A
XF-57|米黄|Buff|D0BD8C
XF-58|橄榄绿|Olive Green|626A43
XF-59|沙漠黄|Desert Yellow|B99B62
XF-60|深黄|Dark Yellow|B5A56B
XF-62|橄榄褐|Olive Drab|595C3D
XF-63|德国灰|German Grey|494D50
XF-64|红棕|Red Brown|795042
XF-65|原野灰|Field Grey|747B68
XF-66|浅灰|Light Grey|A0A6A8
XF-67|北约绿|NATO Green|4C614B
XF-68|北约棕|NATO Brown|74544A
XF-69|北约黑|NATO Black|343839
"""

    /// 田宫 LP 系列的内置有色商品目录。
    private static let tamiyaLacquer = """
LP-1|黑色|Black|202020
LP-2|白色|White|F5F5F0
LP-3|消光黑|Flat Black|252525
LP-4|消光白|Flat White|F0F0EB
LP-5|半光黑|Semi Gloss Black|28292A
LP-6|纯蓝|Pure Blue|1457AF
LP-7|纯红|Pure Red|DA2929
LP-8|纯黄|Pure Yellow|F4D629
LP-12|吴海军工厂灰|IJN Gray (Kure Arsenal)|737B7A
LP-13|佐世保海军工厂灰|IJN Gray (Sasebo Arsenal)|686F73
LP-14|舞鹤海军工厂灰|IJN Gray (Maizuru Arsenal)|757B7A
LP-15|横须贺海军工厂灰|IJN Gray (Yokosuka Arsenal)|697378
LP-16|木甲板棕|Wooden Deck Tan|BDA77A
LP-17|油毡甲板棕|Linoleum Deck Brown|8B6043
LP-18|暗红|Dull Red|913E36
LP-21|意大利红|Italian Red|DA352D
LP-25|陆自棕|Brown (JGSDF)|887653
LP-26|陆自深绿|Dark Green (JGSDF)|4D5C48
LP-27|德国灰|German Gray|484D50
LP-28|橄榄褐|Olive Drab|5A5C3D
LP-29|橄榄褐 2|Olive Drab 2|6B6C43
LP-30|浅沙色|Light Sand|D0BD93
LP-31|日本海军深绿 2|Dark Green 2 (IJN)|304F42
LP-32|日本海军浅灰|Light Gray (IJN)|B2B7A4
LP-33|日本海军灰绿|Gray Green (IJN)|ADB398
LP-34|浅灰|Light Gray|ADB5BA
LP-35|识别白|Insignia White|ECECDF
LP-36|深幽灵灰|Dark Ghost Gray|89949D
LP-37|浅幽灵灰|Light Ghost Gray|AFB9BC
LP-39|赛车白|Racing White|F0E9D6
LP-50|亮红|Bright Red|E93629
LP-51|纯橙|Pure Orange|F67523
"""

    // TS 喷罐作为目标参考色使用；无色罩光款不进入可选颜色目录。
    // TS product codes and English names checked against Tamiya's catalog on 2026-10-09.
    // https://www.tamiya.com/english/products/list.html?genre_item=e_504030
    // Legacy app-authored RGB; current official-chart sRGB is supplied by PaintSwatchData.
    // TS colors are targets only. Omit colorless clear coats 13, 65, 79, and 80;
    // colored effect paints remain selectable, with limitations in the UI and AI prompt.
    private static let tamiyaSpray = """
TS-1|红棕|Red Brown|795042
TS-2|深绿|Dark Green|414F38
TS-3|深黄|Dark Yellow|B5A56B
TS-4|德国灰|German Grey|494D50
TS-5|橄榄褐|Olive Drab|595C3D
TS-6|消光黑|Matt Black|252525
TS-7|赛车白|Racing White|F0E9D6
TS-8|意大利红|Italian Red|DA352D
TS-9|英国绿|British Green|174A39
TS-10|法国蓝|French Blue|2474B6
TS-11|栗红|Maroon|652B36
TS-12|橙色|Orange|F47727
TS-14|黑色|Black|202020
TS-15|蓝色|Blue|1553A4
TS-16|黄色|Yellow|F4D629
TS-17|亮光铝色|Gloss Aluminum|B9BCC0
TS-18|金属红|Metallic Red|A32B39
TS-19|金属蓝|Metallic Blue|224F91
TS-20|金属绿|Metallic Green|24704E
TS-21|金色|Gold|B59443
TS-22|浅绿|Light Green|65AE42
TS-23|浅蓝|Light Blue|60B8DC
TS-24|紫色|Purple|684A8B
TS-25|粉红|Pink|EA95B2
TS-26|纯白|Pure White|F5F5F0
TS-27|消光白|Matt White|F0F0EB
TS-28|橄榄褐 2|Olive Drab 2|6B6C43
TS-29|半光黑|Semi-Gloss Black|28292A
TS-30|银箔色|Silver Leaf|C4C6C8
TS-31|亮橙|Bright Orange|F26824
TS-32|雾灰|Haze Grey|899391
TS-33|暗红|Dull Red|913E36
TS-34|骆驼黄|Camel Yellow|EBAE23
TS-35|公园绿|Park Green|42A34B
TS-36|荧光红|Fluorescent Red|FF4141
TS-37|薰衣草紫|Lavender|9A8CC1
TS-38|枪铁色|Gun Metal|52565B
TS-39|云母红|Mica Red|B5303C
TS-40|金属黑|Metallic Black|292C30
TS-41|珊瑚蓝|Coral Blue|57B9C0
TS-42|浅枪铁色|Light Gun Metal|93979A
TS-43|赛车绿|Racing Green|21513D
TS-44|鲜亮蓝|Brilliant Blue|1267B2
TS-45|珍珠白|Pearl White|EAE9E1
TS-46|浅沙色|Light Sand|D0BD93
TS-47|铬黄|Chrome Yellow|F5CB24
TS-48|炮舰灰|Gunship Grey|5F666C
TS-49|亮红|Bright Red|E93629
TS-50|云母蓝|Mica Blue|174694
TS-51|赛车蓝|Racing Blue|173D66
TS-52|糖果青柠绿|Candy Lime Green|83B846
TS-53|深金属蓝|Deep Metallic Blue|203B5B
TS-54|浅金属蓝|Light Metallic Blue|6F9EB8
TS-55|深蓝|Dark Blue|22395B
TS-56|鲜亮橙|Brilliant Orange|F2661D
TS-57|蓝紫|Blue Violet|514481
TS-58|珍珠浅蓝|Pearl Light Blue|7FB4D5
TS-59|珍珠浅红|Pearl Light Red|DF7479
TS-60|珍珠绿|Pearl Green|5EAB89
TS-61|北约绿|NATO Green|4C614B
TS-62|北约棕|NATO Brown|74544A
TS-63|北约黑|NATO Black|343839
TS-64|深云母蓝|Dark Mica Blue|24364F
TS-66|日本海军灰（吴海军工厂）|IJN Gray (Kure Arsenal)|737B7A
TS-67|日本海军灰（佐世保海军工厂）|IJN Gray (Sasebo Arsenal)|686F73
TS-68|木甲板棕|Wooden Deck Tan|BDA77A
TS-69|油毡甲板棕|Linoleum Deck Brown|8B6043
TS-70|橄榄褐（陆上自卫队）|Olive Drab (JGSDF)|62664B
TS-71|烟色（透明）|Smoke|6A6561
TS-72|透明蓝|Clear Blue|2864A4
TS-73|透明橙|Clear Orange|E88435
TS-74|透明红|Clear Red|BE343F
TS-75|香槟金|Champagne Gold|BCAF8D
TS-76|云母银|Mica Silver|B2B7BB
TS-77|消光肤色|Flat Flesh|E8B18D
TS-78|原野灰|Field Gray|747B68
TS-81|皇家浅灰|Royal Light Gray|B9BFBD
TS-82|橡胶黑|Rubber Black|303333
TS-83|金属银|Metallic Silver|C2C6CA
TS-84|金属金|Metallic Gold|B49955
TS-85|亮云母红|Bright Mica Red|D53F46
TS-86|纯红|Pure Red|DA2929
TS-87|钛金|Titanium Gold|B7A16B
TS-88|钛银|Titanium Silver|B8B4A7
TS-89|珍珠蓝|Pearl Blue|25457B
TS-90|棕色（陆上自卫队）|Brown (JGSDF)|887653
TS-91|深绿（陆上自卫队）|Dark Green (JGSDF)|4D5C48
TS-92|金属橙|Metallic Orange|C87339
TS-93|纯蓝|Pure Blue|1457AF
TS-94|金属灰|Metallic Gray|71777C
TS-95|纯金属红|Pure Metallic Red|B52D37
TS-96|荧光橙|Fluorescent Orange|FF7024
TS-97|珍珠黄|Pearl Yellow|EBC83A
TS-98|纯橙|Pure Orange|F67523
TS-99|日本海军灰（舞鹤海军工厂）|IJN Gray (Maizuru Arsenal)|757B7A
TS-100|半光亮枪铁色|Semi-Gloss Bright Gun Metal|8C9095
TS-101|底色白|Base White|F5F5EF
TS-102|钴绿|Cobalt Green|17A794
"""

    /// 郡士 Mr.Color 系列，C 前缀属于商品身份的一部分。
    private static let mrColor = """
C1|白色|White|F5F5F0
C2|黑色|Black|202020
C3|红色|Red|CB2C31
C4|黄色|Yellow|F2D629
C5|蓝色|Blue|1758A2
C6|绿色|Green|21814B
C7|棕色|Brown|72503D
C11|浅鸥灰|Light Gull Gray|B8B8AB
C12|橄榄褐 1|Olive Drab (1)|676546
C13|中性灰|Neutral Gray|858786
C14|海军蓝|Navy Blue|34434E
C19|沙棕|Sandy Brown|B6A079
C20|浅蓝|Light Blue|93ADB4
C21|中石色|Middle Stone|B49A5E
C22|深土色|Dark Earth|78654D
C23|深绿 2|Dark Green (2)|4E5949
C26|鸭蛋绿|Duck Egg Green|B4C5AB
C29|舰底红|Hull Red|684039
C32|深灰 2|Dark Gray (2)|60686A
C33|消光黑|Flat Black|272727
C34|天蓝|Sky Blue|5BAFD1
C39|深黄|Dark Yellow (Sandy Yellow)|BBAC71
C40|德国灰|German Gray|494F50
C41|红棕|Red Brown|794C3E
C42|桃花心木|Mahogany|624135
C43|木棕|Wood Brown|A47850
C44|棕褐|Tan|C3A780
C45|帆布色|Sail Color|DCD6B5
C51|肤色|Flesh|E9B492
C54|卡其绿|Khaki Green|74714A
C55|卡其|Khaki|A09164
C58|橙黄|Orange Yellow|F2BC28
C59|橙色|Orange|F07928
C62|消光白|Flat White|F0F0E8
C63|粉红|Pink|E59BAE
C64|黄绿|Yellow Green|A7BB42
C65|亮蓝|Bright Blue|2474B6
C66|亮绿|Bright Green|41A453
C67|紫色|Purple|75477A
C68|茜红|Madder Red|A82F44
C69|米白|Off White|ECE6CD
C70|深绿|Dark Green|414F38
C71|午夜蓝|Midnight Blue|283744
C72|中蓝|Intermediate Blue|70828C
C79|鲜红|Shine Red|DF3B31
C80|钴蓝|Cobalt Blue|355993
C81|赤褐|Russet|874C3E
C92|半光黑|Semi Gloss Black|292A2A
C97|浅灰|Light Gray|BCC0BB
C100|酒红|Wine Red|782F41
"""

    /// 郡士水性 Hobby Color 系列，保留独立的 H 色号。
    private static let aqueous = """
H1|白色|White|F5F5F0
H2|黑色|Black|202020
H3|红色|Red|CB2C31
H4|黄色|Yellow|F2D629
H5|蓝色|Blue|1758A2
H6|绿色|Green|21814B
H7|棕色|Brown|72503D
H11|消光白|Flat White|F0F0E8
H12|消光黑|Flat Black|272727
H13|消光红|Flat Red|BF3937
H14|橙色|Orange|F07928
H15|亮蓝|Bright Blue|2474B6
H16|黄绿|Yellow Green|A7BB42
H17|可可棕|Cocoa Brown|684039
H19|粉红|Pink|E59BAE
H21|米白|Off White|ECE6CD
H22|灰色|Gray|9A9D99
H23|鲜红|Shine Red|DF3B31
H24|橙黄|Orange Yellow|F2BC28
H25|天蓝|Sky Blue|5BAFD1
H26|亮绿|Bright Green|41A453
H27|棕褐|Tan|C3A780
H29|鲑鱼粉|Salmon Pink|E89A85
H32|德国灰|German Gray|494F50
H33|赤褐|Russet|874C3E
H34|奶油黄|Cream Yellow|EDDD98
H35|钴蓝|Cobalt Blue|355993
H37|木棕|Wood Brown|A47850
H39|紫色|Purple|75477A
H43|酒红|Wine Red|782F41
H44|肤色|Flesh|E9B492
H47|红棕|Red Brown|794C3E
H51|浅鸥灰|Light Gull Gray|B8B8AB
H52|橄榄褐 1|Olive Drab (1)|676546
H53|中性灰|Neutral Gray|858786
H54|海军蓝|Navy Blue|34434E
H55|午夜蓝|Midnight Blue|283744
H56|中蓝|Intermediate Blue|70828C
"""

    /// 郡士 Acrysion 系列，保留独立的 N 色号。
    private static let acrysion = """
N1|白色|White|F5F5F0
N2|黑色|Black|202020
N3|红色|Red|CB2C31
N4|黄色|Yellow|F2D629
N5|蓝色|Blue|1758A2
N6|绿色|Green|21814B
N7|棕色|Brown|72503D
N11|消光白|Matt White|F0F0E8
N12|消光黑|Matt Black|272727
N13|消光红|Matt Red|BF3937
N14|橙色|Orange|F07928
N15|亮蓝|Bright Blue|2474B6
N16|黄绿|Yellow Green|A7BB42
N17|舰底红|Hull Red|684039
N19|粉红|Pink|E59BAE
N21|米白|Off White|ECE6CD
N22|中性灰|Neutral Gray|858786
N23|鲜红|Shine Red|DF3B31
N24|橙黄|Orange Yellow|F2BC28
N25|天蓝|Sky Blue|5BAFD1
N26|亮绿|Bright Green|41A453
N27|棕褐|Tan|C3A780
N32|德国灰|German Gray|494F50
N33|赤褐|Russet|874C3E
N34|奶油黄|Cream Yellow|EDDD98
N35|钴蓝|Cobalt Blue|355993
N37|木棕|Wood Brown|A47850
N39|紫色|Purple|75477A
N43|酒红|Wine Red|782F41
N44|肤色|Flesh|E9B492
N45|浅蓝|Light Blue|82BDD0
N46|翡翠绿|Emerald Green|2DA383
N47|红棕|Red Brown|794C3E
N49|紫罗兰|Violet|6C528C
N50|青柠绿|Lime Green|C1CF5B
N51|浅鸥灰|Light Gull Gray|B8B8AB
N52|橄榄褐 1|Olive Drab (1)|676546
N54|海军蓝|Navy Blue|34434E
N55|午夜蓝|Midnight Blue|283744
N56|中蓝|Intermediate Blue|70828C
"""
}
