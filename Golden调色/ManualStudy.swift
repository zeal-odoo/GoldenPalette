// 说明书考证的数据层：定义输入、证据、颜色、页面标记及项目存档。
// AI 返回值和本地文件共用这些模型，进入后续流程前需通过相应 validated 方法。
import Foundation

/// 用户指定的模型套件与涂装主题；保存原始要求以判断既有考证是否过期。
struct ManualStudyInput: Codable, Equatable, Sendable {
    /// 品牌、货号、比例或名称，作为说明书搜索条件。
    var kit = ""
    /// 年代、部队、个体及配色要求，用于限定考证范围。
    var theme = ""

    /// 去除首尾空白并限制输入长度；单独搜索说明书时允许主题为空。
    func validated(requireTheme: Bool = true) throws -> Self {
        let value = Self(
            kit: kit.trimmingCharacters(in: .whitespacesAndNewlines),
            theme: theme.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !value.kit.isEmpty, !requireTheme || !value.theme.isEmpty else {
            throw ManualStudyError.invalid("请填写模型品牌、货号或名称，以及要考证的年代、部队或涂装主题。")
        }
        guard value.kit.count <= 500, value.theme.count <= 4_000 else {
            throw ManualStudyError.invalid("模型信息或涂装要求过长，请精简后重试。")
        }
        return value
    }
}

/// 表示资料对颜色结论的支持程度，与零件位置是否经人工核对分别记录。
enum ManualEvidenceLevel: String, Codable, CaseIterable, Sendable {
    case supported
    case inferred
    case disputed

    /// 在界面和导出报告中使用的证据等级名称。
    var title: String {
        switch self {
        case .supported: return "资料支持"
        case .inferred: return "推测 · 待确认"
        case .disputed: return "存在争议"
        }
    }
}

/// 一条可追溯资料；颜色通过 sourceIDs 引用其 id。
struct ManualEvidence: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let publisher: String
    let url: String
    let summary: String

    /// 仅将符合本功能地址规则的网页链接交给界面打开。
    var link: URL? { ManualStudyURL.webURL(url) }
}

/// 一个考证颜色，包含适用部位、证据及可选的屏幕近似色。
struct ManualResearchColor: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let standard: String
    let usage: String
    /// RGB 仅用于预览和试调；无法可靠换算时允许为空。
    let rgb: MixingTarget?
    /// 说明 RGB 的来源或近似换算依据，避免把预览值当成历史标准。
    let rgbBasis: String
    let evidence: ManualEvidenceLevel
    let explanation: String
    /// 引用本次考证 sources 中的编号，不直接复制资料对象。
    let sourceIDs: [String]

    /// 有标准色号时同时显示色名和标准，便于区分同名颜色。
    var displayName: String { standard.isEmpty ? name : "\(name) · \(standard)" }
}

/// 一次完整的主题考证，保留颜色、来源及尚未解决的问题。
struct ManualResearchResult: Codable, Equatable, Sendable {
    let subject: String
    let summary: String
    let colors: [ManualResearchColor]
    let sources: [ManualEvidence]
    let uncertainties: [String]

    /// 校验数量、唯一编号、来源引用及 RGB；结构有效不等同于历史结论已被人工证实。
    func validated() throws -> Self {
        guard !subject.isEmpty, colors.count <= 60, sources.count <= 40,
              Set(colors.map(\.id)).count == colors.count,
              Set(sources.map(\.id)).count == sources.count else {
            throw ManualStudyError.invalid("AI 返回了重复或过多的颜色、资料编号，请重试。")
        }
        let sourceIDs = Set(sources.map(\.id))
        guard sources.allSatisfy({ !$0.id.isEmpty && !$0.title.isEmpty && !$0.summary.isEmpty && $0.link != nil }) else {
            throw ManualStudyError.invalid("AI 返回的考证资料缺少标题、依据或有效网页地址，请重试。")
        }
        for color in colors {
            // “资料支持”的颜色必须引用已列出的来源；推测或争议仍需给出解释。
            guard !color.id.isEmpty, !color.name.isEmpty, !color.explanation.isEmpty,
                  color.sourceIDs.allSatisfy(sourceIDs.contains),
                  color.evidence != .supported || !color.sourceIDs.isEmpty else {
                throw ManualStudyError.invalid("颜色 \(color.name) 缺少可追溯依据，不能作为考证结果使用。")
            }
            if let rgb = color.rgb {
                guard [rgb.red, rgb.green, rgb.blue].allSatisfy({ (0...255).contains($0) }),
                      !color.rgbBasis.isEmpty else {
                    throw ManualStudyError.invalid("颜色 \(color.name) 的预览 RGB 或换算说明无效。")
                }
            }
        }
        return self
    }
}

