// 说明书考证回归测试：覆盖证据引用、输入有效性、PDF 坐标、导出及存档。
// AI 集成使用临时假 CLI 和固定 JSON，避免测试依赖真实账户或联网结果。
import AppKit
import Foundation
import PDFKit
import Testing
@testable import Golden调色

/// 验证考证数据和文档处理的关键边界，测试文件均放在独立临时目录。
struct ManualStudyTests {
    /// “资料支持”必须引用有效来源，重复编号或非网页来源不得通过校验。
    @Test
    func testResearchRequiresTraceableEvidenceAndValidReferences() throws {
        let valid = researchFixture()
        #expect(try valid.validated() == valid)
        #expect(throws: (any Error).self) { try researchFixture(sourceIDs: []).validated() }
        #expect(throws: (any Error).self) { try researchFixture(sourceIDs: ["missing"]).validated() }
        #expect(throws: (any Error).self) { try researchFixture(sourceURL: "file:///tmp/private").validated() }
        #expect(try researchFixture(sourceIDs: [], evidence: .inferred).validated().colors.count == 1)
        let duplicate = ManualResearchResult(
            subject: valid.subject, summary: valid.summary,
            colors: valid.colors + valid.colors, sources: valid.sources, uncertainties: []
        )
        #expect(throws: (any Error).self) { try duplicate.validated() }
    }

