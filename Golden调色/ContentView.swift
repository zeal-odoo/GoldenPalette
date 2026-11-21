//
//  ContentView.swift
//  Golden调色
//
//  Created by Ming Liu on 2025/2/6.
//

// 主工作台及其原生编辑窗口、可复用样式和预览。
// 持久化由 RecipeLibrary 负责；本文件通过稳定 UUID 连接项目、颜色和独立窗口。
import SwiftUI
import AppKit

// MARK: - SoFlat 兼容目录
/// 最初内置的 SoFlat 商品模型，供统一目录适配及旧配方恢复使用。
struct GoldenPaint: Identifiable {
    let name: String
    let code: String
    let series: String
    // Keep the pre-1.0.12 preview for recipes saved without an RGB snapshot.
    /// 保存色样更新前的预览，兼容尚未记录 RGB 快照的历史配方。
    let legacyHex: String
    let isDiscontinued: Bool

    /// 当前显示优先使用有出处的色样，旧值仅作为回退。
    var hex: String { PaintSwatchData.swatch(series: .goldenSoFlat, code: code)?.hex ?? legacyHex }

    /// SoFlat 系列内部以商品色号作为稳定身份。
    var id: String { code }

    // 颜色编辑器使用 0...255 的通道值，展示时再换算到 0...1。
    var red: Double { Double(rgb.red) }
    var green: Double { Double(rgb.green) }
    var blue: Double { Double(rgb.blue) }

    /// 停产商品保留在目录中，并在名称后提示其状态。
    var displayName: String {
        isDiscontinued ? "\(name) · 停产" : name
    }

    /// 安全解析六位 HEX；数据不合法时显示中性灰。
    private var rgb: (red: Int, green: Int, blue: Int) {
        guard hex.count == 6,
              let value = Int(hex, radix: 16) else {
            return (204, 204, 204)
        }

        return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
    }

    /// 一次解析原始商品表，字段不完整的行不会进入目录。
    static let all: [GoldenPaint] = rawLibrary.compactMap { line in
        let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5 else { return nil }
        return GoldenPaint(
            name: parts[0],
            code: parts[1],
            series: parts[2],
            legacyHex: parts[3],
            isDiscontinued: parts[4] == "true"
        )
    }

    // 表字段：英文名 | 商品色号 | 系列 | 历史 HEX | 是否停产；当前色样另表维护。
    // Original screen previews retained for legacy decoding; current sRGB is in PaintSwatchData.
    private static let rawLibrary = """
Titanium White|6755|SoFlat|F3F5F2|false
Black|6745|SoFlat|222721|false
Permanent Green|6660|SoFlat|007A48|false
Ultramarine Blue|6610|SoFlat|0736C8|false
Cadmium Primrose|6505|SoFlat|F5EA32|false
Naphthol Red Light|6550|SoFlat|DA321E|false
Cobalt Teal|6645|SoFlat|00AAA8|false
Bismuth Vanadate Yellow|6510|SoFlat|F4DF16|false
Naphthol Pink|6570|SoFlat|D9485A|false
Cadmium Orange|6530|SoFlat|F47719|false
Red Violet|6595|SoFlat|643761|false
Yellow Green|6675|SoFlat|AAD62C|false
""".split(separator: "\n").map(String.init)
}

// MARK: - 界面颜色
/// 中性工作表面避免干扰色样，控件沿用用户的 macOS 强调色。
enum AppPalette {
    static let primary = Color.accentColor
    static let primaryContainer = Color.accentColor.opacity(0.12)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let cardSurface = Color(nsColor: .textBackgroundColor)
    static let onSurface = Color.primary
    static let onSurfaceVariant = Color.secondary
    static let outlineVariant = Color(nsColor: .separatorColor)
    static let sidebarWidth: CGFloat = 240

    static var librarySymbol: String {
        if #available(macOS 13.0, *) { return "swatchpalette.fill" }
        return "paintpalette.fill"
    }
}

// MARK: - 原生浮动窗口
/// 允许浮动面板成为键盘和主窗口，支持其中的输入控件正常获得焦点。
final class DraggableGlassPanel: NSPanel {
    /// 文本输入需要面板能够成为键盘事件接收窗口。
    override var canBecomeKey: Bool { true }
    /// 允许面板承担主窗口角色，以配合原生交互。
    override var canBecomeMain: Bool { true }
}

/// 新建项目表单，只负责名称草稿与确认操作。
struct NewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (String) -> Void

    @State private var text = ""
    @FocusState private var isNameFocused: Bool

    /// 编辑项目名称并提供键盘提交、取消及初始焦点。
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新建项目").font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 6) {
                Text("项目名称")
                    .font(.headline)
                TextField("例如：骑士模型、森林场景", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("项目名称")
                    .focused($isNameFocused)
                    .accessibilityIdentifier("recipeNameField")
                    .onSubmit(save)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .workspaceButton()
                    .keyboardShortcut(.cancelAction)
                Button("保存", action: save)
                    .workspaceButton(prominent: true)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("saveRecipeButton")
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .workspaceGlassGroup()
        }
        .padding(24)
        .frame(width: 392)
        .onAppear {
            DispatchQueue.main.async {
                isNameFocused = true
            }
        }
    }

    /// 去掉首尾空白，拒绝空名称后向调用方提交。
    private func save() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        onSave(trimmedText)
        dismiss()
    }
}

