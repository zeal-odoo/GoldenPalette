// 说明书考证的工作界面：录入要求 → 导入说明书 → 联网考证 → 逐页标注 → 保存或导出。
// 本视图持有编辑草稿和异步任务状态；AI、存储及 PDF 处理分别委托给对应服务。
import SwiftUI
import PDFKit

/// 在主线程更新界面与 PDFKit 对象，并协调当前项目的考证流程。
@MainActor
struct ManualStudyView: View {
    @Environment(\.dismiss) private var dismiss
    // MARK: - 文档、编辑草稿与界面状态
    @State private var archive = ManualStudyArchive()
    // original 保持原文；preview 是随标记重建的显示副本，避免原文被累加批注。
    @State private var original: PDFDocument?
    @State private var preview: PDFDocument?
    @State private var searchResult: ManualSearchResult?
    @State private var pageIndex = 0
    @State private var sidebarTab = 0
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var exportFile: ManualPDFExport?
    @State private var isLoading = true
    /// 读取失败后禁止覆盖已有存档，等待用户处理原始文件。
    @State private var storageFailed = false
    @State private var isDirty = false
    /// 最近成功读取或保存时的输入，用于识别尚未保存的要求修改。
    @State private var baselineInput = ManualStudyInput()
    @State private var showCloseConfirmation = false
    @State private var status = ""
    @State private var errorMessage: String?
    /// 标识当前任务；旧任务完成或取消时不能清理新任务的状态。
    @State private var requestID: UUID?
    @State private var work: Task<Void, Never>?
    // 编辑文字与在 PDF 上放置位置分为两步，各自持有带页码的请求快照。
    @State private var editingMark: ManualMarkEditRequest?
    @State private var placingMark: ManualMarkEditRequest?
    @State private var mixingColor: ManualResearchColor?

    // MARK: - 项目上下文与复用的调色能力
    let projectID: UUID
    let projectName: String
    let configuration: AIConfiguration
    let canSave: Bool
    let generateRecipe: MixingGenerator
    let generateBlend: BlendMixingGenerator
    /// 将配方和考证出处交回主界面，始终保存到打开此窗口时的项目。
    let onSavePalette: (MixingPalette, String) -> Bool

    private let service = ManualResearchService()
    private let store = ManualStudyStore.shared
    /// 加载和后台操作都占用界面，避免同时修改同一份草稿。
    private var isBusy: Bool { requestID != nil || isLoading }
    /// 原始 PDF 的页数；尚未导入时为零。
    private var pageCount: Int { original?.pageCount ?? 0 }
    /// 按稳定页索引查找结果，不依赖存档数组中的位置。
    private var currentPage: ManualPageResult? { archive.pages.first { $0.pageIndex == pageIndex } }
    /// 批量识别只跳过 AI 已完成页，手动标记页仍可继续分析。
    private var remainingPages: [Int] {
        let done = archive.analyzedPageIndices
        return (0..<pageCount).filter { !done.contains($0) }
    }
    /// 只有当前要求对应的考证存在可用颜色，才允许给 PDF 分配颜色。
    private var canAnnotate: Bool {
        original != nil && archive.researchIsCurrent && !(archive.research?.colors.isEmpty ?? true)
    }