/// 搜索得到的说明书候选；来源网页必填，尚未找到直达 PDF 时 pdfURL 为空。
struct ManualCandidate: Codable, Equatable, Identifiable, Sendable {
    let title: String
    let pageURL: String
    let pdfURL: String
    let matchNotes: String

    /// 用网页与 PDF 地址的组合去重，允许同一来源页面对应不同版本的说明书。
    var id: String { pageURL + "|" + pdfURL }
    var pageLink: URL? { ManualStudyURL.webURL(pageURL) }
    var pdfLink: URL? { ManualStudyURL.webURL(pdfURL) }
}

/// 说明书搜索结果及版本匹配说明。
struct ManualSearchResult: Codable, Equatable, Sendable {
    let candidates: [ManualCandidate]
    let notes: String

    /// 拒绝重复候选和无效链接，同时允许搜索没有结果。
    func validated() throws -> Self {
        guard candidates.count <= 8, Set(candidates.map(\.id)).count == candidates.count,
              candidates.allSatisfy({
                  !$0.title.isEmpty && !$0.matchNotes.isEmpty && $0.pageLink != nil
                      && ($0.pdfURL.isEmpty || $0.pdfLink != nil)
              }) else {
            throw ManualStudyError.invalid("AI 返回的说明书链接无效，请重新搜索或直接导入 PDF。")
        }
        return self
    }
}

/// 单页上的一个颜色定位点；id 仅要求在该页内唯一。
struct ManualPartMark: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    var part: String
    var step: String
    /// 关联本次考证中的颜色编号，避免标记自行引入未经考证的新颜色。
    var colorID: String
    // Coordinates refer to the upright page image, with (0, 0) at its top left.
    /// 相对正向显示页面的 0...1 坐标，左上为原点；PDF 坐标由 ManualPDF 转换。
    var x: Double
    var y: Double
    var reason: String
    /// AI 是否对定位或颜色对应关系存疑；与 reviewed 的人工确认状态相互独立。
    var uncertain: Bool
    /// 只有用户确认后才设为 true，不能由 AI 自行确认。
    var reviewed: Bool = false

    /// 显式列出序列化字段，以便兼容缺少人工核对状态的旧数据。
    enum CodingKeys: String, CodingKey {
        case id, part, step, colorID, x, y, reason, uncertain, reviewed
    }

    /// 创建标记时默认尚未人工核对。
    init(id: Int, part: String, step: String, colorID: String, x: Double, y: Double,
         reason: String, uncertain: Bool, reviewed: Bool = false) {
        self.id = id
        self.part = part
        self.step = step
        self.colorID = colorID
        self.x = x
        self.y = y
        self.reason = reason
        self.uncertain = uncertain
        self.reviewed = reviewed
    }

    /// 读取 AI 输出或旧存档；缺少 reviewed 时按未核对处理。
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        part = try values.decode(String.self, forKey: .part)
        step = try values.decode(String.self, forKey: .step)
        colorID = try values.decode(String.self, forKey: .colorID)
        x = try values.decode(Double.self, forKey: .x)
        y = try values.decode(Double.self, forKey: .y)
        reason = try values.decode(String.self, forKey: .reason)
        uncertain = try values.decode(Bool.self, forKey: .uncertain)
        reviewed = try values.decodeIfPresent(Bool.self, forKey: .reviewed) ?? false
    }
}

/// 某一页的标记和处理状态；空标记也可表示 AI 已确认该页无需涂装。
struct ManualPageResult: Codable, Equatable, Identifiable, Sendable {
    /// 从 0 开始的原始说明书页索引，界面展示时加 1。
    let pageIndex: Int
    var notes: String
    var marks: [ManualPartMark]
    /// 手动添加标记不代表 AI 已分析整页，因此单独记录处理覆盖范围。
    var analyzedByAI: Bool