/// 颜色编辑上下文使用稳定 UUID，窗口打开后主列表切换不会改变保存目标。
enum ColorPickerMode: Equatable {
    case add(listItemID: UUID)
    case edit(listItemID: UUID, colorID: UUID)

    /// 添加和编辑模式都返回所属项目，用于提交前重新查找。
    var listItemID: UUID {
        switch self {
        case .add(let listItemID), .edit(let listItemID, _):
            return listItemID
        }
    }

    /// 根据模式生成窗口及表单标题。
    var title: String {
        switch self {
        case .add:
            return "添加颜色"
        case .edit:
            return "编辑颜色"
        }
    }
}

/// 将颜色编辑表单托管到可独立拖动的原生浮动窗口。
final class ColorEditorWindowController: NSWindowController, NSWindowDelegate {
    let mode: ColorPickerMode

    private var onSave: (ColorInfo) -> Void = { _ in }
    private var onClose: (ColorEditorWindowController) -> Void = { _ in }

    /// 捕获编辑上下文与初始值，保存时将草稿交回颜色库校验。
    init(
        mode: ColorPickerMode,
        recipeName: String,
        initialColor: ColorInfo,
        onSave: @escaping (ColorInfo) -> Void,
        onClose: @escaping (ColorEditorWindowController) -> Void
    ) {
        self.mode = mode
        let panel = DraggableGlassPanel(
            contentRect: NSRect(origin: .zero, size: ColorEditorWindowContent.contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        super.init(window: panel)

        self.onSave = onSave
        self.onClose = onClose

        panel.delegate = self
        panel.title = "\(mode.title) · \(recipeName)"
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.titlebarAppearsTransparent = false
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary]

        let hostingView = NSHostingView(
            rootView: ColorEditorWindowContent(
                mode: mode,
                initialColor: initialColor,
                onSave: { [weak self] color in
                    guard let self else { return }
                    self.onSave(color)
                    self.close()
                },
                onCancel: { [weak self] in
                    self?.close()
                }
            )
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        panel.setContentSize(ColorEditorWindowContent.contentSize)
        panel.center()
    }

    /// 此控制器只接受明确的编辑上下文，不支持归档初始化。
    required init?(coder: NSCoder) {
        nil
    }

    /// 关闭时清除保存回调并通知拥有者，避免旧窗口继续提交数据。
    func windowWillClose(_ notification: Notification) {
        let closeAction = onClose
        onSave = { _ in }
        onClose = { _ in }
        closeAction(self)
    }
}

// MARK: - 颜色编辑表单
/// 使用独立草稿编辑商品参考色或 RGB，确认后才提交给主颜色库。
struct ColorEditorWindowContent: View {
    static let contentSize = NSSize(width: 760, height: 560)

    let mode: ColorPickerMode
    /// 保留原始颜色的其他字段，保存时仅覆盖本表单负责的内容。
    private let initialColor: ColorInfo
    let onSave: (ColorInfo) -> Void
    let onCancel: () -> Void

    // 通道、名称和商品选择属于本窗口草稿，取消时不会写回。
    @State private var red: Double
    @State private var green: Double
    @State private var blue: Double
    @State private var colorName: String
    @State private var paintSearchText: String
    @State private var selectedPaintCode: String?
    @State private var paintSeries: PaintSeries

    /// 从现有颜色恢复通道和商品系列，编辑模式下初始化商品搜索名称。
    init(
        mode: ColorPickerMode,
        initialColor: ColorInfo,
        onSave: @escaping (ColorInfo) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.initialColor = initialColor
        self.onSave = onSave
        self.onCancel = onCancel
        _red = State(initialValue: ColorInfo.clampedRGB(initialColor.red))
        _green = State(initialValue: ColorInfo.clampedRGB(initialColor.green))
        _blue = State(initialValue: ColorInfo.clampedRGB(initialColor.blue))
        _colorName = State(initialValue: initialColor.name)
        _selectedPaintCode = State(initialValue: initialColor.paintCode)
        let series = PaintSeries.forColor(initialColor)
        _paintSeries = State(initialValue: series)

        switch mode {
        case .add:
            _paintSearchText = State(initialValue: "")
        case .edit:
            _paintSearchText = State(initialValue: series.paints.first {
                $0.code == initialColor.paintCode
            }?.name ?? "")
        }
    }

    /// RGB 文本框统一采用 0...255 的整数显示和输入范围。
    private static let rgbFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 0
        formatter.maximum = 255
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    /// 使用当前系列的名称、色号匹配规则过滤目录。
    private var filteredPaints: [CatalogPaint] {
        paintSeries.matchingPaints(paintSearchText)
    }

    /// 只在当前系列内解析选中色号，防止跨漆系串用。
    private var selectedPaint: CatalogPaint? {
        guard let selectedPaintCode else { return nil }
        return paintSeries.paints.first { $0.code == selectedPaintCode }
    }

    /// 有商品选择时展示品牌色号，其余情况标为自定义颜色。
    private var editorPaintTitle: String {
        if let code = selectedPaint?.code {
            return "\(paintSeries.brand.title) \(code)"
        }

        return "自定义颜色"
    }

    /// 左侧选择商品参考，右侧预览并微调 RGB 和名称。
    var body: some View {
        HStack(spacing: 0) {
            paintLibrarySection
                .frame(width: 306)
                .background(AppPalette.canvas)
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(editorPaintTitle)
                        .font(.title2.weight(.semibold))
                    Text("屏幕色样仅供参考，可按实物微调。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.sRGB, red: red / 255, green: green / 255, blue: blue / 255))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AppPalette.outlineVariant)
                    }
                    .accessibilityLabel("颜色预览")
                    .accessibilityValue("RGB \(Int(clampedRGB(red))), \(Int(clampedRGB(green))), \(Int(clampedRGB(blue)))")

                VStack(alignment: .leading, spacing: 6) {
                    Text("颜色名称").font(.headline)
                    TextField("输入颜色名称", text: $colorName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("颜色名称")
                        .accessibilityIdentifier("colorNameField")
                }
                VStack(spacing: 8) {
                    colorSliderRow(title: "R", value: $red)
                    colorSliderRow(title: "G", value: $green)
                    colorSliderRow(title: "B", value: $blue)
                }
                Divider()
                HStack {
                    Spacer()
                    Button("取消", action: onCancel)
                        .workspaceButton()
                        .keyboardShortcut(.cancelAction)
                    Button("确定", action: save)
                        .workspaceButton(prominent: true)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("saveColorButton")
                }
                .workspaceGlassGroup()
            }
            .padding(24)
        }
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        .background(AppPalette.cardSurface)
        // 切换系列清空旧色号和搜索词，避免同名色号被自动沿用。
        .onChange(of: paintSeries) { _ in
            selectedPaintCode = nil
            paintSearchText = ""
        }
    }

    /// 提供品牌/系列筛选、名称搜索及可滚动的商品列表。
    private var paintLibrarySection: some View {
        let paints = filteredPaints

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("参考色库", systemImage: "paintbrush.pointed")
                    .font(.headline)
                    .foregroundStyle(AppPalette.onSurface)

                Spacer()

                Text("\(paints.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppPalette.onSurfaceVariant)
            }

            PaintSeriesPicker(selection: $paintSeries, identifierPrefix: "editor")

            TextField("搜索颜色名称或编号", text: $paintSearchText)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(paints) { paint in
                        Button {
                            selectPaint(paint)
                        } label: {
                            paintLibraryRow(paint)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedPaintCode == paint.code ? .isSelected : [])
                    }
                }
                .padding(2)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(16)
    }

    /// 展示商品色样、系列和选择状态。
    private func paintLibraryRow(_ paint: CatalogPaint) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.sRGB, red: paint.red / 255, green: paint.green / 255, blue: paint.blue / 255))
                .frame(width: 34, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.secondary.opacity(0.22), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(paint.displayName)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("#\(paint.code) · \(paint.series.shortTitle)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AppPalette.onSurfaceVariant)
            }

            Spacer()

            if selectedPaintCode == paint.code {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppPalette.primary)
            }
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selectedPaintCode == paint.code ? AppPalette.primaryContainer : Color.clear)
        )
        .contentShape(Rectangle())
    }

    /// 让同一 RGB 通道同时支持滑块与受限数字输入。
    private func colorSliderRow(title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .leading)
            Slider(value: value, in: 0...255)
                .accessibilityLabel("\(title) 通道")
            TextField("", value: value, formatter: Self.rgbFormatter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
                .accessibilityLabel("\(title) 数值")
                .accessibilityIdentifier("rgb-\(title)")
        }
    }

    /// 从原始颜色构造提交值；新增颜色分配新 UUID 并清空旧方法说明。
    private func save() {
        var color = initialColor
        color.red = clampedRGB(red)
        color.green = clampedRGB(green)
        color.blue = clampedRGB(blue)
        color.name = colorName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let paint = selectedPaint {
            color.paintName = paint.name
            color.paintCode = paint.code
            color.paintSeries = paint.series.title
        } else {
            color.paintName = nil
            color.paintCode = nil
            color.paintSeries = nil
        }
        if case .add = mode {
            color.id = UUID()
            color.method = ""
        }
        onSave(color)
    }

    /// 选中商品时同步名称和 RGB，后续仍允许用户按实物微调。
    private func selectPaint(_ paint: CatalogPaint) {
        selectedPaintCode = paint.code
        paintSearchText = paint.name
        colorName = paint.name
        red = paint.red
        green = paint.green
        blue = paint.blue
    }

    /// 保存前四舍五入并夹紧通道，复用颜色库的非有限值处理。
    private func clampedRGB(_ value: Double) -> Double {
        ColorInfo.clampedRGB(value.rounded())
    }

}

