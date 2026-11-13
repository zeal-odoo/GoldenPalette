// 项目颜色库的数据模型与持久化入口。
// 所有修改先按稳定 UUID 查找，再保存完整快照，避免多窗口编辑时误用旧数组下标。
import Foundation

/// 项目中保存的一个颜色，兼容手工 RGB、商品参考色及 AI 调色配方。
struct ColorInfo: Codable, Identifiable, Equatable {
    var id = UUID()
    /// RGB 使用 0...255 的 Double 保存，以兼容编辑器与历史数据。
    var red: Double
    var green: Double
    var blue: Double
    var name: String = ""
    /// 商品参考信息可为空；系列与色号共同确定具体颜料。
    var paintName: String?
    var paintCode: String?
    var paintSeries: String?
    /// 用户调色说明，也可附带说明书考证来源；与结构化配方分别保存。
    var method: String = ""
    var mixingRecipe: MixingRecipe?

    /// 显式保留存档字段名称，供兼容解码使用。
    private enum CodingKeys: String, CodingKey {
        case id, red, green, blue, name, paintName, paintCode, paintSeries, method, mixingRecipe
    }

    /// 将非法或越界通道值收敛到可展示范围；非有限值按 0 处理。
    static func clampedRGB(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(255, max(0, value))
    }

    /// 规范化 RGB；目标色或商品引用改变时移除已不匹配的结构化配方。
    func normalized() -> ColorInfo {
        var color = self
        color.red = Self.clampedRGB(red)
        color.green = Self.clampedRGB(green)
        color.blue = Self.clampedRGB(blue)
        if let recipe = color.mixingRecipe {
            let changedRGB = Double(recipe.target.red) != color.red
                || Double(recipe.target.green) != color.green || Double(recipe.target.blue) != color.blue
            // 仅比较 RGB 不足以识别参考漆变化：不同系列可能共享色号和近似色。
            // Different reference series can share a code and the same approximate RGB.
            let changedReference = recipe.referencePaint.map { reference in
                guard let paintCode = color.paintCode else { return false }
                return paintCode != reference.paintCode || PaintSeries.forColor(color) != reference.series
            } ?? false
            if changedRGB || changedReference { color.mixingRecipe = nil }
        }
        return color
    }
}

// MARK: - 历史存档兼容
extension ColorInfo {
    /// 旧存档可缺少名称、商品信息或配方；新增字段使用合理默认值。
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            red: Self.clampedRGB(try values.decode(Double.self, forKey: .red)),
            green: Self.clampedRGB(try values.decode(Double.self, forKey: .green)),
            blue: Self.clampedRGB(try values.decode(Double.self, forKey: .blue)),
            name: try values.decodeIfPresent(String.self, forKey: .name) ?? "",
            paintName: try values.decodeIfPresent(String.self, forKey: .paintName),
            paintCode: try values.decodeIfPresent(String.self, forKey: .paintCode),
            paintSeries: try values.decodeIfPresent(String.self, forKey: .paintSeries),
            method: try values.decodeIfPresent(String.self, forKey: .method) ?? "",
            mixingRecipe: try values.decodeIfPresent(MixingRecipe.self, forKey: .mixingRecipe)
        )
    }
}

/// 一个模型项目及其颜色集合，项目名称与 UUID 分开保存。
struct ListItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var colors: [ColorInfo] = []

    /// 项目 JSON 的稳定字段集合。
    private enum CodingKeys: String, CodingKey {
        case id, text, colors
    }
}

extension ListItem {
    /// 兼容没有 id 或 colors 字段的早期项目数据。
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            text: try values.decode(String.self, forKey: .text),
            colors: try values.decodeIfPresent([ColorInfo].self, forKey: .colors) ?? []
        )
    }
}

/// 供应用窗口共享的值类型颜色库，集中执行校验、变更和保存。
/// Shared by the app's windows; all edits resolve stable IDs before saving.
struct RecipeLibrary {
    /// 沿用历史偏好键，以便升级后继续读取已有项目。
    static let itemsKey = "SavedItems"

    private(set) var items: [ListItem]
    /// 读取失败后进入只读状态，阻止空数据覆盖原始存档。
    private(set) var isReadOnly = false
    var errorMessage: String?

    private let defaults: UserDefaults?