    /// 页索引用作列表身份，同一页的结果通过替换更新。
    var id: Int { pageIndex }

    /// 页面结果的存档字段；analyzedByAI 是兼容读取时的可选字段。
    enum CodingKeys: String, CodingKey {
        case pageIndex, notes, marks, analyzedByAI
    }

    /// 默认用于 AI 页结果；手工新建页面需显式传入 analyzedByAI: false。
    init(pageIndex: Int, notes: String, marks: [ManualPartMark], analyzedByAI: Bool = true) {
        self.pageIndex = pageIndex
        self.notes = notes
        self.marks = marks
        self.analyzedByAI = analyzedByAI
    }

    /// 旧格式页面均来自 AI，缺少 analyzedByAI 时保留其已处理语义。
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        pageIndex = try values.decode(Int.self, forKey: .pageIndex)
        notes = try values.decode(String.self, forKey: .notes)
        marks = try values.decode([ManualPartMark].self, forKey: .marks)
        analyzedByAI = try values.decodeIfPresent(Bool.self, forKey: .analyzedByAI) ?? true
    }

    /// 确保页码、颜色引用、标记编号及坐标均能安全用于绘制和导出。
    func validated(pageCount: Int, colorIDs: Set<String>) throws -> Self {
        guard (0..<pageCount).contains(pageIndex), marks.count <= 80,
              Set(marks.map(\.id)).count == marks.count,
              marks.allSatisfy({
                  (1...80).contains($0.id) && !$0.part.isEmpty && !$0.reason.isEmpty
                      && colorIDs.contains($0.colorID)
                      && $0.x.isFinite && $0.y.isFinite
                      && (0...1).contains($0.x) && (0...1).contains($0.y)
              }) else {
            throw ManualStudyError.invalid("AI 返回的页码、零件颜色或标记位置无效，本页未保存。")
        }
        return self
    }
}

/// 每个项目独立保存的考证快照，原始 PDF 和标记始终一起持久化。
struct ManualStudyArchive: Codable, Equatable, Sendable {
    /// 存档格式版本，用于拒绝当前程序无法理解的文件。
    var formatVersion = 1
    var input = ManualStudyInput()
    var manualName = ""
    var manualSourceURL = ""
    var pdfData: Data?
    /// 生成当前考证时的输入快照；与正在编辑的 input 比较以识别过期结果。
    var researchInput: ManualStudyInput?
    var research: ManualResearchResult?
    var pages: [ManualPageResult] = []
    var model: AIModelSelection?
    var researchedAt: Date?

    /// 只有输入仍与生成时一致，才允许继续标记或导出考证结果。
    var researchIsCurrent: Bool { research != nil && researchInput == input }
    /// 只统计 AI 完成的页面，手动标记页不计入自动分析进度。
    var analyzedPageIndices: Set<Int> { Set(pages.filter(\.analyzedByAI).map(\.pageIndex)) }

    /// 更换说明书后清空页标记并使旧考证失效；保留旧考证对象供状态判断。
    mutating func replacePDF(_ data: Data, name: String, sourceURL: String) {
        pdfData = data
        manualName = name
        manualSourceURL = sourceURL
        researchInput = nil
        pages = []
    }

    /// 成功考证后记录输入、模型和时间，并清除依赖旧颜色编号的页面标记。
    mutating func applyResearch(_ result: ManualResearchResult, model: AIModelSelection) {
        research = result
        researchInput = input
        self.model = model
        researchedAt = Date()
        pages = []
    }

    /// 按页替换而非追加重复页，保持存档及报告的页码顺序。
    mutating func replacePage(_ result: ManualPageResult) {
        pages.removeAll { $0.pageIndex == result.pageIndex }
        pages.append(result)
        pages.sort { $0.pageIndex < $1.pageIndex }
    }
}

/// 网页来源和说明书下载共用的 URL 格式检查。
enum ManualStudyURL {
    /// 仅接受有主机且不携带用户名、密码的 HTTP(S) 地址。
    static func webURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
}

/// 可直接展示给用户的考证流程错误。
enum ManualStudyError: LocalizedError {
    case invalid(String)

    /// 将具体校验或处理失败原因交给统一错误提示。
    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        }
    }
}
