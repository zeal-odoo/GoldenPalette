//
//  ContentView.swift
//  Golden调色
//
//  Created by Ming Liu on 2025/2/6.
//

import SwiftUI
import AppKit

struct GoldenPaint: Identifiable {
    let name: String
    let code: String
    let series: String
    // Keep the pre-1.0.12 preview for recipes saved without an RGB snapshot.
    let legacyHex: String
    let isDiscontinued: Bool

    var hex: String { PaintSwatchData.swatch(series: .goldenSoFlat, code: code)?.hex ?? legacyHex }

    var id: String { code }

    var red: Double { Double(rgb.red) }
    var green: Double { Double(rgb.green) }
    var blue: Double { Double(rgb.blue) }

    var displayName: String {
        isDiscontinued ? "\(name) · 停产" : name
    }

    private var rgb: (red: Int, green: Int, blue: Int) {
        guard hex.count == 6,
              let value = Int(hex, radix: 16) else {
            return (204, 204, 204)
        }

        return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
    }

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

enum AppPalette {
    static let burntInk = adaptive(light: hex(0x1A1A1A), dark: hex(0xF4EDE1))
    static let deepInk = adaptive(light: hex(0x333333), dark: hex(0xD8CEC0))
    static let lightInk = adaptive(light: hex(0x666666), dark: hex(0xAEA498))
    static let clearInk = adaptive(light: hex(0x999999), dark: hex(0x746E66))
    static let paper = adaptive(light: hex(0xF8F5F0), dark: hex(0x101315))
    static let ricePaper = adaptive(light: hex(0xFAF0E6), dark: hex(0x171613))
    static let ivory = adaptive(light: hex(0xFFFFF0), dark: hex(0x1E1A16))
    static let cinnabar = adaptive(light: hex(0xC41E3A), dark: hex(0xE04B62))
    static let mountainGreen = adaptive(light: hex(0x2E8B57), dark: hex(0x52A875))
    static let antiqueGold = adaptive(light: hex(0xD4AF37), dark: hex(0xE0B84A))
    static let primary = cinnabar
    static let onPrimary = adaptive(light: .white, dark: hex(0x16090C))
    static let primaryContainer = adaptive(light: hex(0xF5C7B8), dark: hex(0x5B1C28, alpha: 0.84))
    static let onPrimaryContainer = burntInk
    static let secondary = mountainGreen
    static let secondaryContainer = adaptive(light: hex(0xCCE6D1), dark: hex(0x17382B, alpha: 0.86))
    static let tertiary = antiqueGold
    static let tertiaryContainer = adaptive(light: hex(0xEDDC94), dark: hex(0x4B3B17, alpha: 0.86))
    static let surface = paper
    static let canvas = adaptive(light: hex(0xF5F5F3), dark: hex(0x151617))
    static let cardSurface = adaptive(light: hex(0xFFFFFF), dark: hex(0x222426))
    static let surfaceContainerLowest = adaptive(light: hex(0xFFFFFF, alpha: 0.36), dark: hex(0xFFFFFF, alpha: 0.07))
    static let surfaceContainerLow = adaptive(light: hex(0xFFFFFF, alpha: 0.44), dark: hex(0xFFFFFF, alpha: 0.10))
    static let surfaceContainer = adaptive(light: hex(0xFFFFFF, alpha: 0.52), dark: hex(0xFFFFFF, alpha: 0.13))
    static let surfaceContainerHigh = adaptive(light: hex(0xFFFFFF, alpha: 0.64), dark: hex(0xFFFFFF, alpha: 0.18))
    static let onSurface = burntInk
    static let onSurfaceVariant = lightInk
    static let outlineVariant = adaptive(light: hex(0x333333, alpha: 0.14), dark: hex(0xFFFFFF, alpha: 0.16))
    static let shadow = adaptive(light: hex(0x1A1A1A, alpha: 0.14), dark: hex(0x000000, alpha: 0.36))
    static let sidebarWidth: CGFloat = 282

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        })
    }

    private static func hex(_ value: Int, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }
}