    /// 加载当前偏好；仅在不存在新存档时尝试从旧沙盒容器迁移有效数据。
    init(defaults: UserDefaults = .standard, legacyPreferencesURL: URL? = nil) {
        self.defaults = defaults
        items = []

        do {
            var storedValue = defaults.object(forKey: Self.itemsKey)
            var shouldMigrate = false
            if storedValue == nil, let url = legacyPreferencesURL,
               FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                guard let preferences = try PropertyListSerialization.propertyList(
                    from: data, options: [], format: nil
                ) as? [String: Any] else { throw CocoaError(.coderReadCorrupt) }
                storedValue = preferences[Self.itemsKey]
                shouldMigrate = storedValue != nil
            }
            guard let storedValue else { return }
            guard let data = storedValue as? Data else {
                throw CocoaError(.coderReadCorrupt)
            }
            items = try JSONDecoder().decode([ListItem].self, from: data)
            // 迁移只复制成功解码的数据，旧容器原文件仍保留。
            // Copy only valid recipe data from the former sandbox container; keep the original.
            if shouldMigrate {
                defaults.set(data, forKey: Self.itemsKey)
            }
        } catch {
            // Never replace unreadable user data with an empty recipe collection.
            isReadOnly = true
            errorMessage = "无法读取已保存的项目。原始数据已保留，为避免覆盖，暂时无法编辑。请恢复数据后重新打开应用。"
        }
    }

    /// 创建不写入磁盘的预览或测试库，并预先规范化颜色。
    init(previewItems: [ListItem]) {
        defaults = nil
        items = previewItems.map { item in
            var item = item
            item.colors = item.colors.map { $0.normalized() }
            return item
        }
    }

    /// 按项目 UUID 读取最新项目快照。
    func item(id: UUID) -> ListItem? {
        items.first { $0.id == id }
    }

    /// 同时校验项目与颜色身份，适用于独立编辑窗口的回查。
    func color(itemID: UUID, colorID: UUID) -> ColorInfo? {
        item(id: itemID)?.colors.first { $0.id == colorID }
    }

    /// 新建非空项目；只有保存成功才返回可选中的项目 UUID。
    @discardableResult
    mutating func addItem(named name: String) -> UUID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let item = ListItem(text: name)
        return save(items + [item]) ? item.id : nil
    }

    /// 删除指定项目；目标已不存在时返回 false。
    @discardableResult
    mutating func removeItem(id: UUID) -> Bool {
        guard items.contains(where: { $0.id == id }) else { return false }
        return save(items.filter { $0.id != id })
    }

    /// 按双层 UUID 删除颜色，避免列表变化后误删相邻项。
    @discardableResult
    mutating func removeColor(itemID: UUID, colorID: UUID) -> Bool {
        guard let itemIndex = items.firstIndex(where: { $0.id == itemID }),
              let colorIndex = items[itemIndex].colors.firstIndex(where: { $0.id == colorID }) else {
            return false
        }
        var updatedItems = items
        updatedItems[itemIndex].colors.remove(at: colorIndex)
        return save(updatedItems)
    }

    /// 去掉首尾空白后重命名项目，保持原有项目身份和颜色。
    @discardableResult
    mutating func renameItem(id: UUID, to name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let index = items.firstIndex(where: { $0.id == id }) else { return false }
        var updatedItems = items
        updatedItems[index].text = name
        return save(updatedItems)
    }

    /// 单独更新方法说明，避免覆盖同时发生的颜色编辑。
    @discardableResult
    mutating func updateMethod(_ method: String, itemID: UUID, colorID: UUID) -> Bool {
        guard let itemIndex = items.firstIndex(where: { $0.id == itemID }),
              let colorIndex = items[itemIndex].colors.firstIndex(where: { $0.id == colorID }) else {
            return false
        }
        var updatedItems = items
        updatedItems[itemIndex].colors[colorIndex].method = method
        return save(updatedItems)
    }

    /// 提交颜色编辑草稿；编辑已有颜色时保留窗口打开后最新的方法和配方。
    @discardableResult
    mutating func commitColorChange(_ color: ColorInfo, for mode: ColorPickerMode) -> Bool {
        guard let itemIndex = items.firstIndex(where: { $0.id == mode.listItemID }) else { return false }
        var updatedItems = items
        var savedColor = color.normalized()

        switch mode {
        case .add:
            savedColor.id = UUID()
            updatedItems[itemIndex].colors.append(savedColor)

        case .edit(_, let colorID):
            guard let colorIndex = items[itemIndex].colors.firstIndex(where: { $0.id == colorID }) else {
                return false
            }
            savedColor.id = colorID
            // 浮动编辑器可能持有旧快照，文本方法和配方以库中最新值为准，再检查是否仍匹配。
            // A floating color editor must preserve method edits made after it opened.
            savedColor.method = items[itemIndex].colors[colorIndex].method
            savedColor.mixingRecipe = items[itemIndex].colors[colorIndex].mixingRecipe
            updatedItems[itemIndex].colors[colorIndex] = savedColor.normalized()
        }

        return save(updatedItems)
    }

    /// 将整组色阶一次加入原项目，可附加考证背景，保持三种角色一起保存。
    @discardableResult
    mutating func addMixingPalette(_ palette: MixingPalette, to projectID: UUID, context: String = "") -> Bool {
        // Keep the project chosen when mixing opened, even if another window changes selection.
        guard let index = items.firstIndex(where: { $0.id == projectID }) else { return false }
        let colors = palette.recipes.map { recipe in
            ColorInfo(
                red: Double(recipe.target.red),
                green: Double(recipe.target.green),
                blue: Double(recipe.target.blue),
                name: "\(recipe.role.title) · \(recipe.response.name)",
                method: [recipe.response.notes, context].filter { !$0.isEmpty }.joined(separator: "\n\n"),
                mixingRecipe: recipe
            )
        }
        var updatedItems = items
        updatedItems[index].colors.append(contentsOf: colors)
        // Save once so all three tones are appended together without replacing existing colors.
        return save(updatedItems)
    }

    /// 构造旧沙盒偏好文件的位置，用于首次启动时的单向迁移。
    static var legacyPreferencesURL: URL? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers")
            .appendingPathComponent(bundleID)
            .appendingPathComponent("Data/Library/Preferences")
            .appendingPathComponent("\(bundleID).plist")
    }

    /// 编码成功后再提交内存快照；失败保留当前数据并返回可展示的错误。
    private mutating func save(_ updatedItems: [ListItem]) -> Bool {
        guard !isReadOnly else { return false }
        guard updatedItems != items else { return true }

        do {
            if let defaults {
                let data = try JSONEncoder().encode(updatedItems)
                defaults.set(data, forKey: Self.itemsKey)
            }
            items = updatedItems
            errorMessage = nil
            return true
        } catch {
            errorMessage = "无法保存项目，本次修改尚未保存：\(error.localizedDescription)"
            return false
        }
    }
}
