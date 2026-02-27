//
//  ContentView.swift
//  Golden调色
//
//  Created by Ming Liu on 2025/2/6.
//

import SwiftUI

struct ColorInfo: Codable, Identifiable {
    var id = UUID()
    var red: Double
    var green: Double
    var blue: Double
    var name: String = ""
    var method: String = ""
}

struct ListItem: Codable, Identifiable {
    var id = UUID()
    var text: String
    var colors: [ColorInfo] = []
}

enum ColorPickerMode {
    case add(listItemID: UUID)
    case edit(listItemID: UUID, colorID: UUID)
}

struct ColorMethodEditor: View {
    @Binding var method: String
    var onSave: () -> Void = { }

    @State private var isEditing = false
    @State private var tempMethod: String = ""

    var body: some View {
        Group {
            if isEditing {
                VStack(spacing: 6) {
                    TextEditor(text: $tempMethod)
                        .frame(height: 64)
                        .padding(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.secondary.opacity(0.3), lineWidth: 1)
                        )

                    Button("保存") {
                        method = tempMethod
                        onSave()
                        isEditing = false
                    }
                    .appGlassButtonStyle()
                }
                .frame(maxWidth: 260)
            } else {
                Button {
                    tempMethod = method
                    isEditing = true
                } label: {
                    Text(method.isEmpty ? "调色方法" : method)
                        .foregroundStyle(method.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .frame(maxWidth: 260, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct EditableListItemHeader: View {
    @Binding var text: String
    var onDelete: () -> Void
    var onSave: () -> Void = { }

    @State private var isEditing = false
    @State private var tempText = ""

    var body: some View {
        HStack(spacing: 10) {
            if isEditing {
                TextField("请输入内容...", text: $tempText, onCommit: {
                    text = tempText
                    isEditing = false
                    onSave()
                })
                .textFieldStyle(.roundedBorder)
            } else {
                Text(text)
                    .font(.headline)
            }

            Spacer()

            Button {
                tempText = text
                isEditing = true
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }
}

struct ContentView: View {
    private let itemsKey = "SavedItems"

    @State private var showInputPopover = false
    @State private var newItemText = ""

    @State private var items: [ListItem] = [] {
        didSet { saveItems() }
    }

    @State private var selectedItemID: UUID?

    @State private var colorPickerMode: ColorPickerMode?
    @State private var red: Double = 255
    @State private var green: Double = 255
    @State private var blue: Double = 255
    @State private var colorName = ""

    private var rgbFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 0
        formatter.maximum = 255
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }

    private var selectedIndex: Int? {
        guard let selectedItemID else { return nil }
        return items.firstIndex(where: { $0.id == selectedItemID })
    }

    var body: some View {
        rootLayout
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showInputPopover = true
                } label: {
                    Label("新建条目", systemImage: "plus")
                }
                .appGlassButtonStyle()

                Button {
                    guard let selectedIndex else { return }
                    if let lastColor = items[selectedIndex].colors.last {
                        red = lastColor.red
                        green = lastColor.green
                        blue = lastColor.blue
                        colorName = lastColor.name
                    } else {
                        red = 255
                        green = 255
                        blue = 255
                        colorName = ""
                    }
                    colorPickerMode = .add(listItemID: items[selectedIndex].id)
                } label: {
                    Label("新增颜色", systemImage: "paintpalette")
                }
                .disabled(selectedIndex == nil)
                .appGlassButtonStyle()
            }
        }
        .popover(isPresented: $showInputPopover, arrowEdge: .bottom) {
            VStack(spacing: 12) {
                Text("输入内容")
                    .font(.headline)
                TextField("请输入内容...", text: $newItemText)
                    .textFieldStyle(.roundedBorder)
                Button("保存") {
                    addItem()
                }
                .appGlassButtonStyle()
            }
            .padding()
            .frame(width: 320)
        }
        .popover(isPresented: Binding<Bool>(
            get: { colorPickerMode != nil },
            set: { if !$0 { colorPickerMode = nil } }
        )) {
            colorEditorPopover
        }
        .onAppear(perform: loadItems)
    }

    @ViewBuilder
    private var rootLayout: some View {
        if #available(macOS 13.0, *) {
            NavigationSplitView {
                sidebar
                    .navigationTitle("配方")
            } detail: {
                detail
                    .navigationTitle("调色记录")
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            HStack(spacing: 0) {
                sidebar
                    .frame(minWidth: 240, maxWidth: 300)
                Divider()
                detail
            }
        }
    }

    private var sidebar: some View {
        Group {
            if #available(macOS 13.0, *) {
                sidebarList
                    .scrollContentBackground(.hidden)
            } else {
                sidebarList
            }
        }
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.14), Color.yellow.opacity(0.08), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var sidebarList: some View {
        List(selection: $selectedItemID) {
            ForEach(items) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.text)
                            .font(.headline)
                        Text("\(item.colors.count) 个颜色")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .appGlassCard(cornerRadius: 12)
                .tag(item.id)
                .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedIndex {
            let itemBinding = $items[selectedIndex]

            VStack(alignment: .leading, spacing: 14) {
                EditableListItemHeader(
                    text: itemBinding.text,
                    onDelete: { deleteSelectedItem() },
                    onSave: { saveItems() }
                )
                .padding(12)
                .appGlassCard(cornerRadius: 16)

                if items[selectedIndex].colors.isEmpty {
                    emptyStateView(
                        title: "暂无颜色",
                        symbol: "paintpalette",
                        description: "点击工具栏“新增颜色”开始记录。"
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(items[selectedIndex].colors.indices, id: \.self) { colorIndex in
                                colorRow(itemIndex: selectedIndex, colorIndex: colorIndex)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [Color.yellow.opacity(0.10), Color.orange.opacity(0.08), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            emptyStateView(
                title: "选择一个条目",
                symbol: "sidebar.left",
                description: "在左侧选择配方，或先新建条目。"
            )
        }
    }

    private func colorRow(itemIndex: Int, colorIndex: Int) -> some View {
        let color = items[itemIndex].colors[colorIndex]

        return HStack(spacing: 14) {
            Button {
                red = color.red
                green = color.green
                blue = color.blue
                colorName = color.name
                colorPickerMode = .edit(listItemID: items[itemIndex].id, colorID: color.id)
            } label: {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: color.red / 255, green: color.green / 255, blue: color.blue / 255))
                        .frame(width: 110, height: 34)
                        .overlay {
                            if !color.name.isEmpty {
                                Text(color.name)
                                    .font(.caption)
                                    .bold()
                                    .foregroundStyle(readableTextColor(for: color))
                            }
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("RGB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(Int(color.red)), \(Int(color.green)), \(Int(color.blue))")
                            .font(.subheadline.monospacedDigit())
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            ColorMethodEditor(method: $items[itemIndex].colors[colorIndex].method) {
                saveItems()
            }
        }
        .padding(12)
        .appGlassCard(cornerRadius: 14)
    }

    private var colorEditorPopover: some View {
        VStack(spacing: 18) {
            Text("RGB 调色")
                .font(.headline)

            colorSliderRow(title: "R", value: $red)
            colorSliderRow(title: "G", value: $green)
            colorSliderRow(title: "B", value: $blue)

            HStack {
                Text("名称")
                    .frame(width: 48, alignment: .leading)
                TextField("输入颜色名称", text: $colorName)
                    .textFieldStyle(.roundedBorder)
            }

            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: red / 255, green: green / 255, blue: blue / 255))
                .frame(height: 110)
                .overlay {
                    if !colorName.isEmpty {
                        Text(colorName)
                            .bold()
                            .foregroundStyle(readableTextColor(red: red, green: green, blue: blue))
                    }
                }
                .appGlassCard(cornerRadius: 12)

            Button("确定") {
                commitColorChange()
            }
            .appGlassButtonStyle()
        }
        .padding()
        .frame(width: 340)
    }

    private func colorSliderRow(title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
                .frame(width: 20, alignment: .leading)
            Slider(value: value, in: 0...255)
            TextField("", value: value, formatter: rgbFormatter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
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

    private func addItem() {
        guard !newItemText.isEmpty else { return }
        let item = ListItem(text: newItemText)
        items.append(item)
        selectedItemID = item.id
        newItemText = ""
        showInputPopover = false
    }

    private func deleteSelectedItem() {
        guard let selectedIndex else { return }
        let removedID = items[selectedIndex].id
        items.remove(at: selectedIndex)
        if selectedItemID == removedID {
            selectedItemID = items.first?.id
        }
    }

    private func commitColorChange() {
        guard let mode = colorPickerMode else { return }

        switch mode {
        case .add(let listItemID):
            guard let itemIndex = items.firstIndex(where: { $0.id == listItemID }) else { break }
            let newColor = ColorInfo(red: red, green: green, blue: blue, name: colorName)
            items[itemIndex].colors.append(newColor)

        case .edit(let listItemID, let colorID):
            guard let itemIndex = items.firstIndex(where: { $0.id == listItemID }),
                  let colorIndex = items[itemIndex].colors.firstIndex(where: { $0.id == colorID }) else { break }

            let currentMethod = items[itemIndex].colors[colorIndex].method
            items[itemIndex].colors[colorIndex] = ColorInfo(
                id: colorID,
                red: red,
                green: green,
                blue: blue,
                name: colorName,
                method: currentMethod
            )
        }

        colorPickerMode = nil
    }

    private func readableTextColor(for color: ColorInfo) -> Color {
        readableTextColor(red: color.red, green: color.green, blue: color.blue)
    }

    private func readableTextColor(red: Double, green: Double, blue: Double) -> Color {
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 150 ? .black : .white
    }

    private func saveItems() {
        if let encoded = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(encoded, forKey: itemsKey)
        }
    }

    private func loadItems() {
        if let data = UserDefaults.standard.data(forKey: itemsKey),
           let decodedItems = try? JSONDecoder().decode([ListItem].self, from: data) {
            items = decodedItems
            selectedItemID = items.first?.id
        }
    }
}

private extension View {
    @ViewBuilder
    func appGlassCard(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    func appGlassButtonStyle() -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

}

#Preview {
    ContentView()
}