struct InkSeal: View {
    var text: String
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(AppPalette.cinnabar)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(AppPalette.cinnabar.opacity(0.75), lineWidth: 2)
                        .padding(4)
                )

            Text(text)
                .font(.system(size: size * 0.34, weight: .bold, design: .serif))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.55)
                .padding(7)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-4))
    }
}

final class DraggableGlassPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class NewRecipeWindowController: NSWindowController, NSWindowDelegate {
    private var onSave: (String) -> Void = { _ in }
    private var onClose: () -> Void = { }
    private let windowSize = NSSize(width: 400, height: 224)

    init(onSave: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        let panel = DraggableGlassPanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init(window: panel)

        self.onSave = onSave
        self.onClose = onClose

        panel.delegate = self
        panel.title = "新建项目"
        panel.isMovableByWindowBackground = true
        panel.isMovable = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.showsResizeIndicator = false
        panel.minSize = windowSize
        panel.maxSize = windowSize
        panel.setContentSize(windowSize)
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        let hostingView = NSHostingView(
            rootView: NewRecipeWindowContent(
                onSave: { [weak self] text in
                    self?.onSave(text)
                    self?.dismissPanel()
                },
                onCancel: { [weak self] in
                    self?.dismissPanel()
                }
            )
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.masksToBounds = false
        panel.contentView = hostingView
        panel.center()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func windowWillClose(_ notification: Notification) {
        let closeAction = onClose
        onSave = { _ in }
        onClose = { }
        closeAction()
    }

    private func dismissPanel() {
        close()
    }
}

struct NewRecipeWindowContent: View {
    var onSave: (String) -> Void
    var onCancel: () -> Void

    @State private var text = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("新建项目")
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundStyle(AppPalette.burntInk)
                    Text("为这次模型、场景或绘画命名")
                        .font(.caption)
                        .foregroundStyle(AppPalette.onSurfaceVariant)
                }

                Spacer()

                InkSeal(text: "新谱", size: 38)
            }

            TextField("例如：骑士模型、森林场景", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .accessibilityIdentifier("recipeNameField")
                .onSubmit(save)

            HStack {
                Button("取消", action: onCancel)
                    .floatingPanelButtonStyle()
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("保存", action: save)
                    .floatingPanelButtonStyle(prominent: true)
                    .accessibilityIdentifier("saveRecipeButton")
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 360)
        .floatingLiquidGlassPanel(cornerRadius: 22)
        .padding(.top, 16)
        .frame(width: 400, height: 224)
        .onAppear {
            DispatchQueue.main.async {
                isNameFocused = true
            }
        }
    }

    private func save() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        onSave(trimmedText)
    }
}

enum ColorPickerMode: Equatable {
    case add(listItemID: UUID)
    case edit(listItemID: UUID, colorID: UUID)

    var listItemID: UUID {
        switch self {
        case .add(let listItemID), .edit(let listItemID, _):
            return listItemID
        }
    }

    var title: String {
        switch self {
        case .add:
            return "添加颜色"
        case .edit:
            return "编辑颜色"
        }
    }
}

final class ColorEditorWindowController: NSWindowController, NSWindowDelegate {
    let mode: ColorPickerMode

    private var onSave: (ColorInfo) -> Void = { _ in }
    private var onClose: (ColorEditorWindowController) -> Void = { _ in }

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
        // The content view sits below the title bar, so AppKit must draw its background.
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

    required init?(coder: NSCoder) {
        nil
    }

    func windowWillClose(_ notification: Notification) {
        let closeAction = onClose
        onSave = { _ in }
        onClose = { _ in }
        closeAction(self)
    }
}

struct FrostedWindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        // Use the same behind-window material for the color editor and saved recipes.
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) { }
}

struct ColorEditorWindowContent: View {
    static let contentSize = NSSize(width: 760, height: 560)

    let mode: ColorPickerMode
    private let initialColor: ColorInfo
    let onSave: (ColorInfo) -> Void
    let onCancel: () -> Void

    @State private var red: Double
    @State private var green: Double
    @State private var blue: Double
    @State private var colorName: String
    @State private var paintSearchText: String
    @State private var selectedPaintCode: String?
    @State private var paintSeries: PaintSeries

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