/// 调色方法的就地编辑器，临时草稿允许取消而不改动已保存文本。
struct ColorMethodEditor: View {
    @Binding var method: String

    @State private var isEditing = false
    @State private var tempMethod = ""

    /// 在摘要和编辑表单之间切换，只有保存操作更新外部绑定。
    var body: some View {
        Group {
            if isEditing {
                VStack(alignment: .leading, spacing: 8) {
                    Text("调色方法")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppPalette.onSurfaceVariant)

                    TextEditor(text: $tempMethod)
                        .accessibilityIdentifier("colorMethodField")
                        .font(.body)
                        .frame(height: 72)
                        .padding(4)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(AppPalette.outlineVariant, lineWidth: 1)
                                .allowsHitTesting(false)
                        }

                    HStack {
                        Button("取消") {
                            isEditing = false
                        }
                        .workspaceButton()

                        Spacer()

                        Button("保存") {
                            method = tempMethod
                            isEditing = false
                        }
                        .workspaceButton(prominent: true)
                        .accessibilityIdentifier("saveMethodButton")
                    }
                }
            } else {
                Button {
                    tempMethod = method
                    isEditing = true
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "text.alignleft")
                            .foregroundStyle(AppPalette.onSurfaceVariant)
                        Text(method.isEmpty ? "添加调色方法" : method)
                            .foregroundStyle(method.isEmpty ? AppPalette.onSurfaceVariant : Color.primary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "pencil")
                            .foregroundStyle(AppPalette.onSurfaceVariant)
                    }
                    .font(.callout)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("编辑调色方法")
                .accessibilityLabel(method.isEmpty ? "添加调色方法" : "编辑调色方法：\(method)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 项目标题的就地重命名组件，编辑状态由主界面控制。
struct EditableListItemHeader: View {
    @Binding var text: String
    @Binding var isEditing: Bool

    @State private var tempText = ""
    @FocusState private var isNameFocused: Bool

    /// 进入编辑时复制当前名称并聚焦，未确认前保留原标题。
    var body: some View {
        HStack(spacing: 8) {
            if isEditing {
                TextField("项目名称", text: $tempText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .onSubmit(save)
                    .onAppear {
                        tempText = text
                        isNameFocused = true
                    }

                Button("完成", action: save)
                    .workspaceButton()
                    .disabled(tempText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("取消") {
                    isEditing = false
                }
                .keyboardShortcut(.cancelAction)
            } else {
                Text(text)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 提交非空名称并退出编辑状态。
    private func save() {
        let name = tempText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        text = name
        isEditing = false
    }
}

// MARK: - 功能窗口上下文
/// 固定调色任务所属项目及初始输入，避免主窗口切换选中项影响保存。
private struct ProjectMixingRequest: Identifiable {
    let projectID: UUID
    let projectName: String
    let target: MixingTarget
    let referencePaint: PaintReference?
    let paintSet: MixingPaintSet

    /// 以项目身份控制该项目的调色弹窗。
    var id: UUID { projectID }
}

/// 打开说明书考证时记录的项目身份及备用显示名称。
private struct ProjectManualRequest: Identifiable {
    let id: UUID
    let name: String
}

// MARK: - 主工作台
/// 连接项目列表、颜色卡片、AI 调色和说明书考证入口。
struct ContentView: View {
    /// 颜色库由应用根节点拥有，所有窗口通过同一绑定读取最新数据。
    @Binding private var library: RecipeLibrary

    @State private var isRenamingRecipe = false
    @State private var isCreatingProject = false
    // 持有独立编辑器，允许切换项目时继续编辑原色。
    @State private var colorEditorWindowController: ColorEditorWindowController?
    @State private var savedRecipeWindowController: SavedMixingRecipeWindowController?
    /// 只保存选中项目 UUID；当前数组位置每次从库中重新解析。
    @State private var selectedItemID: UUID?
    // 弹窗保存任务创建时的项目上下文，与当前侧栏选择相互独立。
    @State private var mixingRequest: ProjectMixingRequest?
    @State private var manualRequest: ProjectManualRequest?

    /// 当前颜色库的项目快照，供视图渲染使用。
    private var items: [ListItem] { library.items }

    // 生成服务由应用注入，便于界面测试使用固定结果。
    private let configuration: AIConfiguration
    private let generateRecipe: MixingGenerator
    private let generateBlend: BlendMixingGenerator
    private let connectionBar: CodexConnectionBar?

    /// 接收共享库与生成能力；未显式注入时使用真实 Codex 服务。
    init(
        library: Binding<RecipeLibrary>,
        configuration: AIConfiguration = AIConfiguration(),
        connectionBar: CodexConnectionBar? = nil,
        generateBlend: @escaping BlendMixingGenerator = { request, paintSet, configuration in
            try await CodexMixingService().generate(from: request, paintSet: paintSet, configuration: configuration)
        },
        generateRecipe: @escaping MixingGenerator = { target, referencePaint, paintSet, configuration in
            try await CodexMixingService().generate(for: target, referencePaint: referencePaint, paintSet: paintSet, configuration: configuration)
        }
    ) {
        _library = library
        self.connectionBar = connectionBar
        self.configuration = configuration
        self.generateRecipe = generateRecipe
        self.generateBlend = generateBlend
    }

    /// 按选中 UUID 解析最新位置，删除或刷新后不会沿用失效下标。
    private var selectedIndex: Int? {
        guard let selectedItemID else { return nil }
        return items.firstIndex(where: { $0.id == selectedItemID })
    }

    /// 组装主布局，绑定功能弹窗，并在数据变化时核对选择与窗口状态。
    var body: some View {
        let generator: MixingGenerator = generateRecipe
        let blendGenerator: BlendMixingGenerator = generateBlend
        return workspaceWithToolbar
            .frame(minWidth: 700, minHeight: 440)
            .navigationTitle("调色谱")
            .sheet(isPresented: $isCreatingProject) {
                NewProjectSheet(onSave: addItem(named:))
            }
            .sheet(item: $mixingRequest) { request in
                AIMixingView(
                    projectName: library.item(id: request.projectID)?.text ?? request.projectName,
                    initialTarget: request.target,
                    initialReferencePaint: request.referencePaint,
                    initialPaintSet: request.paintSet,
                    configuration: configuration,
                    canSave: !library.isReadOnly && library.item(id: request.projectID) != nil,
                    generateBlend: blendGenerator,
                    generateRecipe: generator
                // 始终保存到请求创建时的项目，不跟随后续侧栏选择变化。
                ) { palette in
                    library.addMixingPalette(palette, to: request.projectID)
                }
            }
            .sheet(item: $manualRequest) { request in
                ManualStudyView(
                    projectID: request.id,
                    projectName: library.item(id: request.id)?.text ?? request.name,
                    configuration: configuration,
                    canSave: !library.isReadOnly && library.item(id: request.id) != nil,
                    generateRecipe: generator,
                    generateBlend: blendGenerator
                ) { palette, context in
                    library.addMixingPalette(palette, to: request.id, context: context)
                }
            }
            .onChange(of: selectedItemID) { _ in
                isRenamingRecipe = false
            }
            .onChange(of: items) { _ in
                reconcileSelection()
            }
            .onAppear(perform: reconcileSelection)
            .onDisappear(perform: closeEditors)
            .alert("项目数据错误", isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { if !$0 { library.errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { library.errorMessage = nil }
            } message: {
                Text(library.errorMessage ?? "")
            }
    }

    @ViewBuilder
    private var workspaceWithToolbar: some View {
        if #available(macOS 26.0, *) {
            rootLayout.toolbar {
                colorTools
                if selectedIndex != nil {
                    ToolbarSpacer(.fixed, placement: .primaryAction)
                }
                projectTools
            }
        } else {
            rootLayout.toolbar {
                colorTools
                projectTools
            }
        }
    }

    @ToolbarContentBuilder
    private var colorTools: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if let selectedIndex {
                Button {
                    let item = items[selectedIndex]
                    manualRequest = ProjectManualRequest(id: item.id, name: item.text)
                } label: {
                    Label("说明书考证", systemImage: "doc.text.magnifyingglass")
                }
                .labelStyle(.titleAndIcon)
                .help("查找或导入模型说明书，考证配色并标注零件")
                .accessibilityIdentifier("manualStudyButton")
                .disabled(library.isReadOnly)
            }
        }

        ToolbarItem(placement: .primaryAction) {
            if selectedIndex != nil {
                Button {
                    showAIMixing()
                } label: {
                    Label("AI 调色", systemImage: "sparkles")
                }
                .labelStyle(.titleAndIcon)
                .help("为当前项目生成本色、阴影色和高光色配方")
                .accessibilityIdentifier("aiMixingButton")
                .disabled(library.isReadOnly)
            }
        }

    }

    @ToolbarContentBuilder
    private var projectTools: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                isCreatingProject = true
            } label: {
                Label("新建项目", systemImage: "folder.badge.plus")
            }
            .help("新建项目")
            .accessibilityIdentifier("newRecipeButton")
            .disabled(library.isReadOnly)
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    isRenamingRecipe = true
                } label: {
                    Label("重命名项目", systemImage: "pencil")
                }

                Divider()

                Button(role: .destructive) {
                    deleteSelectedItem()
                } label: {
                    Label("删除项目", systemImage: "trash")
                }
            } label: {
                Label("项目操作", systemImage: "ellipsis")
            }
            .disabled(selectedIndex == nil || library.isReadOnly)
            .help("项目操作")
            .accessibilityIdentifier("recipeActionsMenu")
        }
    }

    // MARK: - 分栏与项目展示
    /// 新系统使用原生分栏导航，旧系统以水平布局提供相同工作区域。
    @ViewBuilder
    private var rootLayout: some View {
        if #available(macOS 13.0, *) {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 192, ideal: AppPalette.sidebarWidth, max: 300)
            } detail: {
                workspaceDetail
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            HStack(spacing: 0) {
                sidebar
                    .frame(width: AppPalette.sidebarWidth)
                    .background(.ultraThinMaterial)
                Divider()
                workspaceDetail
            }
        }
    }

