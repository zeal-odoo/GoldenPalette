import Foundation
import Testing
@testable import Golden调色

struct Golden__Tests {
    @Test
    func testLegacyColorsDecodeWithoutNewFields() throws {
        let json = #"""
        [{"id":"00000000-0000-0000-0000-000000000001","text":"旧配方","colors":[
            {"id":"00000000-0000-0000-0000-000000000002","red":128,"green":64,"blue":32}
        ]}]
        """#
        let items = try JSONDecoder().decode([ListItem].self, from: Data(json.utf8))
        let color = try #require(items.first?.colors.first)
        #expect(items.first?.text == "旧配方")
        #expect(color.id.uuidString == "00000000-0000-0000-0000-000000000002")
        #expect(color.name.isEmpty)
        #expect(color.method.isEmpty)
        #expect(color.paintCode == nil)
        #expect(color.red == 128)
    }

    @Test
    func testLegacyRecipeWithoutColorsDecodesAsEmpty() throws {
        let data = Data(#"{"text":"空配方"}"#.utf8)
        let item = try JSONDecoder().decode(ListItem.self, from: data)
        #expect(item.text == "空配方")
        #expect(item.colors.isEmpty)
    }

    @Test
    func testColorEncodingPreservesAllFields() throws {
        let color = ColorInfo(
            red: 123.5, green: 64, blue: 32,
            name: "披风", paintName: "Pyrrole Red",
            paintCode: "2277", paintSeries: "8", method: "薄涂两层\n保留阴影"
        )
        let original = [ListItem(text: "模型", colors: [color])]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([ListItem].self, from: data)
        #expect(decoded == original)
    }

    @Test
    func testExtremeRGBValuesDecodeSafely() throws {
        let data = Data(#"{"red":1e100,"green":-20,"blue":300}"#.utf8)
        let color = try JSONDecoder().decode(ColorInfo.self, from: data)
        #expect(Int(color.red) == 255)
        #expect(Int(color.green) == 0)
        #expect(Int(color.blue) == 255)
    }

    @Test
    func testMalformedSavedDataIsNotOverwritten() throws {
        try withTemporaryDefaults { defaults in
            let original = Data(#"[{"text":"损坏配方","colors":[{"red":"invalid"}]}]"#.utf8)
            defaults.set(original, forKey: RecipeLibrary.itemsKey)
            var library = RecipeLibrary(defaults: defaults)

            #expect(library.isReadOnly)
            #expect(library.errorMessage != nil)
            let addItemResult = library.addItem(named: "新配方")
            #expect(addItemResult == nil)
            #expect(defaults.data(forKey: RecipeLibrary.itemsKey) == original)
        }
    }

    @Test
    func testUnexpectedStoredValueIsNotOverwritten() throws {
        try withTemporaryDefaults { defaults in
            defaults.set("unreadable data", forKey: RecipeLibrary.itemsKey)
            var library = RecipeLibrary(defaults: defaults)

            #expect(library.isReadOnly)
            let addItemResult = library.addItem(named: "新配方")
            #expect(addItemResult == nil)
            #expect(defaults.string(forKey: RecipeLibrary.itemsKey) == "unreadable data")
        }
    }

    @Test
    func testLoadingLegacyDataDoesNotRewriteStorage() throws {
        try withTemporaryDefaults { defaults in
            let original = Data(#"[{"text":"旧配方","colors":[{"red":20,"green":30,"blue":40}]}]"#.utf8)
            defaults.set(original, forKey: RecipeLibrary.itemsKey)
            var library = RecipeLibrary(defaults: defaults)

            #expect(!library.isReadOnly)
            #expect(library.items.count == 1)
            #expect(defaults.data(forKey: RecipeLibrary.itemsKey) == original)

            let id = try #require(library.items.first?.id)
            let renameItemResult = library.renameItem(id: id, to: "恢复的配方")
            #expect(renameItemResult)
            #expect(RecipeLibrary(defaults: defaults).items == library.items)
        }
    }

    @Test
    func testRecipeAndColorEditsSurviveReload() throws {
        try withTemporaryDefaults { defaults in
            var library = RecipeLibrary(defaults: defaults)
            let addItemResult = library.addItem(named: "  披风  ")
            let itemID = try #require(addItemResult)
            let commitColorChangeResult = library.commitColorChange(
                ColorInfo(red: 120, green: 30, blue: 40, name: "主色"),
                for: .add(listItemID: itemID)
            )
            #expect(commitColorChangeResult)
            let colorID = try #require(library.item(id: itemID)?.colors.first?.id)
            let updateMethodResult = library.updateMethod("薄涂两层", itemID: itemID, colorID: colorID)
            #expect(updateMethodResult)
            let renameItemResult = library.renameItem(id: itemID, to: "  红色披风\n")
            #expect(renameItemResult)

            let reloaded = RecipeLibrary(defaults: defaults)
            #expect(reloaded.items == library.items)
            #expect(reloaded.item(id: itemID)?.text == "红色披风")
            #expect(reloaded.color(itemID: itemID, colorID: colorID)?.method == "薄涂两层")

            let removeItemResult = library.removeItem(id: itemID)
            #expect(removeItemResult)
            #expect(RecipeLibrary(defaults: defaults).items.isEmpty)
        }
    }

    @Test
    func testColorEditorPreservesLatestMethodAndIdentity() throws {
        let originalColor = ColorInfo(red: 10, green: 20, blue: 30, method: "原方法")
        let item = ListItem(text: "配方", colors: [originalColor])
        var library = RecipeLibrary(previewItems: [item])
        let draft = ColorInfo(
            red: 100, green: 110, blue: 120, name: "新名称",
            paintName: "Titan Buff", paintCode: "2370", paintSeries: "1", method: "旧草稿"
        )

        let updateMethodResult = library.updateMethod("新方法", itemID: item.id, colorID: originalColor.id)
        #expect(updateMethodResult)
        let commitColorChangeResult = library.commitColorChange(draft, for: .edit(listItemID: item.id, colorID: originalColor.id))
        #expect(commitColorChangeResult)

        let saved = try #require(library.color(itemID: item.id, colorID: originalColor.id))
        #expect(saved.id == originalColor.id)
        #expect(saved.method == "新方法")
        #expect(saved.name == "新名称")
        #expect(saved.red == 100)
        #expect(saved.paintCode == "2370")
        #expect(saved.paintName == "Titan Buff")
    }

    @Test
    func testEditingUsesIDsAfterEarlierRecipeIsRemoved() throws {
        let first = ListItem(text: "第一个")
        let color = ColorInfo(red: 50, green: 60, blue: 70)
        let second = ListItem(text: "第二个", colors: [color])
        var library = RecipeLibrary(previewItems: [first, second])

        let removeItemResult = library.removeItem(id: first.id)
        #expect(removeItemResult)
        let renameItemResult = library.renameItem(id: second.id, to: "保留的配方")
        #expect(renameItemResult)
        let updateMethodResult = library.updateMethod("当前方法", itemID: second.id, colorID: color.id)
        #expect(updateMethodResult)
        let commitColorChangeResult = library.commitColorChange(
            ColorInfo(red: 100, green: 110, blue: 120),
            for: .edit(listItemID: second.id, colorID: color.id)
        )
        #expect(commitColorChangeResult)
        let saved = try #require(library.items.first)
        #expect(saved.id == second.id)
        #expect(saved.text == "保留的配方")
        #expect(saved.colors.first?.method == "当前方法")
        #expect(saved.colors.first?.red == 100)
    }

    @Test
    func testStaleEditsCannotModifyAnotherRecipe() {
        let removedColor = ColorInfo(red: 10, green: 20, blue: 30)
        let removed = ListItem(text: "已删除", colors: [removedColor])
        let survivor = ListItem(text: "保留", colors: [ColorInfo(red: 40, green: 50, blue: 60)])
        var library = RecipeLibrary(previewItems: [removed, survivor])

        let removeItemResult = library.removeItem(id: removed.id)
        #expect(removeItemResult)
        let renameItemResult = library.renameItem(id: removed.id, to: "错误名称")
        #expect(!renameItemResult)
        let updateMethodResult = library.updateMethod("错误方法", itemID: removed.id, colorID: removedColor.id)
        #expect(!updateMethodResult)
        let commitColorChangeResult = library.commitColorChange(removedColor, for: .add(listItemID: removed.id))
        #expect(!commitColorChangeResult)
        let commitColorChangeResult2 = library.commitColorChange(
            removedColor, for: .edit(listItemID: survivor.id, colorID: removedColor.id)
        )
        #expect(!commitColorChangeResult2)
        #expect(library.items == [survivor])
    }

    @Test
    func testAddingFromExistingColorCreatesANewIdentity() throws {
        let color = ColorInfo(red: 100, green: 120, blue: 140)
        let item = ListItem(text: "配方", colors: [color])
        var library = RecipeLibrary(previewItems: [item])

        let commitColorChangeResult = library.commitColorChange(color, for: .add(listItemID: item.id))
        #expect(commitColorChangeResult)
        let colors = try #require(library.item(id: item.id)?.colors)
        #expect(colors.count == 2)
        #expect(Set(colors.map(\.id)).count == 2)
        #expect(colors.last?.red == color.red)
    }

    @Test
    func testNonFiniteRGBValuesCannotBreakSaving() throws {
        try withTemporaryDefaults { defaults in
            var library = RecipeLibrary(defaults: defaults)
            let addItemResult = library.addItem(named: "配方")
            let id = try #require(addItemResult)
            let commitColorChangeResult = library.commitColorChange(
                ColorInfo(red: .nan, green: .infinity, blue: -.infinity),
                for: .add(listItemID: id)
            )
            #expect(commitColorChangeResult)
            let saved = try #require(RecipeLibrary(defaults: defaults).item(id: id)?.colors.first)
            #expect(saved.red == 0)
            #expect(saved.green == 0)
            #expect(saved.blue == 0)
        }
    }

    @Test
    func testBlankNamesDoNotReplaceSavedNames() throws {
        var library = RecipeLibrary(previewItems: [])
        let addItemResult = library.addItem(named: " \n ")
        #expect(addItemResult == nil)
        let addItemResult2 = library.addItem(named: "原名称")
        let id = try #require(addItemResult2)
        let renameItemResult = library.renameItem(id: id, to: "\n ")
        #expect(!renameItemResult)
        #expect(library.item(id: id)?.text == "原名称")
    }

    @Test
    func testDeletingOneColorPersistsWithoutChangingOtherColorsOrProjects() throws {
        try withTemporaryDefaults { defaults in
            let removed = ColorInfo(red: 10, green: 20, blue: 30, name: "同名颜色", method: "删除这份")
            let kept = ColorInfo(red: 40, green: 50, blue: 60, name: "同名颜色", method: "保留这份")
            let project = ListItem(text: "当前项目", colors: [removed, kept])
            let other = ListItem(text: "其他项目", colors: [removed])
            defaults.set(try JSONEncoder().encode([project, other]), forKey: RecipeLibrary.itemsKey)
            var library = RecipeLibrary(defaults: defaults)

            let deleted = library.removeColor(itemID: project.id, colorID: removed.id)
            #expect(deleted)
            let reloaded = RecipeLibrary(defaults: defaults)
            #expect(reloaded.items.count == 2)
            #expect(reloaded.item(id: project.id)?.colors == [kept])
            #expect(reloaded.item(id: project.id)?.text == project.text)
            #expect(reloaded.item(id: other.id) == other)
        }
    }

    @Test
    func testDeletingLastColorKeepsProjectAndRejectsStaleEdits() throws {
        let color = ColorInfo(red: 10, green: 20, blue: 30)
        let project = ListItem(text: "保留的项目", colors: [color])
        var library = RecipeLibrary(previewItems: [project])

        let wrongProject = library.removeColor(itemID: UUID(), colorID: color.id)
        let wrongColor = library.removeColor(itemID: project.id, colorID: UUID())
        #expect(!wrongProject && !wrongColor)
        #expect(library.items == [project])

        let deleted = library.removeColor(itemID: project.id, colorID: color.id)
        #expect(deleted)
        let deletedAgain = library.removeColor(itemID: project.id, colorID: color.id)
        let staleSave = library.commitColorChange(color, for: .edit(listItemID: project.id, colorID: color.id))
        let staleMethod = library.updateMethod("过期修改", itemID: project.id, colorID: color.id)
        #expect(!deletedAgain && !staleSave && !staleMethod)
        let saved = try #require(library.item(id: project.id))
        #expect(saved.colors.isEmpty)
        #expect(saved.text == project.text)
        #expect(library.items.count == 1)
    }

    private func withTemporaryDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "GoldenRecipeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }
}