    private static let rgbFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 0
        formatter.maximum = 255
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private var filteredPaints: [CatalogPaint] {
        paintSeries.matchingPaints(paintSearchText)
    }

    private var selectedPaint: CatalogPaint? {
        guard let selectedPaintCode else { return nil }
        return paintSeries.paints.first { $0.code == selectedPaintCode }
    }

    private var editorPaintTitle: String {
        if let code = selectedPaint?.code {
            return "\(paintSeries.brand.title) \(code)"
        }

        return "自定义颜色"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            paintLibrarySection
                .frame(width: 330)

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(mode.title)
                            .font(.system(size: 24, weight: .regular, design: .serif))
                            .foregroundStyle(AppPalette.deepInk)
                        Text(editorPaintTitle)
                            .font(.headline)
                            .foregroundStyle(AppPalette.onSurface)
                        Text("色样仅供参考，可按实物微调")
                            .font(.caption)
                            .foregroundStyle(AppPalette.onSurfaceVariant)
                    }

                    Spacer()
                }

                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(red: red / 255, green: green / 255, blue: blue / 255))
                    .frame(height: 190)
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(colorName.isEmpty ? "未命名颜色" : colorName)
                                .font(.title3.weight(.semibold))
                            Text("RGB \(Int(clampedRGB(red))) \(Int(clampedRGB(green))) \(Int(clampedRGB(blue)))")
                                .font(.caption.monospacedDigit())
                        }
                        .foregroundStyle(readableTextColor(red: red, green: green, blue: blue))
                        .padding(16)
                    }
                    .shadow(color: AppPalette.shadow, radius: 8, x: 0, y: 3)

                HStack {
                    Text("名称")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppPalette.onSurfaceVariant)
                        .frame(width: 42, alignment: .leading)
                    TextField("输入颜色名称", text: $colorName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("colorNameField")
                }

                VStack(spacing: 10) {
                    colorSliderRow(title: "R", value: $red, tint: .red)
                    colorSliderRow(title: "G", value: $green, tint: .green)
                    colorSliderRow(title: "B", value: $blue, tint: .blue)
                }

                HStack {
                    Button("取消", action: onCancel)
                        .liquidGlassButtonStyle()
                        .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button(action: save) {
                        Label("确定", systemImage: "checkmark")
                    }
                    .liquidGlassProminentButtonStyle()
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("saveColorButton")
                }
                .glassActionGroup()
            }
            .padding(16)
        }
        .padding(18)
        .frame(width: Self.contentSize.width, height: Self.contentSize.height, alignment: .top)
        .background(FrostedWindowBackground())
        .onChange(of: paintSeries) { _ in
            selectedPaintCode = nil
            paintSearchText = ""
        }
    }

    private var paintLibrarySection: some View {
        let paints = filteredPaints

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("参考色库", systemImage: "paintbrush.pointed")
                    .font(.subheadline.weight(.semibold))
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
                    }
                }
                .padding(2)
            }
            .frame(height: 320)
        }
        .padding(14)
    }

    private func paintLibraryRow(_ paint: CatalogPaint) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: paint.red / 255, green: paint.green / 255, blue: paint.blue / 255))
                .frame(width: 34, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.secondary.opacity(0.22), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(paint.displayName)
                    .font(.caption)
                    .foregroundStyle(AppPalette.onSurface)
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
                .fill(selectedPaintCode == paint.code ? AppPalette.surfaceContainerHigh : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private func colorSliderRow(title: String, value: Binding<Double>, tint: Color = .accentColor) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 20, alignment: .leading)
            Slider(value: value, in: 0...255)
            TextField("", value: value, formatter: Self.rgbFormatter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
                .accessibilityLabel("\(title) 数值")
                .accessibilityIdentifier("rgb-\(title)")
        }
    }

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

    private func selectPaint(_ paint: CatalogPaint) {
        selectedPaintCode = paint.code
        paintSearchText = paint.name
        colorName = paint.name
        red = paint.red
        green = paint.green
        blue = paint.blue
    }

    private func clampedRGB(_ value: Double) -> Double {
        ColorInfo.clampedRGB(value.rounded())
    }

    private func readableTextColor(red: Double, green: Double, blue: Double) -> Color {
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 150 ? .black : .white
    }
}