    private var workspaceDetail: some View {
        detail.workspaceBar(edge: .bottom) {
            if let connectionBar {
                connectionBar
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    /// 展示项目列表、数量和设置入口。
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("我的项目")
                    .font(.headline)
                Spacer()
                Text("\(items.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(items.count) 个项目")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            List(selection: $selectedItemID) {
                ForEach(items) { item in
                    sidebarRow(item)
                        .tag(item.id)
                }
            }
            .listStyle(.sidebar)

            Divider()
            AISettingsLink()
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
        }
    }

    /// 在侧栏紧凑显示项目名称、颜色数量和前几个颜色的叠层预览。
    private func sidebarRow(_ item: ListItem) -> some View {
        HStack(spacing: 12) {
            projectThumbnail(item.colors)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .help(item.text)
                Text("\(item.colors.count) 个颜色")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    /// 根据当前项目展示颜色网格或空状态；重命名时滚回项目标题。
    @ViewBuilder
    private var detail: some View {
        if let selectedIndex {
            let selectedItem = items[selectedIndex]

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 0) {
                        if !selectedItem.colors.isEmpty {
                            projectColorBanner(selectedItem.colors)
                        }
                        VStack(alignment: .leading, spacing: 24) {
                            recipeHeader(item: selectedItem, title: titleBinding(for: selectedItem))
                                .id("recipeHeader")

                            if selectedItem.colors.isEmpty {
                                emptyRecipeContent
                            } else {
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 218), spacing: 16, alignment: .top)],
                                    alignment: .leading,
                                    spacing: 16
                                ) {
                                    ForEach(selectedItem.colors) { color in
                                        colorCard(color, itemID: selectedItem.id)
                                    }
                                }
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(AppPalette.canvas)
                .accessibilityIdentifier("recipeDetailScrollView")
                .onChange(of: isRenamingRecipe) { isEditing in
                    if isEditing {
                        scrollProxy.scrollTo("recipeHeader", anchor: .top)
                    }
                }
            }
            .id(selectedItem.id)
        } else {
            VStack(spacing: 16) {
                Image(systemName: library.isReadOnly ? "exclamationmark.triangle" : AppPalette.librarySymbol)
                    .font(.system(size: 56, weight: .medium))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.teal, .orange, .indigo)
                    .accessibilityHidden(true)
                Text(library.isReadOnly ? "项目暂时无法读取" : "创建第一个调色项目")
                    .font(.title.weight(.semibold))
                Text(library.isReadOnly
                     ? "原始数据已保留，请恢复数据后重新打开应用。"
                     : "把同一模型或画作的色样和配方收在一个项目里。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    isCreatingProject = true
                } label: {
                    Label("新建项目", systemImage: "plus")
                }
                .workspaceButton(prominent: true)
                .controlSize(.large)
                .disabled(library.isReadOnly)
                .accessibilityIdentifier("emptyNewProjectButton")
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppPalette.canvas)
        }
    }

    /// 组合可编辑项目名、颜色总数和整组色条。
    private func recipeHeader(item: ListItem, title: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            EditableListItemHeader(text: title, isEditing: $isRenamingRecipe)
            if !item.colors.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("项目颜色").font(.headline)
                    Text("\(item.colors.count) 色")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }

    /// 项目已创建但尚无颜色时，引导用户从 AI 调色开始。
    private var emptyRecipeContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "paintpalette")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("留白待色")
                .font(.title2.weight(.semibold))

            Text("从一个目标色开始，生成本色、阴影色和高光色配方。")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button {
                showAIMixing()
            } label: {
                Label("AI 调色", systemImage: "sparkles")
            }
            .workspaceButton(prominent: true)
            .accessibilityIdentifier("emptyProjectAIMixingButton")
            .disabled(library.isReadOnly)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 270)
        .background(AppPalette.cardSurface, in: RoundedRectangle(cornerRadius: 14))
    }

    /// 单色卡片聚合颜色编辑、配方查看、重新调色、删除和方法说明入口。
    private func colorCard(_ color: ColorInfo, itemID: UUID) -> some View {
        let displayName = color.name.isEmpty ? (color.paintName ?? "未命名颜色") : color.name

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                showColorEditor(
                    mode: .edit(listItemID: itemID, colorID: color.id),
                    initialColor: color
                )
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle()
                        .fill(Color(.sRGB, red: color.red / 255, green: color.green / 255, blue: color.blue / 255))
                        .frame(height: 100)
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 8) {
                            Text(displayName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "slider.horizontal.3")
                                .font(.caption)
                                .foregroundStyle(AppPalette.onSurfaceVariant)
                                .padding(.top, 3)
                        }

                        if let paintName = color.paintName, paintName != displayName {
                            Text(paintName)
                                .font(.caption)
                                .foregroundStyle(AppPalette.onSurfaceVariant)
                                .lineLimit(1)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            if let reference = color.mixingRecipe?.referencePaint {
                                Text("本色参考：\(reference.series.brand.title) #\(reference.paintCode)")
                            } else if let code = color.paintCode {
                                Text("参考色：\(PaintSeries.forColor(color).brand.title) #\(code)")
                            } else {
                                Text("自定义颜色")
                            }
                            if let recipe = color.mixingRecipe {
                                Text("调色用漆：\(recipe.paintsTitle)")
                            } else if let series = color.paintSeries {
                                Text("参考漆系：\(series)")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(AppPalette.onSurfaceVariant)

                        Text("RGB  \(Int(color.red)) · \(Int(color.green)) · \(Int(color.blue))")
                            .font(.caption.monospaced())
                            .foregroundStyle(AppPalette.onSurfaceVariant)
                    }
                    .padding(12)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("编辑颜色：\(displayName)")
            .accessibilityLabel("编辑颜色：\(displayName)")
            .accessibilityValue("RGB \(Int(color.red)), \(Int(color.green)), \(Int(color.blue))")

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let recipe = color.mixingRecipe {
                    SavedMixingRecipeButton(recipe: recipe) {
                        showSavedMixingRecipe(recipe, itemID: itemID, colorID: color.id)
                    }
                }

                HStack {
                    Button {
                        showAIMixing(color: color)
                    } label: {
                        Label("用此颜色 AI 调色", systemImage: "sparkles")
                    }

                    Spacer(minLength: 8)

                    Button(role: .destructive) {
                        library.removeColor(itemID: itemID, colorID: color.id)
                    } label: {
                        Label("删除颜色", systemImage: "trash")
                            .labelStyle(.iconOnly)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .help("删除颜色：\(displayName)")
                    .accessibilityLabel("删除颜色：\(displayName)")
                    .accessibilityIdentifier("deleteColorButton-\(color.id)")
                }
                .buttonStyle(.borderless)
                .disabled(library.isReadOnly)

                ColorMethodEditor(method: methodBinding(for: color, itemID: itemID))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(AppPalette.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppPalette.outlineVariant)
                .allowsHitTesting(false)
        }
    }

    /// 预览项目最前面的三种颜色，空项目显示系统文件夹。
    @ViewBuilder
    private func projectThumbnail(_ colors: [ColorInfo]) -> some View {
        if colors.isEmpty {
            Image(systemName: "folder")
                .font(.title3)
        } else {
            colorStrip(colors.prefix(3))
        }
    }

    @ViewBuilder
    private func projectColorBanner(_ colors: [ColorInfo]) -> some View {
        let band = colorBands(colors).frame(height: 60).accessibilityHidden(true)
        if #available(macOS 26.0, *) {
            band.backgroundExtensionEffect()
        } else {
            band
        }
    }

    private func colorBands(_ colors: some RandomAccessCollection<ColorInfo>) -> some View {
        HStack(spacing: 0) {
            ForEach(colors) { color in
                Color(.sRGB, red: color.red / 255, green: color.green / 255, blue: color.blue / 255)
            }
        }
    }

    private func colorStrip(_ colors: some RandomAccessCollection<ColorInfo>) -> some View {
        colorBands(colors)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(AppPalette.outlineVariant)
            }
    }

    // MARK: - 库操作与稳定身份绑定
    /// 只有项目创建并保存成功后才切换选中项。
    private func addItem(named text: String) {
        if let itemID = library.addItem(named: text) {
            selectedItemID = itemID
        }
    }

    /// 每次读写都按 UUID 查找最新项目，避免视图持有旧名称快照。
    private func titleBinding(for item: ListItem) -> Binding<String> {
        Binding(
            get: { library.item(id: item.id)?.text ?? item.text },
            set: { library.renameItem(id: item.id, to: $0) }
        )
    }

    /// 按项目和颜色双层 UUID 更新方法，避免独立窗口同时编辑时覆盖无关字段。
    private func methodBinding(for color: ColorInfo, itemID: UUID) -> Binding<String> {
        Binding(
            get: { library.color(itemID: itemID, colorID: color.id)?.method ?? color.method },
            set: { library.updateMethod($0, itemID: itemID, colorID: color.id) }
        )
    }

    /// 数据改变后修复选择，并关闭已删除或已不匹配的颜色/配方窗口。
    private func reconcileSelection() {
        if !items.contains(where: { $0.id == selectedItemID }) {
            selectedItemID = items.first?.id
        }
        if let controller = savedRecipeWindowController,
           library.color(itemID: controller.itemID, colorID: controller.colorID)?.mixingRecipe != controller.recipe {
            // A deleted or edited color must not leave an unrelated recipe window open.
            controller.close()
        }
        guard let controller = colorEditorWindowController else { return }
        let itemID = controller.mode.listItemID
        if library.item(id: itemID) == nil {
            controller.close()
        } else if case .edit(_, let colorID) = controller.mode,
                  library.color(itemID: itemID, colorID: colorID) == nil {
            // Another window can delete the color while this editor is open.
            controller.close()
        }
    }

    /// 主界面离开或打开新流程时统一关闭附属编辑窗口。
    private func closeEditors() {
        colorEditorWindowController?.close()
        savedRecipeWindowController?.close()
    }

    /// 删除选中项目前关闭其颜色编辑器，成功后重新选取有效项目。
    private func deleteSelectedItem() {
        guard let selectedIndex else { return }
        let removedID = items[selectedIndex].id
        if colorEditorWindowController?.mode.listItemID == removedID {
            colorEditorWindowController?.close()
        }
        if library.removeItem(id: removedID) {
            reconcileSelection()
        }
    }

    /// 从指定颜色或项目最近配方恢复调色起点，并固定原料套装和项目身份。
    private func showAIMixing(color: ColorInfo? = nil) {
        guard !library.isReadOnly, let selectedItemID,
              let project = library.item(id: selectedItemID) else { return }
        closeEditors()
        let reference: PaintReference?
        let target: MixingTarget
        if let color {
            reference = PaintReference.forColor(color)
            target = MixingTarget(red: color.red, green: color.green, blue: color.blue)
        } else {
            reference = project.colors.compactMap(\.mixingRecipe).last?.referencePaint
            target = reference?.previewTarget ?? .initial
        }
        let previousRecipe = color?.mixingRecipe ?? project.colors.compactMap(\.mixingRecipe).last
        mixingRequest = ProjectMixingRequest(
            projectID: project.id, projectName: project.text, target: target, referencePaint: reference,
            paintSet: previousRecipe?.paintSetForNewMixing ?? .defaultSelection
        )
    }

    /// 打开仍与库中数据一致的配方快照；相同窗口已存在时直接置前。
    private func showSavedMixingRecipe(_ recipe: MixingRecipe, itemID: UUID, colorID: UUID) {
        guard let item = library.item(id: itemID),
              library.color(itemID: itemID, colorID: colorID)?.mixingRecipe == recipe else { return }
        if let controller = savedRecipeWindowController,
           controller.itemID == itemID, controller.colorID == colorID, controller.recipe == recipe {
            NSApp.activate(ignoringOtherApps: true)
            controller.window?.makeKeyAndOrderFront(nil)
            return
        }

        savedRecipeWindowController?.close()
        let controller = SavedMixingRecipeWindowController(
            itemID: itemID,
            colorID: colorID,
            projectName: item.text,
            recipe: recipe,
            onClose: { closedController in
                if savedRecipeWindowController === closedController {
                    savedRecipeWindowController = nil
                }
            }
        )
        savedRecipeWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    /// 同一编辑目标复用窗口，其他目标关闭旧窗口；保存始终沿用原始上下文。
    private func showColorEditor(mode: ColorPickerMode, initialColor: ColorInfo) {
        if let controller = colorEditorWindowController, controller.mode == mode {
            NSApp.activate(ignoringOtherApps: true)
            controller.window?.makeKeyAndOrderFront(nil)
            return
        }

        guard let item = items.first(where: { $0.id == mode.listItemID }) else { return }
        colorEditorWindowController?.close()

        // Keep the original recipe ID even when the main window changes selection.
        let controller = ColorEditorWindowController(
            mode: mode,
            recipeName: item.text,
            initialColor: initialColor,
            onSave: { color in
                library.commitColorChange(color, for: mode)
            },
            onClose: { closedController in
                if colorEditorWindowController === closedController {
                    colorEditorWindowController = nil
                }
            }
        )
        colorEditorWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }


}

