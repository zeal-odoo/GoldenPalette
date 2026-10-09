import Foundation

struct ColorInfo: Codable, Identifiable, Equatable {
    var id = UUID()
    var red: Double
    var green: Double
    var blue: Double
    var name: String = ""
    var paintName: String?
    var paintCode: String?
    var paintSeries: String?
    var method: String = ""
    var mixingRecipe: MixingRecipe?

    private enum CodingKeys: String, CodingKey {
        case id, red, green, blue, name, paintName, paintCode, paintSeries, method, mixingRecipe
    }

    static func clampedRGB(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(255, max(0, value))
    }

    func normalized() -> ColorInfo {
        var color = self
        color.red = Self.clampedRGB(red)
        color.green = Self.clampedRGB(green)
        color.blue = Self.clampedRGB(blue)
        if let recipe = color.mixingRecipe {
            let changedRGB = Double(recipe.target.red) != color.red
                || Double(recipe.target.green) != color.green || Double(recipe.target.blue) != color.blue
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

extension ColorInfo {
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

struct ListItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var colors: [ColorInfo] = []

    private enum CodingKeys: String, CodingKey {
        case id, text, colors
    }
}

extension ListItem {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            text: try values.decode(String.self, forKey: .text),
            colors: try values.decodeIfPresent([ColorInfo].self, forKey: .colors) ?? []
        )
    }
}

/// Shared by the app's windows; all edits resolve stable IDs before saving.
struct RecipeLibrary {
    static let itemsKey = "SavedItems"

    private(set) var items: [ListItem]
    private(set) var isReadOnly = false
    var errorMessage: String?

    private let defaults: UserDefaults?

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

    init(previewItems: [ListItem]) {
        defaults = nil
        items = previewItems.map { item in
            var item = item
            item.colors = item.colors.map { $0.normalized() }
            return item
        }
    }

    func item(id: UUID) -> ListItem? {
        items.first { $0.id == id }
    }

    func color(itemID: UUID, colorID: UUID) -> ColorInfo? {
        item(id: itemID)?.colors.first { $0.id == colorID }
    }

    @discardableResult
    mutating func addItem(named name: String) -> UUID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let item = ListItem(text: name)
        return save(items + [item]) ? item.id : nil
    }

    @discardableResult
    mutating func removeItem(id: UUID) -> Bool {
        guard items.contains(where: { $0.id == id }) else { return false }
        return save(items.filter { $0.id != id })
    }

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

    @discardableResult
    mutating func renameItem(id: UUID, to name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let index = items.firstIndex(where: { $0.id == id }) else { return false }
        var updatedItems = items
        updatedItems[index].text = name
        return save(updatedItems)
    }

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
            // A floating color editor must preserve method edits made after it opened.
            savedColor.method = items[itemIndex].colors[colorIndex].method
            savedColor.mixingRecipe = items[itemIndex].colors[colorIndex].mixingRecipe
            updatedItems[itemIndex].colors[colorIndex] = savedColor.normalized()
        }

        return save(updatedItems)
    }

    @discardableResult
    mutating func addMixingPalette(_ palette: MixingPalette, to projectID: UUID) -> Bool {
        // Keep the project chosen when mixing opened, even if another window changes selection.
        guard let index = items.firstIndex(where: { $0.id == projectID }) else { return false }
        let colors = palette.recipes.map { recipe in
            ColorInfo(
                red: Double(recipe.target.red),
                green: Double(recipe.target.green),
                blue: Double(recipe.target.blue),
                name: "\(recipe.role.title) · \(recipe.response.name)",
                method: recipe.response.notes,
                mixingRecipe: recipe
            )
        }
        var updatedItems = items
        updatedItems[index].colors.append(contentsOf: colors)
        // Save once so all three tones are appended together without replacing existing colors.
        return save(updatedItems)
    }

    static var legacyPreferencesURL: URL? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers")
            .appendingPathComponent(bundleID)
            .appendingPathComponent("Data/Library/Preferences")
            .appendingPathComponent("\(bundleID).plist")
    }

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