struct ColorMethodEditor: View {
    @Binding var method: String

    @State private var isEditing = false
    @State private var tempMethod = ""

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
                        .liquidGlassButtonStyle()

                        Spacer()

                        Button("保存") {
                            method = tempMethod
                            isEditing = false
                        }
                        .liquidGlassProminentButtonStyle()
                        .accessibilityIdentifier("saveMethodButton")
                    }
                    .glassActionGroup()
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
                            .foregroundStyle(method.isEmpty ? AppPalette.onSurfaceVariant : AppPalette.deepInk)
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

struct EditableListItemHeader: View {
    @Binding var text: String
    @Binding var isEditing: Bool

    @State private var tempText = ""
    @FocusState private var isNameFocused: Bool

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
                    .buttonStyle(.bordered)
                    .disabled(tempText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("取消") {
                    isEditing = false
                }
                .keyboardShortcut(.cancelAction)
            } else {
                Text(text)
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundStyle(AppPalette.burntInk)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        let name = tempText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        text = name
        isEditing = false
    }
}

private struct ProjectMixingRequest: Identifiable {
    let projectID: UUID
    let projectName: String
    let target: MixingTarget
    let referencePaint: PaintReference?
    let paintSet: MixingPaintSet

    var id: UUID { projectID }
}

struct ContentView: View {
    @Binding private var library: RecipeLibrary

    @State private var isRenamingRecipe = false
    @State private var newRecipeWindowController: NewRecipeWindowController?
    @State private var colorEditorWindowController: ColorEditorWindowController?
    @State private var savedRecipeWindowController: SavedMixingRecipeWindowController?
    @State private var selectedItemID: UUID?
    @State private var mixingRequest: ProjectMixingRequest?

    private var items: [ListItem] { library.items }

    private let configuration: AIConfiguration
    private let generateRecipe: MixingGenerator
    private let generateBlend: BlendMixingGenerator

    init(
        library: Binding<RecipeLibrary>,
        configuration: AIConfiguration = AIConfiguration(),
        generateBlend: @escaping BlendMixingGenerator = { request, paintSet, configuration in
            try await CodexMixingService().generate(from: request, paintSet: paintSet, configuration: configuration)
        },
        generateRecipe: @escaping MixingGenerator = { target, referencePaint, paintSet, configuration in
            try await CodexMixingService().generate(for: target, referencePaint: referencePaint, paintSet: paintSet, configuration: configuration)
        }
    ) {
        _library = library
        self.configuration = configuration
        self.generateRecipe = generateRecipe
        self.generateBlend = generateBlend
    }

    private var selectedIndex: Int? {
        guard let selectedItemID else { return nil }
        return items.firstIndex(where: { $0.id == selectedItemID })
    }

    var body: some View {
        let generator: MixingGenerator = generateRecipe
        let blendGenerator: BlendMixingGenerator = generateBlend
        return rootLayout
            .navigationTitle("调色谱")
            .toolbar { recipeToolbar }
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
                ) { palette in
                    library.addMixingPalette(palette, to: request.projectID)
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

    @ToolbarContentBuilder
    private var recipeToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if selectedIndex != nil {
                Button {
                    showAIMixing()
                } label: {
                    Label("AI 调色", systemImage: "sparkles")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.primary)
                .help("输入本色 RGB 或选择颜色，生成本色、阴影色、高光色各 200 滴的配方")
                .accessibilityIdentifier("aiMixingButton")
                .disabled(library.isReadOnly)
            }
        }

        ToolbarItem(placement: .automatic) {
            Button {
                showNewRecipeWindow()
            } label: {
                Label("新建项目", systemImage: "square.and.pencil")
            }
            .help("新建项目")
            .accessibilityIdentifier("newRecipeButton")
            .disabled(library.isReadOnly)
        }