    /// 组合侧栏、文档和状态区，并集中连接文件选择器及编辑弹窗。
    var body: some View {
        VStack(spacing: 0) {
            header.padding(20)
            Divider()
            if let errorMessage {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle").foregroundColor(.orange)
                    Text(errorMessage).textSelection(.enabled)
                    Spacer()
                    Button("收起") { self.errorMessage = nil }
                }
                .font(.callout).padding(12).background(Color.orange.opacity(0.08))
                .accessibilityIdentifier("manualError")
            }
            if archive.research != nil && !archive.researchIsCurrent {
                Text("模型要求或说明书已变更。请重新考证，旧标记暂不显示和导出。")
                    .font(.callout).foregroundColor(.orange).padding(8)
            }
            HStack(spacing: 0) {
                sidebar.frame(width: 340)
                Divider()
                documentPanel
            }
            Divider()
            HStack {
                if isBusy {
                    ProgressView().controlSize(.small)
                    Text(isLoading ? "读取已保存的说明书…" : status)
                    Spacer()
                    if !isLoading { Button("取消") { work?.cancel() }.accessibilityIdentifier("manualCancelButton") }
                } else {
                    Text(status.isEmpty ? "先确定模型与主题，再导入说明书并考证配色。" : status)
                    Spacer()
                    Text(isDirty ? "有未保存修改" : "本地资料").foregroundColor(.secondary)
                }
            }
            .font(.callout).padding(12)
        }
        .frame(width: 1_120, height: 740)
        .interactiveDismissDisabled(isDirty || isBusy)
        .task { await loadArchive() }
        // 要求改变会使旧考证失效；取消未完成的定位，避免继续放置旧颜色。
        .onChange(of: archive.input) { value in
            if value != baselineInput { isDirty = true }
            placingMark = nil
            if archive.researchIsCurrent { refreshPreview() } else { preview = original }
        }
        .onDisappear {
            requestID = nil
            work?.cancel()
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url): importPDF(url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $isExporting, document: exportFile, contentType: .pdf,
            defaultFilename: "GOLDEN-涂装标注"
        ) { result in
            switch result {
            case .success: status = "已导出标注 PDF，附录包含颜色依据和未处理页码。"
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $editingMark) { request in
            ManualMarkEditor(request: request, colors: archive.research?.colors ?? []) { mark in
                saveMark(mark, request: request)
            }
        }
        .sheet(item: $mixingColor) { color in
            AIMixingView(
                projectName: "\(projectName) · \(color.name)",
                initialTarget: color.rgb ?? .initial,
                configuration: configuration,
                canSave: canSave,
                generateBlend: generateBlend,
                generateRecipe: generateRecipe
            ) { palette in
                onSavePalette(palette, mixingContext(for: color))
            }
        }
        .confirmationDialog("保存说明书的修改后关闭？", isPresented: $showCloseConfirmation) {
            Button("保存并关闭") { saveArchive(closeAfter: true) }
                .disabled(storageFailed || !canSave || isBusy)
            Button("放弃未保存修改", role: .destructive) { dismiss() }
            Button("返回", role: .cancel) {}
        } message: {
            Text("已经保存的 PDF、资料和标注会保留。")
        }
    }