// MARK: - 共享样式与系统版本兼容
extension View {
    /// 操作层使用系统材质，旧版 macOS 沿用相同层级的原生按钮。
    @ViewBuilder
    func workspaceButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// 下拉列表交由系统菜单呈现，收起的选择器与工作区按钮使用同一套材质。
    func workspaceMenuPicker() -> some View {
        pickerStyle(.menu)
            .workspaceButton()
    }

    @ViewBuilder
    func workspaceGlassGroup() -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 4) { self }
        } else {
            self
        }
    }

    /// 为组合控件提供单层材质，内部按钮保留独立焦点。
    @ViewBuilder
    func workspaceControlCapsule() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: Capsule())
        } else {
            background(.regularMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(AppPalette.outlineVariant) }
        }
    }

    @ViewBuilder
    func workspaceBar<Bar: View>(edge: VerticalEdge, @ViewBuilder content: () -> Bar) -> some View {
        if #available(macOS 26.0, *) {
            safeAreaBar(edge: edge, spacing: 0, content: content)
        } else {
            safeAreaInset(edge: edge, spacing: 0, content: content)
        }
    }
}

// MARK: - 独立于用户数据的设计预览
#if DEBUG
/// 用内存颜色库包装主界面，预览操作不会写入真实项目。
private struct RecipePreview: View {
    @State private var library: RecipeLibrary