        ToolbarItem(placement: .automatic) {
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

    @ViewBuilder
    private var rootLayout: some View {
        if #available(macOS 13.0, *) {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 230, ideal: AppPalette.sidebarWidth, max: 320)
            } detail: {
                detail
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            HStack(spacing: 0) {
                sidebar
                    .frame(width: AppPalette.sidebarWidth)
                    .background(.ultraThinMaterial)
                Divider()
                detail
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("调色谱")
                        .font(.system(size: 30, weight: .regular, design: .serif))
                    Text("调色原料 · GOLDEN")
                        .font(.caption)
                        .foregroundStyle(AppPalette.onSurfaceVariant)
                }

                Spacer()

                InkSeal(text: "色谱", size: 36)
            }
            .foregroundStyle(AppPalette.onSurface)
            .padding(.horizontal, 20)
            .padding(.top, 24)

            HStack {
                Text("我的项目")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(items.count)")
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(AppPalette.onSurfaceVariant)
            .padding(.horizontal, 20)

            List(selection: $selectedItemID) {
                ForEach(items) { item in
                    sidebarRow(item)
                        .tag(item.id)
                }
            }
            .listStyle(.sidebar)
            .transparentListBackground()

            AISettingsLink()
                .buttonStyle(.borderless)
                .padding(.horizontal, 20)

            HStack(spacing: 6) {
                Image(systemName: "paintbrush.pointed")
                Text("参考色库 · 田宫 · 郡士")
            }
            .font(.caption)
            .foregroundStyle(AppPalette.onSurfaceVariant)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private func sidebarRow(_ item: ListItem) -> some View {
        HStack(spacing: 12) {
            colorStackPreview(item.colors)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Text("\(item.colors.count) 个颜色")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedIndex {
            let selectedItem = items[selectedIndex]

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        recipeHeader(item: selectedItem, title: titleBinding(for: selectedItem))
                            .id("recipeHeader")

                        if selectedItem.colors.isEmpty {
                            emptyRecipeContent
                        } else {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 16)],
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
                .background(canvasBackground)
                .accessibilityIdentifier("recipeDetailScrollView")
                .onChange(of: isRenamingRecipe) { isEditing in
                    if isEditing {
                        scrollProxy.scrollTo("recipeHeader", anchor: .top)
                    }
                }
            }
            .id(selectedItem.id)
        } else {
            ZStack {
                canvasBackground
                inkMountains
                    .opacity(0.18)
                    .allowsHitTesting(false)

                VStack(spacing: 20) {
                    emptyStateView(
                        title: library.isReadOnly ? "项目暂时无法读取" : "先创建一个项目",
                        symbol: "paintpalette",
                        description: library.isReadOnly
                            ? "原始数据已保留，请恢复数据后重新打开应用。"
                            : "点击“新建项目”，进入项目后选择颜色或输入 RGB，再用 AI 生成三色配方。"
                    )

                    Button {
                        showNewRecipeWindow()
                    } label: {
                        Label("新建项目", systemImage: "folder.badge.plus")
                    }
                    .liquidGlassProminentButtonStyle()
                    .disabled(library.isReadOnly)
                    .accessibilityIdentifier("emptyNewProjectButton")
                }
                .foregroundStyle(AppPalette.onSurface)
                .padding(40)
            }
        }
    }

    private var canvasBackground: some View {
        AppPalette.canvas
            .overlay {
                paperGrain
                    .opacity(0.08)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea()
    }

    private var paperGrain: some View {
        Canvas { context, size in
            for index in 0..<90 {
                let x = size.width * CGFloat((index * 37) % 97) / 97
                let y = size.height * CGFloat((index * 53) % 89) / 89
                let rect = CGRect(x: x, y: y, width: 1.2, height: 1.2)
                context.fill(Path(ellipseIn: rect), with: .color(AppPalette.lightInk.opacity(0.16)))
            }
        }
    }

    private var inkMountains: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack(alignment: .bottom) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: height * 0.76))
                    path.addCurve(
                        to: CGPoint(x: width * 0.38, y: height * 0.66),
                        control1: CGPoint(x: width * 0.12, y: height * 0.70),
                        control2: CGPoint(x: width * 0.24, y: height * 0.58)
                    )
                    path.addCurve(
                        to: CGPoint(x: width, y: height * 0.70),
                        control1: CGPoint(x: width * 0.58, y: height * 0.78),
                        control2: CGPoint(x: width * 0.76, y: height * 0.62)
                    )
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.addLine(to: CGPoint(x: 0, y: height))
                    path.closeSubpath()
                }
                .fill(AppPalette.clearInk.opacity(0.22))
                .blur(radius: 16)

                Path { path in
                    path.move(to: CGPoint(x: 0, y: height * 0.86))
                    path.addCurve(
                        to: CGPoint(x: width * 0.46, y: height * 0.74),
                        control1: CGPoint(x: width * 0.15, y: height * 0.78),
                        control2: CGPoint(x: width * 0.30, y: height * 0.72)
                    )
                    path.addCurve(
                        to: CGPoint(x: width, y: height * 0.82),
                        control1: CGPoint(x: width * 0.62, y: height * 0.76),
                        control2: CGPoint(x: width * 0.78, y: height * 0.90)
                    )
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.addLine(to: CGPoint(x: 0, y: height))
                    path.closeSubpath()
                }
                .fill(AppPalette.deepInk.opacity(0.18))
                .blur(radius: 10)
            }
        }
    }

    private func recipeHeader(item: ListItem, title: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                EditableListItemHeader(
                    text: title,
                    isEditing: $isRenamingRecipe
                )

                Text("\(item.colors.count) 色")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(AppPalette.onSurfaceVariant)
                    .fixedSize()
            }

            colorStrip(item.colors)
                .frame(height: 12)

            if !item.colors.isEmpty {
                HStack {
                    Text("项目颜色")
                        .font(.headline)
                        .foregroundStyle(AppPalette.onSurface)
                    Spacer()
                    Text("点按色卡编辑")
                        .font(.caption)
                        .foregroundStyle(AppPalette.onSurfaceVariant)
                }
            }
        }
    }

    private var emptyRecipeContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "paintpalette")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(AppPalette.onSurfaceVariant)

            Text("留白待色")
                .font(.system(size: 24, weight: .regular, design: .serif))
                .foregroundStyle(AppPalette.onSurface)

            Text("选择颜色或输入 RGB，为这个项目生成本色、阴影色和高光色。")
                .font(.callout)
                .foregroundStyle(AppPalette.onSurfaceVariant)

            Button {
                showAIMixing()
            } label: {
                Label("AI 调色", systemImage: "sparkles")
            }
            .liquidGlassProminentButtonStyle()
            .accessibilityIdentifier("emptyProjectAIMixingButton")
            .disabled(library.isReadOnly)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .contentSurface(cornerRadius: 20)
    }

    private func colorCard(_ color: ColorInfo, itemID: UUID) -> some View {
        let displayName = color.name.isEmpty ? (color.paintName ?? "未命名颜色") : color.name

        return VStack(alignment: .leading, spacing: 16) {
            Button {
                showColorEditor(
                    mode: .edit(listItemID: itemID, colorID: color.id),
                    initialColor: color
                )
            } label: {
                VStack(alignment: .leading, spacing: 16) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: color.red / 255, green: color.green / 255, blue: color.blue / 255))
                        .frame(height: 156)
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(.black.opacity(0.08), lineWidth: 1)
                        }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Text(displayName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppPalette.onSurface)
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
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppPalette.onSurfaceVariant)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("编辑颜色：\(displayName)")
            .accessibilityLabel("编辑颜色：\(displayName)")
            .accessibilityValue("RGB \(Int(color.red)), \(Int(color.green)), \(Int(color.blue))")

            Divider()

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
        .padding(16)
        .contentSurface(cornerRadius: 22, elevated: true)
    }

    private func colorStackPreview(_ colors: [ColorInfo]) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(AppPalette.surfaceContainerHigh)

            ForEach(Array(colors.prefix(4).enumerated()), id: \.offset) { index, color in
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(red: color.red / 255, green: color.green / 255, blue: color.blue / 255))
                    .frame(width: 20, height: 20)
                    .offset(x: CGFloat(index) * 4 - 6, y: CGFloat(index) * 3 - 5)
                    .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 1)
            }

            if colors.isEmpty {
                Image(systemName: "paintpalette")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func colorStrip(_ colors: [ColorInfo]) -> some View {
        GeometryReader { proxy in
            let visibleColors = colors.isEmpty ? [ColorInfo(red: 235, green: 232, blue: 222)] : colors
            let width = proxy.size.width / CGFloat(visibleColors.count)

            HStack(spacing: 0) {
                ForEach(Array(visibleColors.enumerated()), id: \.offset) { _, color in
                    Rectangle()
                        .fill(Color(red: color.red / 255, green: color.green / 255, blue: color.blue / 255))
                        .frame(width: width)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(.black.opacity(0.08), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func emptyStateView(title: String, symbol: String, description: String) -> some View {
        if #available(macOS 14.0, *) {
            ContentUnavailableView(title, systemImage: symbol, description: Text(description))
        } else {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func addItem(named text: String) {
        if let itemID = library.addItem(named: text) {
            selectedItemID = itemID
        }
    }

    private func titleBinding(for item: ListItem) -> Binding<String> {
        Binding(
            get: { library.item(id: item.id)?.text ?? item.text },
            set: { library.renameItem(id: item.id, to: $0) }
        )
    }

    private func methodBinding(for color: ColorInfo, itemID: UUID) -> Binding<String> {
        Binding(
            get: { library.color(itemID: itemID, colorID: color.id)?.method ?? color.method },
            set: { library.updateMethod($0, itemID: itemID, colorID: color.id) }
        )
    }

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

    private func closeEditors() {
        newRecipeWindowController?.close()
        colorEditorWindowController?.close()
        savedRecipeWindowController?.close()
    }

    private func showNewRecipeWindow() {
        if let window = newRecipeWindowController?.window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let controller = NewRecipeWindowController(
            onSave: { text in
                addItem(named: text)
            },
            onClose: {
                newRecipeWindowController = nil
            }
        )
        newRecipeWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }

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

private extension View {
    func contentSurface(cornerRadius: CGFloat, elevated: Bool = false) -> some View {
        self
            .background(AppPalette.cardSurface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AppPalette.outlineVariant.opacity(0.55), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: elevated ? AppPalette.shadow.opacity(0.35) : .clear, radius: 8, x: 0, y: 3)
    }

    @ViewBuilder
    func glassActionGroup() -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                self
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func transparentListBackground() -> some View {
        if #available(macOS 13.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }

    @ViewBuilder
    func floatingLiquidGlassPanel(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            self
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(AppPalette.outlineVariant, lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .shadow(color: AppPalette.shadow, radius: 18, x: 0, y: 10)
        }
    }

    func floatingPanelButtonStyle(prominent: Bool = false) -> some View {
        self
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(prominent ? AppPalette.onPrimary : AppPalette.onSurface)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(prominent ? AppPalette.primary : AppPalette.surfaceContainerHigh)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(AppPalette.outlineVariant, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    func liquidGlassProminentButtonStyle() -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            self
                .buttonStyle(.glassProminent)
                .controlSize(.regular)
                .tint(AppPalette.primary)
        } else if #available(macOS 14.0, *) {
            self
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 8))
                .controlSize(.regular)
                .tint(AppPalette.primary)
        } else {
            self
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(AppPalette.primary)
        }
    }

    @ViewBuilder
    func liquidGlassButtonStyle() -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            self
                .buttonStyle(.glass)
                .controlSize(.regular)
        } else if #available(macOS 14.0, *) {
            self
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 8))
                .controlSize(.regular)
                .tint(AppPalette.secondary)
        } else {
            self
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .tint(AppPalette.secondary)
        }
    }
}

#if DEBUG
private struct RecipePreview: View {
    @State private var library: RecipeLibrary

    init(items: [ListItem]) {
        _library = State(initialValue: RecipeLibrary(previewItems: items))
    }

    var body: some View {
        ContentView(library: $library)
    }
}

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
    NewRecipeWindowContent(onSave: { _ in }, onCancel: { })
        .padding(32)
        .background(AppPalette.canvas)
        .preferredColorScheme(.light)
}

#Preview("添加颜色 · 毛玻璃") {
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