    // MARK: - 界面区域
    /// 提供项目级保存、导出和带未保存修改检查的关闭入口。
    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("说明书与涂装考证").font(.title2.bold())
                Text(projectName).foregroundColor(.secondary)
            }
            Spacer()
            Button("保存") { saveArchive() }
                .disabled(isBusy || !canSave || storageFailed || !isDirty)
                .accessibilityIdentifier("manualSaveButton")
            Button("导出标注 PDF") { prepareExport() }
                .disabled(isBusy || !archive.researchIsCurrent || original == nil)
                .accessibilityIdentifier("manualExportButton")
            Button("关闭") {
                work?.cancel()
                if isDirty { showCloseConfirmation = true } else { dismiss() }
            }
            .accessibilityIdentifier("manualCloseButton")
        }
    }

    /// 在要求、配色与证据之间切换，保留右侧 PDF 的浏览位置。
    private var sidebar: some View {
        VStack(spacing: 12) {
            Picker("内容", selection: $sidebarTab) {
                Text("模型与说明书").tag(0)
                Text("配色").tag(1)
                Text("依据").tag(2)
            }
            .pickerStyle(.segmented).padding([.top, .horizontal], 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch sidebarTab {
                    case 1: colorPanel
                    case 2: evidencePanel
                    default: inputPanel
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
    }

    /// 编辑搜索条件、选择说明书并启动考证；处理过程中锁定输入。
    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("模型套件").font(.headline)
            TextField("品牌、货号、比例、型号", text: $archive.input.kit)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("manualKitField")
            Text("涂装要求").font(.headline)
            TextEditor(text: $archive.input.theme)
                .frame(height: 100)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.3)))
                .accessibilityIdentifier("manualThemeField")
            Text("例如：1944 年诺曼底、具体部队与车号；保留内饰原厂色。")
                .font(.caption).foregroundColor(.secondary)
            HStack {
                Button("AI 查找说明书") { findManual() }
                    .accessibilityIdentifier("manualSearchButton")
                Button("导入 PDF") { isImporting = true }
                    .accessibilityIdentifier("manualImportButton")
            }
            if !archive.manualName.isEmpty {
                Label(archive.manualName, systemImage: "doc.fill").font(.callout)
                Text("\(pageCount) 页 · 可重新导入替换")
                    .font(.caption).foregroundColor(.secondary)
                if let url = ManualStudyURL.webURL(archive.manualSourceURL) {
                    Link("说明书来源", destination: url)
                }
            }
            if let result = searchResult {
                Text(result.notes).font(.callout).textSelection(.enabled)
                ForEach(result.candidates) { candidate in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(candidate.title).font(.headline)
                        Text(candidate.matchNotes).font(.caption).textSelection(.enabled)
                        HStack {
                            if let url = candidate.pageLink { Link("核对来源", destination: url) }
                            if let url = candidate.pdfLink {
                                Button("使用此 PDF") { downloadPDF(url, candidate: candidate) }
                            }
                        }
                    }
                    .padding(10).background(Color.secondary.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            Divider()
            Button(archive.research == nil ? "AI 考证配色" : "重新考证配色") { researchColors() }
                .buttonStyle(.borderedProminent)
                .disabled(original == nil)
                .accessibilityIdentifier("manualResearchButton")
            Text("导入后可先翻到配色表页。考证会参考封面、当前页及可提取的文字，结合联网资料核对主题。重新考证成功后会清除旧标记。")
                .font(.caption).foregroundColor(.secondary)
            Text("分析时，所选说明书页面会发送给当前配置的 AI。")
                .font(.caption).foregroundColor(.secondary)
        }
        .disabled(isBusy || storageFailed || !canSave)
    }

    /// 展示考证颜色，并将具备 RGB 依据的颜色转交现有调色界面。
    @ViewBuilder
    private var colorPanel: some View {
        if let research = archive.research {
            Text(research.subject).font(.headline)
            Text(research.summary).font(.callout).textSelection(.enabled)
            if research.colors.isEmpty {
                Text("尚无可用的颜色结论。请到「依据」查看待确认问题，补充要求后重新考证。")
                    .foregroundColor(.secondary)
            }
            ForEach(research.colors) { color in
                ManualResearchColorCard(
                    color: color, sources: research.sources,
                    canMix: archive.researchIsCurrent && canSave && !isBusy
                ) { mixingColor = color }
            }
        } else {
            Text("导入说明书后，点击「AI 考证配色」。").foregroundColor(.secondary)
        }
    }

    /// 保留不确定项和原始资料入口，供用户独立核对 AI 的结论。
    @ViewBuilder
    private var evidencePanel: some View {
        Text("AI 检索结果需核对原始资料；“资料支持”表示模型找到了依据，并非人工认证。")
            .font(.caption).foregroundColor(.secondary)
        if let research = archive.research {
            ForEach(Array(research.uncertainties.enumerated()), id: \.offset) { _, value in
                Label(value, systemImage: "questionmark.circle").font(.callout)
            }
            ForEach(research.sources) { source in
                VStack(alignment: .leading, spacing: 6) {
                    Text("[\(source.id)] \(source.title)").font(.headline)
                    Text(source.publisher).font(.caption).foregroundColor(.secondary)
                    Text(source.summary).font(.callout).textSelection(.enabled)
                    if let url = source.link { Link("打开原始资料", destination: url) }
                }
                Divider()
            }
            if let date = archive.researchedAt {
                Text("检索时间：\(date.formatted(date: .numeric, time: .shortened))")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    /// 组织翻页、PDF 预览、自动标注、手动标记和当前页结果列表。
    private var documentPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Button { changePage(by: -1) } label: { Image(systemName: "chevron.left") }
                    .disabled(pageIndex == 0)
                Text(pageCount == 0 ? "尚未导入说明书" : "第 \(pageIndex + 1) / \(pageCount) 页")
                    .monospacedDigit().accessibilityIdentifier("manualPageLabel")
                Button { changePage(by: 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(pageIndex + 1 >= pageCount)
                Spacer()
                Text("AI 已处理 \(archive.analyzedPageIndices.count)/\(pageCount) 页").font(.caption).foregroundColor(.secondary)
            }
            .padding(12)
            if let preview {
                ManualPDFPreview(
                    document: preview, pageIndex: pageIndex,
                    onPlace: placingMark == nil ? nil : { page, point in placeMark(on: page, at: point) }
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.richtext").font(.system(size: 42)).foregroundColor(.secondary)
                    Text("从左侧查找说明书，或导入 PDF")
                    Text("支持扫描版；无法辨认的零件会标为待确认。")
                        .font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                Button(currentPage == nil ? "标注当前页" : "重新标注本页") { annotatePages([pageIndex]) }
                    .disabled(!canAnnotate || isBusy)
                    .accessibilityIdentifier("manualAnnotatePageButton")
                Button("继续标注剩余 \(remainingPages.count) 页") { annotatePages(remainingPages) }
                    .disabled(!canAnnotate || isBusy || remainingPages.isEmpty)
                Spacer()
                Button("手动加标记") { addMark() }
                    .disabled(!canAnnotate || isBusy || (currentPage?.marks.count ?? 0) >= 80)
                    .help("每页最多 80 个标记")
            }
            .padding(10)
            if placingMark != nil {
                HStack {
                    Text("点击说明书上的零件，放置此标记。").foregroundColor(.orange)
                    Spacer()
                    Button("取消定位") { placingMark = nil }
                }.font(.callout).padding(.horizontal, 12).padding(.bottom, 8)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let currentPage, archive.researchIsCurrent {
                        Text(currentPage.notes).font(.callout).textSelection(.enabled)
                        if currentPage.marks.isEmpty {
                            Text("本页没有可定位的涂装标记，请核对上方说明。").foregroundColor(.secondary)
                        }
                        ForEach(currentPage.marks) { mark in markRow(mark) }
                    } else {
                        Text("本页尚未处理。配色考证完成后，可逐页标注或处理剩余页。")
                            .font(.callout).foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            .frame(height: 170)
        }
    }

    /// 显示一个零件的颜色、依据及核对状态，并提供定位、编辑和删除操作。
    private func markRow(_ mark: ManualPartMark) -> some View {
        let color = archive.research?.colors.first { $0.id == mark.colorID }
        return HStack(alignment: .top, spacing: 8) {
            Circle().fill(color?.rgb?.color ?? .gray).frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(pageIndex + 1).\(mark.id) · \(mark.part) → \(color?.displayName ?? mark.colorID)")
                    .font(.callout.bold())
                Text("\(mark.step) · \(mark.reviewed ? "用户已核对" : "AI 标记待核对")\(mark.uncertain ? " · 对应关系有疑问" : "")")
                    .font(.caption).foregroundColor(mark.reviewed ? .secondary : .orange)
                Text(mark.reason).font(.caption).textSelection(.enabled)
            }
            Spacer()
            Button("定位") { placingMark = ManualMarkEditRequest(pageIndex: pageIndex, mark: mark) }
                .help("点击说明书调整标记位置")
            Button("编辑") { editingMark = ManualMarkEditRequest(pageIndex: pageIndex, mark: mark) }
            Button { removeMark(mark) } label: { Image(systemName: "trash") }
                .help("删除此标记")
        }
        .disabled(isBusy)
    }

    // MARK: - 读取、异步任务与结果提交
    /// 首次打开时恢复项目存档；校验失败后保留文件并禁止后续覆盖。
    private func loadArchive() async {
        guard isLoading else { return }
        defer { isLoading = false }
        do {
            if let saved = try await store.load(projectID: projectID) {
                try Task.checkCancellation()
                if let data = saved.pdfData {
                    original = try ManualPDF.open(data)
                    preview = try ManualPDF.annotatedDocument(for: saved)
                }
                archive = saved
                status = "已读取保存的说明书、考证资料和标记。"
            } else {
                archive.input.kit = projectName
            }
            baselineInput = archive.input
            isDirty = false
        } catch is CancellationError {
        } catch {
            storageFailed = true
            errorMessage = "读取已保存资料失败，已禁止覆盖：\(error.localizedDescription)"
        }
    }

    /// 串行启动操作并统一处理忙碌、取消和错误状态；具体流程负责提交成功结果。
    private func startWork(_ message: String, operation: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { return }
        let id = UUID()
        requestID = id
        status = message
        errorMessage = nil
        placingMark = nil
        work = Task { @MainActor in
            // 仅持有当前请求身份的任务可以清理状态，防止窗口关闭后的旧回调干扰界面。
            defer {
                if requestID == id { requestID = nil; work = nil }
            }
            do {
                try await operation()
            } catch is CancellationError {
                if requestID == id { status = "已取消；已完成的页面仍保留，可保存或继续。" }
            } catch {
                if requestID == id {
                    if Task.isCancelled {
                        status = "已取消；已完成的页面仍保留，可保存或继续。"
                    } else {
                        errorMessage = error.localizedDescription
                        status = "操作未完成，可重试。"
                    }
                }
            }
        }
    }

    /// 对输入取快照后搜索说明书，用户仍需核对候选的货号和版本。
    private func findManual() {
        let input = archive.input
        startWork("正在联网查找对应型号的说明书…") {
            let result = try await service.searchManual(for: input, configuration: configuration)
            try Task.checkCancellation()
            searchResult = result
            status = result.candidates.isEmpty ? "没有找到可核对的说明书，可直接导入 PDF。" : "找到候选说明书，请核对货号与版本后选择。"
        }
    }

    /// 读取文件选择器返回的本地文件，随后统一走 PDF 接收流程。
    private func importPDF(_ url: URL) {
        startWork("正在导入说明书…") {
            let data = try ManualStudyStore.importPDF(at: url)
            try acceptPDF(data, name: url.lastPathComponent, sourceURL: "")
        }
    }

    /// 下载用户选中的候选，保留来源网页供后续存档和导出追溯。
    private func downloadPDF(_ url: URL, candidate: ManualCandidate) {
        startWork("正在下载说明书…") {
            let data = try await ManualStudyStore.downloadPDF(from: url)
            try Task.checkCancellation()
            try acceptPDF(data, name: candidate.title, sourceURL: candidate.pageURL)
        }
    }

    /// 先验证新 PDF，再替换草稿；失败时保留原有说明书和标记。
    private func acceptPDF(_ data: Data, name: String, sourceURL: String) throws {
        let document = try ManualPDF.open(data)
        archive.replacePDF(data, name: name, sourceURL: sourceURL)
        original = document
        preview = document
        pageIndex = 0
        isDirty = true
        status = "已导入 \(document.pageCount) 页。可翻到配色表页后开始考证。"
    }

    /// 发送封面、当前页和文本摘录；当前页就是封面时自动去重。
    private func researchColors() {
        guard let original else { return }
        let input = archive.input
        let indices = Array(Set([0, pageIndex])).sorted()
        startWork("正在联网考证配色与适用范围…") {
            let images = try indices.map { index -> Data in
                guard let page = original.page(at: index) else { throw ManualStudyError.invalid("说明书页码无效。") }
                return try ManualPDF.image(of: page)
            }
            let result = try await service.research(
                input: input, manualText: ManualPDF.textExcerpt(of: original),
                imagePageNumbers: indices.map { $0 + 1 }, images: images, configuration: configuration
            )
            // 请求成功且未取消后才替换考证，失败重试不会提前丢弃既有结果。
            try Task.checkCancellation()
            archive.applyResearch(result, model: configuration.model)
            preview = original
            sidebarTab = result.colors.isEmpty ? 2 : 1
            isDirty = true
            status = "考证完成，请核对颜色与来源，再标注说明书。"
        }
    }

    /// 顺序识别指定页面，每完成一页立即保留结果，取消时可继续剩余页。
    private func annotatePages(_ indices: [Int]) {
        guard let original, let research = archive.research, canAnnotate, !indices.isEmpty else { return }
        let input = archive.input
        startWork("准备识别说明书页面…") {
            for (offset, index) in indices.enumerated() {
                try Task.checkCancellation()
                guard let page = original.page(at: index) else { throw ManualStudyError.invalid("说明书页码无效。") }
                status = "正在标注第 \(index + 1) 页（本次 \(offset + 1)/\(indices.count)）…"
                let result = try await service.annotate(
                    input: input, research: research, pageIndex: index, pageCount: original.pageCount,
                    pageText: page.string ?? "", image: ManualPDF.image(of: page), configuration: configuration
                )
                try Task.checkCancellation()
                archive.replacePage(result)
                pageIndex = index
                isDirty = true
                preview = try ManualPDF.annotatedDocument(for: archive)
            }
            status = "本次标注完成。请核对零件与位置；可点「定位」修正。"
        }
    }

    /// 保存当前快照，成功后更新已保存基线；可用于“保存并关闭”。
    private func saveArchive(closeAfter: Bool = false) {
        guard canSave, !storageFailed else { return }
        let snapshot = archive
        startWork("正在保存说明书与标注…") {
            try await store.save(snapshot, projectID: projectID)
            try Task.checkCancellation()
            baselineInput = snapshot.input
            isDirty = false
            status = "已保存到此项目，下次打开可继续。"
            if closeAfter { dismiss() }
        }
    }

    /// 先生成带附录的 PDF 数据，再交给系统导出器选择目标位置。
    private func prepareExport() {
        startWork("正在生成标注 PDF 与考证附录…") {
            await Task.yield()
            try Task.checkCancellation()
            exportFile = ManualPDFExport(data: try ManualPDF.export(archive))
            isExporting = true
            status = "选择标注 PDF 的保存位置。"
        }
    }

    // MARK: - 翻页与手工校正
    /// 限制翻页范围，并取消旧页面的待放置标记。
    private func changePage(by delta: Int) {
        pageIndex = min(max(pageIndex + delta, 0), max(0, pageCount - 1))
        placingMark = nil
    }

    /// 分配 1...80 中最小的空闲编号；先填写信息，再点击 PDF 定位。
    private func addMark() {
        let usedIDs = Set(currentPage?.marks.map(\.id) ?? [])
        guard let color = archive.research?.colors.first,
              let id = (1...80).first(where: { !usedIDs.contains($0) }) else { return }
        let mark = ManualPartMark(
            id: id,
            part: "", step: "", colorID: color.id, x: 0.5, y: 0.5,
            reason: "用户手动标注", uncertain: false
        )
        editingMark = ManualMarkEditRequest(pageIndex: pageIndex, mark: mark, isNew: true)
    }

    /// 按页和标记编号保存编辑；手动新建页不会被算作 AI 已完成页。
    private func saveMark(_ mark: ManualPartMark, request: ManualMarkEditRequest) {
        var page = archive.pages.first { $0.pageIndex == request.pageIndex }
            ?? ManualPageResult(pageIndex: request.pageIndex, notes: "用户手动标注；本页尚未经过 AI 全页识别。", marks: [], analyzedByAI: false)
        page.marks.removeAll { $0.id == mark.id }
        page.marks.append(mark)
        page.marks.sort { $0.id < $1.id }
        archive.replacePage(page)
        isDirty = true
        refreshPreview()
        if request.isNew { placingMark = ManualMarkEditRequest(pageIndex: request.pageIndex, mark: mark) }
    }

    /// 只接受目标页上的点击；位置变化后撤销此前的人工核对状态。
    private func placeMark(on index: Int, at point: CGPoint) {
        guard let request = placingMark, request.pageIndex == index else { return }
        var mark = request.mark
        mark.x = point.x
        mark.y = point.y
        mark.reviewed = false
        placingMark = nil
        saveMark(mark, request: request)
    }

    /// 删除当前页标记后重建预览，保留该页已有的分析状态。
    private func removeMark(_ mark: ManualPartMark) {
        guard var page = currentPage else { return }
        page.marks.removeAll { $0.id == mark.id }
        archive.replacePage(page)
        placingMark = nil
        isDirty = true
        refreshPreview()
    }

    /// 从存档中的原始 PDF 重建带标记副本，错误通过界面统一展示。
    private func refreshPreview() {
        do { preview = try ManualPDF.annotatedDocument(for: archive) }
        catch { errorMessage = error.localizedDescription }
    }

    /// 把模型主题、颜色依据和来源链接附到保存的调色方法中，保留跨功能的出处。
    private func mixingContext(for color: ManualResearchColor) -> String {
        let sources = archive.research?.sources.filter { color.sourceIDs.contains($0.id) } ?? []
        return """
        说明书考证参考：\(archive.input.kit)
        主题：\(archive.input.theme)
        参考色：\(color.displayName)（\(color.evidence.title)）
        \(color.explanation)
        RGB 为屏幕近似：\(color.rgbBasis)。实际目标以已保存配方为准。
        \(sources.map { "[\($0.id)] \($0.title) \($0.url)" }.joined(separator: "\n"))
        """
    }
}

/// 弹窗和点击定位共用的编辑快照，防止翻页后误改另一页的同编号标记。
struct ManualMarkEditRequest: Identifiable {
    let pageIndex: Int
    let mark: ManualPartMark
    var isNew = false
    /// 组合页索引与页内编号，作为 SwiftUI 弹窗的稳定身份。
    var id: String { "\(pageIndex).\(mark.id)" }
}

/// 编辑单个标记的局部草稿，只有确认保存才回传给父视图。
@MainActor
private struct ManualMarkEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ManualPartMark
    let request: ManualMarkEditRequest
    let colors: [ManualResearchColor]
    let onSave: (ManualPartMark) -> Void

    /// 使用请求内容初始化独立草稿，取消弹窗时不会写回存档。
    init(request: ManualMarkEditRequest, colors: [ManualResearchColor], onSave: @escaping (ManualPartMark) -> Void) {
        self.request = request
        self.colors = colors
        self.onSave = onSave
        _draft = State(initialValue: request.mark)
    }

    /// 新标记尚未定位，因此在完成首次放置前不开放人工核对开关。
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("第 \(request.pageIndex + 1) 页 · 零件标记").font(.title2.bold())
            TextField("零件号或部位（如 A12 / 轮胎）", text: $draft.part)
            TextField("装配步骤", text: $draft.step)
            Picker("涂装颜色", selection: $draft.colorID) {
                ForEach(colors) { Text($0.displayName).tag($0.id) }
            }
            Text("标注说明").font(.headline)
            TextEditor(text: $draft.reason).frame(height: 90)
            Toggle("对应关系仍有疑问", isOn: $draft.uncertain)
            Toggle("我已核对零件、颜色和位置", isOn: $draft.reviewed)
                .disabled(request.isNew)
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button(request.isNew ? "添加并定位" : "保存修改") {
                    draft.part = draft.part.trimmingCharacters(in: .whitespacesAndNewlines)
                    if draft.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        draft.reason = "用户手动标注"
                    }
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(24).frame(width: 440)
    }
}

/// 展示颜色用途和证据来源，并按 RGB 是否可用决定能否试调。
private struct ManualResearchColorCard: View {
    let color: ManualResearchColor
    let sources: [ManualEvidence]
    let canMix: Bool
    let onMix: () -> Void

    /// 将详细依据折叠展示，保持颜色列表易于浏览。
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 5).fill(color.rgb?.color ?? .gray)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(color.id) · \(color.displayName)").font(.headline)
                    Text(color.evidence.title).font(.caption)
                        .foregroundColor(color.evidence == .supported ? .secondary : .orange)
                }
            }
            Text(color.usage).font(.callout)
            DisclosureGroup("选色依据与 RGB 说明") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(color.explanation)
                    Text("屏幕近似：\(color.rgb?.hex ?? "未知")；\(color.rgbBasis)")
                    ForEach(sources.filter { color.sourceIDs.contains($0.id) }) { source in
                        if let url = source.link { Link("[\(source.id)] \(source.title)", destination: url) }
                    }
                }
                .font(.caption).textSelection(.enabled).padding(.top, 6)
            }
            Button("用 GOLDEN 试调此色", action: onMix)
                .disabled(!canMix || color.rgb == nil)
            if color.rgb == nil {
                Text("缺少可靠的 RGB 换算依据，暂不生成调色配方。").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(12).background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
