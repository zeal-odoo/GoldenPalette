// PDF 处理与 SwiftUI 桥接：解析、页面渲染、坐标换算、标注及带考证附录的导出。
// 所有定位都使用同一显示变换，确保 AI 图像、预览点击和导出的圆点位置一致。
import AppKit
import CoreText
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// 无状态的 PDF 工具，原始 PDF 数据始终由考证存档持有。
enum ManualPDF {
    /// 检查文件大小、加密状态、页数及页面尺寸，拒绝无法可靠渲染的文档。
    static func open(_ data: Data) throws -> PDFDocument {
        guard data.count <= ManualStudyStore.maximumPDFBytes, let document = PDFDocument(data: data) else {
            throw ManualStudyError.invalid("文件不是可读取的 PDF。网页下载可能返回了登录页，请手动下载说明书后导入。")
        }
        guard !document.isLocked else {
            throw ManualStudyError.invalid("此 PDF 已加密，请先解锁后再导入。")
        }
        guard (1...200).contains(document.pageCount) else {
            throw ManualStudyError.invalid("支持 1–200 页的说明书；较大的文件请先拆分。")
        }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let reference = page.pageRef else {
                throw ManualStudyError.invalid("说明书第 \(index + 1) 页无法读取。")
            }
            let bounds = reference.getBoxRect(.cropBox)
            guard bounds.width.isFinite, bounds.height.isFinite,
                  (1...20_000).contains(bounds.width), (1...20_000).contains(bounds.height) else {
                throw ManualStudyError.invalid("说明书第 \(index + 1) 页的尺寸无效。")
            }
        }
        return document
    }

    /// 计算用户看到的裁切区域尺寸，横转 90° 或 270° 时交换宽高。
    static func displayedSize(of page: PDFPage) -> CGSize {
        let bounds = page.pageRef?.getBoxRect(.cropBox) ?? page.bounds(for: .cropBox)
        let rotation = ((page.rotation % 360) + 360) % 360
        return rotation == 90 || rotation == 270
            ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
    }

    /// 统一处理页面旋转与非零裁切原点，供图像渲染和双向坐标转换复用。
    /// The same transform is used for vision images, PDF markers, and user clicks.
    /// This handles rotated pages and crop boxes whose origin is not (0, 0).
    static func displayTransform(for page: PDFPage) -> CGAffineTransform {
        page.pageRef?.getDrawingTransform(
            .cropBox, rect: CGRect(origin: .zero, size: displayedSize(of: page)),
            rotate: 0, preserveAspectRatio: true
        ) ?? .identity
    }

    /// 将左上原点的归一化坐标转换为 PDF 页面坐标，包含纵轴翻转和逆变换。
    static func pagePoint(x: Double, y: Double, on page: PDFPage) -> CGPoint {
        let size = displayedSize(of: page)
        return CGPoint(x: x * size.width, y: (1 - y) * size.height)
            .applying(displayTransform(for: page).inverted())
    }

    /// 将 PDF 点击位置转换回 0...1 的图像坐标，与 AI 输出采用同一约定。
    static func normalizedPoint(_ point: CGPoint, on page: PDFPage) -> CGPoint {
        let displayed = point.applying(displayTransform(for: page))
        let size = displayedSize(of: page)
        return CGPoint(x: displayed.x / size.width, y: 1 - displayed.y / size.height)
    }

    /// 将页面和可见原有批注渲染成白底 JPEG，最长边固定为 2400 像素。
    static func image(of page: PDFPage) throws -> Data {
        let size = displayedSize(of: page)
        let scale = 2_400 / max(size.width, size.height)
        let width = max(1, Int((size.width * scale).rounded()))
        let height = max(1, Int((size.height * scale).rounded()))
        guard let reference = page.pageRef,
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else {
            throw ManualStudyError.invalid("无法生成说明书页面图像。")
        }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: CGFloat(width) / size.width, y: CGFloat(height) / size.height)
        context.concatenate(displayTransform(for: page))
        context.drawPDFPage(reference)
        for annotation in page.annotations where annotation.shouldDisplay {
            annotation.draw(with: .mediaBox, in: context)
        }
        guard let image = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(
                using: .jpeg, properties: [.compressionFactor: 0.88]
              ) else {
            throw ManualStudyError.invalid("说明书图像编码失败。")
        }
        return data
    }

    /// 提取最多 32000 字符并附上页码；扫描件可没有文本，仍可使用页面图像。
    static func textExcerpt(of document: PDFDocument) -> String {
        var result = ""
        for index in 0..<document.pageCount {
            result += "\n[第 \(index + 1) 页]\n" + (document.page(at: index)?.string ?? "")
            if result.count >= 32_000 { return String(result.prefix(32_000)) }
        }
        return result
    }

    /// 从原始数据重建副本后附加标记，避免多次刷新时重复叠加或改写原文。
    static func annotatedDocument(for archive: ManualStudyArchive) throws -> PDFDocument {
        guard let data = archive.pdfData else { throw ManualStudyError.invalid("请先导入说明书 PDF。") }
        let document = try open(data)
        // 输入或说明书变更后只显示原文，防止过期考证继续出现在预览中。
        guard archive.researchIsCurrent, let research = archive.research else { return document }
        _ = try research.validated()
        let colors = Dictionary(uniqueKeysWithValues: research.colors.map { ($0.id, $0) })
        for result in archive.pages {
            _ = try result.validated(pageCount: document.pageCount, colorIDs: Set(colors.keys))
            guard let page = document.page(at: result.pageIndex) else { continue }
            for mark in result.marks {
                guard let color = colors[mark.colorID] else { continue }
                let point = pagePoint(x: mark.x, y: mark.y, on: page)
                let swatch = color.rgb.map {
                    NSColor(srgbRed: Double($0.red) / 255, green: Double($0.green) / 255,
                            blue: Double($0.blue) / 255, alpha: 1)
                } ?? NSColor.systemGray
                // “页码.页内编号”同时连接 PDF 圆点、侧栏列表与导出附录。
                let tag = "\(result.pageIndex + 1).\(mark.id)"
                let circle = PDFAnnotation(
                    bounds: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12),
                    forType: .circle, withProperties: nil
                )
                circle.interiorColor = swatch
                // 橙色边框提示待人工核对；颜色 RGB 未知时圆点使用灰色占位。
                circle.color = mark.reviewed ? .black : .systemOrange
                circle.border = PDFBorder()
                circle.border?.lineWidth = 1.5
                circle.contents = "\(tag) · \(mark.part) → \(color.displayName)\n\(color.evidence.title)\n\(mark.reason)"
                circle.userName = "GOLDEN"
                page.addAnnotation(circle)

                let bounds = page.bounds(for: .cropBox)
                let label = PDFAnnotation(
                    bounds: CGRect(
                        x: min(max(bounds.minX, point.x + 8), bounds.maxX - 48),
                        y: min(max(bounds.minY, point.y - 6), bounds.maxY - 14),
                        width: 48, height: 14
                    ),
                    forType: .freeText, withProperties: nil
                )
                label.contents = tag
                label.font = NSFont.boldSystemFont(ofSize: 10)
                label.fontColor = .black
                label.color = NSColor.white.withAlphaComponent(0.9)
                label.userName = "GOLDEN"
                page.addAnnotation(label)
            }
        }
        return document
    }

    /// 导出带原生批注的说明书，并在末尾追加颜色、零件、来源和处理覆盖范围。
    static func export(_ archive: ManualStudyArchive) throws -> Data {
        guard archive.researchIsCurrent else {
            throw ManualStudyError.invalid("模型要求或说明书已变更，请重新考证后再导出标注。")
        }
        let document = try annotatedDocument(for: archive)
        let report = reportText(for: archive, pageCount: document.pageCount)
        let appendix = try reportDocument(report)
        for index in 0..<appendix.pageCount {
            if let page = appendix.page(at: index) { document.insert(page, at: document.pageCount) }
        }
        guard let data = document.dataRepresentation() else {
            throw ManualStudyError.invalid("PDF 导出失败，请检查说明书文件的权限。")
        }
        return data
    }

    /// 生成可阅读的附录文本，明确区分已分析页、未分析页及人工核对状态。
    static func reportText(for archive: ManualStudyArchive, pageCount: Int) -> String {
        var lines = [
            "GOLDEN · 说明书涂装考证与标注",
            "模型：\(archive.input.kit)", "要求：\(archive.input.theme)",
            "说明书：\(archive.manualName)",
            "说明书来源：\(archive.manualSourceURL.isEmpty ? "用户导入 PDF" : archive.manualSourceURL)",
            "考证模型：\(archive.model?.summary ?? "未记录")",
            "AI 检索结果需核对原始来源；资料支持不代表已由人工证实。RGB 为屏幕近似，GOLDEN 配方须试涂。",
            "圆点旁的编号为「说明书页码.标记号」。橙色边框表示尚未人工核对。",
            "此文件附录为颜色、零件与出处对照；原始 PDF 未被覆盖。"
        ]
        let completed = archive.analyzedPageIndices
        let remaining = (0..<pageCount).filter { !completed.contains($0) }.map { String($0 + 1) }
        lines.append("已处理 \(completed.count)/\(pageCount) 页。未处理页：\(remaining.isEmpty ? "无" : remaining.joined(separator: "、"))")
        if let research = archive.research {
            lines += ["\n主题核对：\(research.subject)", research.summary]
            for uncertainty in research.uncertainties { lines.append("待确认：\(uncertainty)") }
            lines.append("\n颜色表")
            for color in research.colors {
                lines += [
                    "\(color.id) · \(color.displayName) · \(color.evidence.title)",
                    "用途：\(color.usage)\n依据：\(color.explanation)",
                    "来源：\(color.sourceIDs.joined(separator: "、"))",
                    "屏幕近似：\(color.rgb?.description ?? "未知")；\(color.rgbBasis)"
                ]
            }
            lines.append("\n逐页零件标记")
            for page in archive.pages.sorted(by: { $0.pageIndex < $1.pageIndex }) {
                lines.append("第 \(page.pageIndex + 1) 页：\(page.notes)")
                for mark in page.marks {
                    let color = research.colors.first { $0.id == mark.colorID }
                    lines.append(
                        "\(page.pageIndex + 1).\(mark.id) · \(mark.step) · \(mark.part) → \(color?.displayName ?? mark.colorID)"
                        + "\n\(mark.reviewed ? "用户已核对" : "AI 标记待核对")\(mark.uncertain ? "；对应关系有疑问" : "")；\(mark.reason)"
                    )
                }
            }
            lines.append("\n考证资料")
            for source in research.sources {
                lines += ["[\(source.id)] \(source.title) — \(source.publisher)", source.url, source.summary]
            }
        }
        return lines.joined(separator: "\n\n")
    }

    /// 用 Core Text 按可见字符范围分页绘制中文报告，生成 A4 尺寸的 PDF 附录。
    private static func reportDocument(_ text: String) throws -> PDFDocument {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw ManualStudyError.invalid("无法生成考证附录。")
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ])
        let setter = CTFramesetterCreateWithAttributedString(string)
        var offset = 0
        while offset < string.length {
            context.beginPDFPage(nil)
            let path = CGPath(rect: box.insetBy(dx: 42, dy: 48), transform: nil)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: offset, length: 0), path, nil)
            CTFrameDraw(frame, context)
            // 每轮必须消耗字符，否则长文本排版失败会导致分页循环无法结束。
            let visible = CTFrameGetVisibleStringRange(frame)
            context.endPDFPage()
            guard visible.length > 0 else { throw ManualStudyError.invalid("考证附录排版失败。") }
            offset += visible.length
        }
        context.closePDF()
        guard let document = PDFDocument(data: data as Data) else {
            throw ManualStudyError.invalid("考证附录无法读取。")
        }
        return document
    }
}