    /// 将指定预览项目转换为可编辑的本地状态。
    init(items: [ListItem]) {
        _library = State(initialValue: RecipeLibrary(previewItems: items))
    }

    /// 复用真实主界面布局检查预览数据的展示。
    var body: some View {
        ContentView(library: $library, connectionBar: CodexConnectionBar(phase: .skipped, performAction: {}))
    }
}

/// 设计预览使用的固定 SoFlat 色样与示例项目。
private enum RecipePreviewData {
    static let colors: [ColorInfo] = GoldenPaint.all.map { paint in
        ColorInfo(
            red: paint.red,
            green: paint.green,
            blue: paint.blue,
            name: paint.name,
            paintName: paint.name,
            paintCode: paint.code,
            paintSeries: paint.series
        )
    }

    static let items: [ListItem] = [
        ListItem(text: "SoFlat · 12 色", colors: colors),
        ListItem(text: "配色练习")
    ]
}

// 预览覆盖浅色、深色、空项目和独立编辑窗口，便于检查主要界面状态。
#Preview("配色工作台 · 浅色") {
    RecipePreview(items: RecipePreviewData.items)
        .frame(width: 1180, height: 780)
        .preferredColorScheme(.light)
}

#Preview("配色工作台 · 深色") {
    RecipePreview(items: RecipePreviewData.items)
        .frame(width: 1180, height: 780)
        .preferredColorScheme(.dark)
}

#Preview("空状态") {
    RecipePreview(items: [])
        .frame(width: 1000, height: 700)
        .preferredColorScheme(.light)
}

#Preview("新建项目") {
    NewProjectSheet(onSave: { _ in })
        .background(AppPalette.canvas)
        .preferredColorScheme(.light)
}

#Preview("添加颜色") {
    ColorEditorWindowContent(
        mode: .add(listItemID: UUID()),
        initialColor: RecipePreviewData.colors.first ?? ColorInfo(red: 255, green: 255, blue: 255),
        onSave: { _ in },
        onCancel: { }
    )
    .preferredColorScheme(.light)
}

#Preview("编辑颜色 · 深色") {
    ColorEditorWindowContent(
        mode: .edit(listItemID: UUID(), colorID: UUID()),
        initialColor: RecipePreviewData.colors.last ?? ColorInfo(red: 255, green: 255, blue: 255),
        onSave: { _ in },
        onCancel: { }
    )
    .preferredColorScheme(.dark)
}
#endif