    /// 越界的 AI RGB 应被拒绝，不能静默夹紧后冒充有效考证颜色。
    @Test
    func testUnsupportedPreviewRGBIsRejected() throws {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(researchFixture())) as? [String: Any])
        var colors = try #require(object["colors"] as? [[String: Any]])
        colors[0]["rgb"] = ["red": 256, "green": 1, "blue": 1]
        object["colors"] = colors
        let result = try JSONDecoder().decode(
            ManualResearchResult.self, from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(throws: (any Error).self) { try result.validated() }
    }

    /// 标记只能使用既有颜色、有效页码、唯一编号和有限的归一化坐标。
    @Test
    func testPageRejectsInventedColorsAndInvalidCoordinates() throws {
        var mark = markFixture()
        /// 用固定页数和颜色集合验证一个候选标记，便于逐项构造反例。
        func validate(_ mark: ManualPartMark, pageIndex: Int = 0) throws -> ManualPageResult {
            try ManualPageResult(pageIndex: pageIndex, notes: "", marks: [mark])
                .validated(pageCount: 2, colorIDs: ["C1"])
        }
        #expect(try validate(mark).marks.count == 1)
        mark.colorID = "invented"
        #expect(throws: (any Error).self) { try validate(mark) }
        mark.colorID = "C1"
        mark.x = 1.1
        #expect(throws: (any Error).self) { try validate(mark) }
        mark.x = .nan
        #expect(throws: (any Error).self) { try validate(mark) }
        mark.x = 0.5
        #expect(throws: (any Error).self) { try validate(mark, pageIndex: 2) }
        for id in [0, 81, Int.max] {
            let unsafe = ManualPartMark(id: id, part: "A12", step: "", colorID: "C1",
                                        x: 0.5, y: 0.5, reason: "Source", uncertain: false)
            #expect(throws: (any Error).self) { try validate(unsafe) }
        }
        let duplicated = ManualPageResult(pageIndex: 0, notes: "", marks: [mark, mark])
        #expect(throws: (any Error).self) { try duplicated.validated(pageCount: 1, colorIDs: ["C1"]) }
    }

    /// 要求或 PDF 变化使旧结果失效；手工添加标记不能增加 AI 完成页数。
    @Test
    func testThemeOrPDFChangeInvalidatesOldMarksAndManualEditsDoNotCompletePage() throws {
        var archive = archiveFixture(pdf: try pdfFixture())
        #expect(archive.researchIsCurrent)
        archive.input.theme = "Different period"
        #expect(!archive.researchIsCurrent)
        archive.input = try #require(archive.researchInput)
        #expect(archive.researchIsCurrent)
        archive.replacePage(ManualPageResult(pageIndex: 1, notes: "Manual", marks: [markFixture()], analyzedByAI: false))
        #expect(archive.analyzedPageIndices == [0])
        #expect(ManualPDF.reportText(for: archive, pageCount: 2).contains("未处理页：2"))
        archive.replacePDF(try pdfFixture(), name: "New manual", sourceURL: "")
        #expect(archive.pages.isEmpty)
        #expect(!archive.researchIsCurrent)
    }

    /// 搜索说明书允许暂不填写主题，但考证与外部地址仍须满足各自规则。
    @Test
    func testSearchCanRunBeforeThemeIsChosenAndRejectsNonWebLinks() throws {
        let input = ManualStudyInput(kit: "Tamiya 35227", theme: "")
        #expect(try input.validated(requireTheme: false).kit == input.kit)
        #expect(throws: (any Error).self) { try input.validated() }
        for address in ["file:///tmp/a.pdf", "javascript:alert(1)", "https://user:password@example.com/a", "https:///"] {
            #expect(ManualStudyURL.webURL(address) == nil)
        }
        #expect(ManualStudyURL.webURL("https://example.com/manual.pdf") != nil)
    }

    /// 模型的文字声明、进行中或失败的搜索事件都不能冒充搜索完成。
    @Test
    func testActualSearchEventIsRequiredInsteadOfModelClaim() {
        let claim = Data(#"{"type":"item.completed","item":{"type":"agent_message","text":"web_search completed"}}"#.utf8)
        let started = Data(#"{"type":"item.started","item":{"type":"web_search","status":"in_progress"}}"#.utf8)
        let failed = Data(#"{"type":"item.completed","item":{"type":"web_search","status":"failed"}}"#.utf8)
        let completed = Data(#"{"type":"item.completed","item":{"type":"web_search","query":"manual"}}"#.utf8)
        #expect(!CodexMixingService.containsCompletedWebSearch(claim))
        #expect(!CodexMixingService.containsCompletedWebSearch(started))
        #expect(!CodexMixingService.containsCompletedWebSearch(failed))
        #expect(CodexMixingService.containsCompletedWebSearch(completed))
    }

    /// 只有考证请求开启搜索和附图，普通调色继续沿用原有调用参数。
    @Test
    func testResearchEnablesSearchAndAttachesImagesWithoutChangingMixingDefaults() throws {
        let root = URL(fileURLWithPath: "/tmp/manual with spaces")
        let image = root.appendingPathComponent("page 1.jpg")
        let args = CodexMixingService.arguments(
            schema: root.appendingPathComponent("schema.json"),
            output: root.appendingPathComponent("result.json"), directory: root,
            model: AIModelSelection(modelID: "chosen-model", reasoningEffort: .medium),
            webSearch: true, images: [image]
        )
        #expect(args.contains("web_search=\"live\""))
        #expect(args.contains("--json"))
        #expect(args.contains("chosen-model"))
        #expect(args.contains("read-only"))
        #expect(args.contains("shell_tool"))
        #expect(args.last == "-")
        let index = try #require(args.firstIndex(of: "--image"))
        #expect(args[index + 1] == image.path)
        let defaults = CodexMixingService.arguments(schema: root, output: root, directory: root)
        #expect(defaults.contains("web_search=\"disabled\""))
        #expect(!defaults.contains("--image"))
        #expect(!defaults.contains("--json"))
    }

    /// 同时检查坐标映射和渲染图像取样，覆盖四种旋转及非零裁切原点。
    @Test
    func testPDFMarkerCoordinatesAndVisionImagesRespectRotationAndCropOrigin() throws {
        // 用已知蓝色块的中心作参照，防止仅验证变换可逆却未验证实际绘制位置。
        // The blue patch is at PDF point (90,95) within crop box (40,70,200,100).
        let expected: [(Int, Double, Double)] = [(0, 0.25, 0.75), (90, 0.25, 0.25), (180, 0.75, 0.25), (270, 0.75, 0.75)]
        for (rotation, x, y) in expected {
            let document = try ManualPDF.open(pdfFixture(rotation: rotation))
            let page = try #require(document.page(at: 0))
            let point = ManualPDF.pagePoint(x: x, y: y, on: page)
            #expect(abs(point.x - 90) < 0.001)
            #expect(abs(point.y - 95) < 0.001)
            let image = try #require(NSBitmapImageRep(data: ManualPDF.image(of: page)))
            let sampled = try #require(image.colorAt(x: Int(x * Double(image.pixelsWide)), y: Int(y * Double(image.pixelsHigh)))?.usingColorSpace(.deviceRGB))
            #expect(sampled.blueComponent > 0.7)
            #expect(sampled.redComponent < 0.3)
        }
    }

    /// 导出的标记位置、零件和来源可追溯，且原始 PDF 字节及页面批注不被修改。
    @Test
    func testAnnotatedExportPreservesOriginalAndIncludesEvidenceAndCoverage() throws {
        let raw = try pdfFixture()
        let archive = archiveFixture(pdf: raw)
        let preview = try ManualPDF.annotatedDocument(for: archive)
        let first = try #require(preview.page(at: 0))
        let circle = try #require(first.annotations.first { $0.type == "Circle" })
        #expect(abs(circle.bounds.midX - 90) < 0.001)
        #expect(abs(circle.bounds.midY - 95) < 0.001)
        #expect(circle.contents?.contains("A12") == true)
        let exported = try #require(PDFDocument(data: ManualPDF.export(archive)))
        #expect(exported.pageCount > 2)
        #expect(exported.string?.contains("https://example.com/archive") == true)
        #expect(exported.string?.contains("A12") == true)
        #expect(try ManualPDF.open(raw).page(at: 0)?.annotations.isEmpty == true)
        #expect(archive.pdfData == raw)
    }

    /// 存档往返保留原文和标记身份，项目彼此隔离，损坏文件不能被读取操作覆盖。
    @Test
    func testArchivePersistsOriginalPDFAndStableMarkIDs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ManualArchive-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ManualStudyStore(root: root)
        let id = UUID()
        let archive = archiveFixture(pdf: try pdfFixture())
        try await store.save(archive, projectID: id)
        let loaded = try await store.load(projectID: id)
        #expect(loaded == archive)
        #expect(loaded?.pages.first?.marks.first?.id == 1)
        let other = try await store.load(projectID: UUID())
        #expect(other == nil)
        let path = root.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        let bad = Data("corrupt original".utf8)
        try bad.write(to: path)
        await #expect(throws: (any Error).self) { try await store.load(projectID: id) }
        #expect(try Data(contentsOf: path) == bad)
    }

    /// 网页内容、超限数据和空文件都不能作为说明书继续处理。
    @Test
    func testPDFImportRejectsNonPDFAndOversizedData() throws {
        #expect(throws: (any Error).self) { try ManualPDF.open(Data("<html>login</html>".utf8)) }
        #expect(throws: (any Error).self) { try ManualPDF.open(Data(repeating: 0, count: ManualStudyStore.maximumPDFBytes + 1)) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ManualInvalid-\(UUID()).pdf")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root)
        #expect(throws: (any Error).self) { try ManualStudyStore.importPDF(at: root) }
    }

    /// 假 CLI 验证真实调用边界：搜索事件、附图、页码以及强制撤销 AI 自我核对。
    @Test
    func testServiceUsesSearchTraceAndPageImageAndDoesNotSelfApproveMarks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Manual CLI-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("fake-codex")
        // 脚本仅记录参数、复制测试响应和事件；不发起真实 AI 或网络请求。
        let script = #"""
        #!/bin/sh
        set -eu
        fixture_dir=$(dirname "$0")
        printf '%s\n' "$@" > "$fixture_dir/arguments.txt"
        output_path=''
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --output-last-message) output_path=$2; shift ;;
                --image) cp "$2" "$fixture_dir/received-image.jpg"; shift ;;
            esac
            shift
        done
        cat > "$fixture_dir/prompt.txt"
        cp "$fixture_dir/response.json" "$output_path"
        cat "$fixture_dir/events.jsonl"
        """#
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let configuration = AIConfiguration(
            model: AIModelSelection(modelID: "manual-fixture-model", reasoningEffort: .low),
            executablePath: executable.path
        )
        let input = ManualStudyInput(kit: "Example kit 123", theme: "1944 specific vehicle")
        let events = root.appendingPathComponent("events.jsonl")
        let response = root.appendingPathComponent("response.json")
        try Data(#"{"type":"item.completed","item":{"type":"web_search","query":"kit manual"}}"#.utf8).write(to: events)
        let search = ManualSearchResult(candidates: [
            ManualCandidate(title: "Kit 123", pageURL: "https://example.com/kit", pdfURL: "https://example.com/manual.pdf", matchNotes: "Exact kit")
        ], notes: "Version checked")
        try JSONEncoder().encode(search).write(to: response)
        let service = ManualResearchService()
        #expect(try await service.searchManual(for: input, configuration: configuration) == search)
        try Data().write(to: events)
        await #expect(throws: (any Error).self) { try await service.searchManual(for: input, configuration: configuration) }
        var mark = markFixture()
        mark.reviewed = true
        let page = ManualPageResult(pageIndex: 1, notes: "Fixture page", marks: [mark])
        try JSONEncoder().encode(page).write(to: response)
        let image = Data([0xff, 0xd8, 0xff, 0xd9])
        let annotated = try await service.annotate(
            input: input, research: researchFixture(), pageIndex: 1, pageCount: 2,
            pageText: "A12", image: image, configuration: configuration
        )
        #expect(annotated.marks.first?.reviewed == false)
        #expect(annotated.analyzedByAI)
        #expect(try Data(contentsOf: root.appendingPathComponent("received-image.jpg")) == image)
        let arguments = try String(contentsOf: root.appendingPathComponent("arguments.txt"), encoding: .utf8)
        #expect(arguments.contains("web_search=\"disabled\""))
        let prompt = try String(contentsOf: root.appendingPathComponent("prompt.txt"), encoding: .utf8)
        #expect(prompt.contains("pageIndex=1"))
        #expect(prompt.contains(input.theme))
        #expect(prompt.contains("C1"))
        await #expect(throws: (any Error).self) {
            try await service.annotate(
                input: input, research: researchFixture(), pageIndex: 0, pageCount: 2,
                pageText: "", image: image, configuration: configuration
            )
        }
    }

    // MARK: - 固定测试资料
    /// 构造一条颜色和一条来源，可替换引用及等级以测试失败路径。
    private func researchFixture(sourceIDs: [String] = ["S1"], evidence: ManualEvidenceLevel = .supported,
                                 sourceURL: String = "https://example.com/archive") -> ManualResearchResult {
        ManualResearchResult(
            subject: "Fixture subject", summary: "Documented theme",
            colors: [ManualResearchColor(
                id: "C1", name: "Fixture blue", standard: "Example 1", usage: "A12",
                rgb: MixingTarget(red: 32, green: 64, blue: 220), rgbBasis: "Approximate screen swatch",
                evidence: evidence, explanation: "Applies to the specified vehicle", sourceIDs: sourceIDs
            )],
            sources: [ManualEvidence(
                id: "S1", title: "Archive record", publisher: "Fixture publisher",
                url: sourceURL, summary: "Primary record about the specific vehicle"
            )], uncertainties: ["Ageing is not represented"]
        )
    }

    /// 创建与 PDF 蓝色块对应的稳定标记，供坐标、存档和导出测试共用。
    private func markFixture() -> ManualPartMark {
        ManualPartMark(id: 1, part: "A12", step: "Step 1", colorID: "C1",
                       x: 0.25, y: 0.75, reason: "Source S1", uncertain: false)
    }

    /// 组合原文、考证及第一页结果，模拟已完成部分分析的项目。
    private func archiveFixture(pdf: Data) -> ManualStudyArchive {
        var archive = ManualStudyArchive()
        archive.input = ManualStudyInput(kit: "Example kit", theme: "Specific period")
        archive.replacePDF(pdf, name: "fixture.pdf", sourceURL: "")
        archive.applyResearch(researchFixture(), model: AIModelSelection())
        archive.replacePage(ManualPageResult(pageIndex: 0, notes: "Page checked", marks: [markFixture()]))
        return archive
    }

    /// 生成两页 PDF，并对第一页设置裁切和旋转，所有几何参照均可确定。
    private func pdfFixture(rotation: Int = 0) throws -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 300, height: 240)
        let consumer = try #require(CGDataConsumer(data: data))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        for _ in 0..<2 {
            context.beginPDFPage(nil)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(box)
            context.setFillColor(NSColor(srgbRed: 0.1, green: 0.2, blue: 0.9, alpha: 1).cgColor)
            context.fill(CGRect(x: 80, y: 85, width: 20, height: 20))
            context.endPDFPage()
        }
        context.closePDF()
        let document = try #require(PDFDocument(data: data as Data))
        let page = try #require(document.page(at: 0))
        page.setBounds(CGRect(x: 40, y: 70, width: 200, height: 100), for: .cropBox)
        page.rotation = rotation
        return try #require(document.dataRepresentation())
    }
}