/// 将已生成的 PDF 字节适配到 SwiftUI 文件导出器。
struct ManualPDFExport: FileDocument {
    /// 文件选择和导出限定为 PDF 类型。
    static var readableContentTypes: [UTType] { [.pdf] }
    var data: Data

    /// 直接包装导出结果，不在文件选择器回调中重新生成报告。
    init(data: Data) { self.data = data }

    /// 按 FileDocument 协议读取文件包装中的普通文件数据。
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    /// 输出单个 PDF 文件，不创建目录式文档包。
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// 在 SwiftUI 中展示可缩放的 PDFKit 单页视图。
struct ManualPDFPreview: NSViewRepresentable {
    let document: PDFDocument
    let pageIndex: Int
    /// 非空时启用点击定位；回调参数为原始页索引和归一化位置。
    var onPlace: ((Int, CGPoint) -> Void)?

    /// 创建原生预览并设置裁切区域、单页显示和自动缩放。
    func makeNSView(context: Context) -> ManualPDFView {
        let view = ManualPDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.displayBox = .cropBox
        view.backgroundColor = .windowBackgroundColor
        view.setAccessibilityIdentifier("manualPDFPreview")
        return view
    }

    /// 仅在文档或页码实际变化时更新 PDFKit，减少不必要的翻页和缩放重置。
    func updateNSView(_ view: ManualPDFView, context: Context) {
        if view.document !== document { view.document = document }
        if let page = document.page(at: pageIndex), view.currentPage !== page { view.go(to: page) }
        view.onPlace = onPlace
    }
}

/// 为 PDFKit 增加可选的点击放置标记能力。
final class ManualPDFView: PDFView {
    var onPlace: ((Int, CGPoint) -> Void)?

    /// 定位模式下回传有效页面位置，其余情况保留 PDFView 的原生鼠标行为。
    override func mouseDown(with event: NSEvent) {
        guard let onPlace, let document else { super.mouseDown(with: event); return }
        let location = convert(event.locationInWindow, from: nil)
        guard let page = page(for: location, nearest: false) else { return }
        let point = ManualPDF.normalizedPoint(convert(location, to: page), on: page)
        guard (0...1).contains(point.x), (0...1).contains(point.y) else { return }
        onPlace(document.index(for: page), point)
    }
}
