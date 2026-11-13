// 20 滴本色追加配方的边界、计量、快照和旧版兼容性。
import Foundation
import Testing
@testable import Golden调色

struct ToneAdditionTests {
    /// 两套原料都从已调本色取样，底料不被重复计入总耗料。
    @Test(arguments: MixingPaintSet.selectable)
    func testTwentyDropPortionsKeepTheExactBaseAndCountOnlyNewPaint(_ paintSet: MixingPaintSet) throws {
        let palette = try makePalette(paintSet: paintSet)
        #expect(palette.base.basePortion == nil)
        #expect(palette.base.preparedTotalDrops == 200)
        #expect(palette.shadow.preparedTotalDrops == 22)
        #expect(palette.highlight.preparedTotalDrops == 26)
        #expect(palette.totalPaintDrops == 208)
        #expect(palette.remainingBaseDrops == 160)
        let distributedDrops = palette.remainingBaseDrops + palette.shadow.preparedTotalDrops + palette.highlight.preparedTotalDrops
        #expect(distributedDrops == 208)
        for recipe in [palette.shadow, palette.highlight] {
            let portion = try #require(recipe.basePortion)
            #expect(portion.drops == 20)
            #expect(portion.target == palette.base.target)
            #expect(portion.response == palette.base.response)
            #expect(recipe.basePreparation == palette.base)
            #expect(recipe.displayedPaints.allSatisfy { recipe.drops(for: $0.code) > 0 })
            let restored = try JSONDecoder().decode(MixingRecipe.self, from: JSONEncoder().encode(recipe))
            #expect(restored == recipe)
            #expect(restored.formattedText.contains("20 滴本色 +"))
            #expect(restored.formattedText.contains("先调好再取 20 滴"))
            #expect(restored.formattedText.contains("不要将原料滴数除以 10"))
            #expect(restored.basePreparation?.ingredientDrops == 200)
        }
    }

    /// 新响应必须声明底料量，不能接受旧结构或小数滴数。
    @Test
    func testNewGenerationRequiresExactlyTwentyBaseDrops() throws {
        let data = try JSONEncoder().encode(fixture())
        let original = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for role in ["shadow", "highlight"] {
            for invalid: Any in [0, 19, 21, -20, 20.5, "20", NSNull()] {
                var object = original
                var tone = try #require(object[role] as? [String: Any])
                tone["baseDrops"] = invalid
                object[role] = tone
                let changed = try JSONSerialization.data(withJSONObject: object)
                #expect(throws: MixingError.self) { try MixingPalette.decode(changed, for: .initial) }
            }
            var object = original
            var tone = try #require(object[role] as? [String: Any])
            tone.removeValue(forKey: "baseDrops")
            object[role] = tone
            let missing = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: MixingError.self) { try MixingPalette.decode(missing, for: .initial) }
        }
    }

    /// 追加的总量、色号、逐步累计量都独立复核，不能依赖 JSON Schema 代替校验。
    @Test(arguments: MixingPaintSet.selectable)
    func testInvalidAdditionsAreRejected(_ paintSet: MixingPaintSet) throws {
        let codes = paintCodes(paintSet)
        let valid = response(paintSet, white: 0, black: 2)
        let mismatch = MixingResponse(
            name: valid.name, ingredients: valid.ingredients,
            steps: [MixingStep(paintCode: codes.black, drops: 1, instruction: "搅匀")], notes: valid.notes
        )
        let missingSteps = MixingResponse(name: valid.name, ingredients: valid.ingredients, steps: [], notes: valid.notes)
        var foreign = valid.ingredients
        foreign[0] = PaintDose(paintCode: "BASE", drops: 20)
        let wrongCode = MixingResponse(name: valid.name, ingredients: foreign, steps: valid.steps, notes: valid.notes)
        var duplicate = valid.ingredients
        duplicate[0] = duplicate[1]
        let duplicateCode = MixingResponse(name: valid.name, ingredients: duplicate, steps: valid.steps, notes: valid.notes)
        let base = response(paintSet, white: 150, black: 50)
        let invalidResponses = [
            response(paintSet, white: 0, black: 0),
            response(paintSet, white: 0, black: -1),
            response(paintSet, white: 0, black: 21),
            response(paintSet, white: 11, black: 10), // 单色合规，总追加量仍超限。
            response(paintSet, white: 3, black: 1), // 与本色 150:50 比例相同。
            base, mismatch, missingSteps, wrongCode, duplicateCode
        ]
        for invalid in invalidResponses {
            #expect(throws: MixingError.self) {
                try MixingPalette(target: .initial, response: fixture(paintSet, shadow: invalid), paintSet: paintSet)
            }
        }
        // 20 滴上限可以使用，但不是必须凑足的目标总量。
        let maximum = try MixingPalette(
            target: .initial, response: fixture(paintSet, shadow: response(paintSet, white: 0, black: 20)),
            paintSet: paintSet
        )
        #expect(maximum.shadow.preparedTotalDrops == 40)
    }

    /// 即使整组中本色卡片已被删除，阴影和高光仍保留可独立执行的原配方。
    @Test
    func testBaseSnapshotSurvivesDeletingTheBaseCardAndReloading() throws {
        let suite = "ToneAdditionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var library = RecipeLibrary(defaults: defaults)
        let createdID = library.addItem(named: "20 滴追加")
        let projectID = try #require(createdID)
        let palette = try makePalette()
        let saved = library.addMixingPalette(palette, to: projectID)
        #expect(saved)
        let baseID = try #require(library.item(id: projectID)?.colors.first?.id)
        let removed = library.removeColor(itemID: projectID, colorID: baseID)
        #expect(removed)
        let reloaded = RecipeLibrary(defaults: defaults)
        let remaining = try #require(reloaded.item(id: projectID))
        #expect(remaining.colors.compactMap(\.mixingRecipe) == [palette.shadow, palette.highlight])
        for color in remaining.colors {
            #expect(color.mixingRecipe?.basePreparation == palette.base)
            #expect(color.mixingRecipe?.formattedText.contains("本色原配方快照") == true)
        }
    }

    /// 存档里的底料快照也必须完整有效，不能换成其他套装或把它再次解释成追加配方。
    @Test
    func testDamagedBaseSnapshotsCannotBypassRecipeValidation() throws {
        let palette = try makePalette()
        let original = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(palette.shadow)) as? [String: Any])
        for key in ["drops", "response"] {
            var object = original
            var portion = try #require(object["basePortion"] as? [String: Any])
            portion[key] = key == "drops" ? 19 : try JSONSerialization.jsonObject(with: JSONEncoder().encode(palette.shadow.response))
            object["basePortion"] = portion
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: MixingError.self) { try JSONDecoder().decode(MixingRecipe.self, from: data) }
        }
        var relabeled = original
        relabeled["role"] = "base"
        let data = try JSONSerialization.data(withJSONObject: relabeled)
        #expect(throws: MixingError.self) { try JSONDecoder().decode(MixingRecipe.self, from: data) }
    }

    /// 旧文件没有底料字段时，各角色仍按独立的 200 滴配方显示与复制。
    @Test(arguments: MixingRole.allCases)
    func testLegacyIndependentToneRecipesRetainTheirOriginalInstructions(_ role: MixingRole) throws {
        let original = try MixingRecipe(
            target: .initial, response: response(.soFlat12, white: 150, black: 50),
            role: role, paintSet: .soFlat12
        )
        let decoded = try JSONDecoder().decode(MixingRecipe.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.basePortion == nil)
        #expect(decoded.basePreparation == nil)
        #expect(decoded.preparedTotalDrops == 200)
        #expect(decoded.quantitySummary == "合计 200 滴")
        #expect(!decoded.formattedText.contains("另取干净调色杯"))
    }

    /// 普通调色和合色共用新增计量结构，本色 Schema 不允许零步配方。
    @Test(arguments: MixingPaintSet.selectable)
    func testSchemasAndPromptsDistinguishBaseFromAdditions(_ paintSet: MixingPaintSet) throws {
        let schema = try #require(JSONSerialization.jsonObject(with: MixingPalette.outputSchema(paintSet: paintSet)) as? [String: Any])
        let fields = try #require(schema["properties"] as? [String: Any])
        for role in ["shadow", "highlight"] {
            let tone = try #require(fields[role] as? [String: Any])
            #expect((tone["required"] as? [String])?.contains("baseDrops") == true)
            let properties = try #require(tone["properties"] as? [String: Any])
            let baseDrops = try #require(properties["baseDrops"] as? [String: Any])
            #expect(baseDrops["enum"] as? [Int] == [20])
            let recipe = try #require(properties["recipe"] as? [String: Any])
            let recipeFields = try #require(recipe["properties"] as? [String: Any])
            let ingredients = try #require(recipeFields["ingredients"] as? [String: Any])
            let item = try #require(ingredients["items"] as? [String: Any])
            let doseFields = try #require(item["properties"] as? [String: Any])
            let drops = try #require(doseFields["drops"] as? [String: Any])
            #expect(drops["maximum"] as? Int == 20)
            let steps = try #require(recipeFields["steps"] as? [String: Any])
            #expect(steps["minItems"] as? Int == 0)
        }
        let prompt = MixingPalette.prompt(for: .initial, paintSet: paintSet)
        #expect(prompt.contains("各取 20 滴"))
        #expect(prompt.contains("本色剩余 160 滴"))
        #expect(prompt.contains("不是将本色原料逐项除以 10"))
        #expect(prompt.contains("保持本色色相协调"))
        #expect(prompt.contains("min(18.0"))
        #expect(!prompt.contains("三份共 600 滴"))
        let request = try ColorBlendRequest(sources: [
            ColorBlendSource(target: .initial, percentage: 50),
            ColorBlendSource(target: MixingTarget(red: 100, green: 100, blue: 100), percentage: 50)
        ])
        #expect(request.prompt(paintSet: paintSet).contains(MixingPalette.recipeInstructions(paintSet: paintSet)))
    }

    // MARK: - 固定响应
    private func makePalette(paintSet: MixingPaintSet = .soFlat12) throws -> MixingPalette {
        try MixingPalette(target: .initial, response: fixture(paintSet), paintSet: paintSet)
    }

    private func fixture(_ paintSet: MixingPaintSet = .soFlat12, shadow: MixingResponse? = nil) -> MixingPaletteResponse {
        MixingPaletteResponse(
            base: response(paintSet, white: 150, black: 50),
            shadow: MixingToneResponse(
                target: MixingTarget(red: 64, green: 80, blue: 64),
                recipe: shadow ?? response(paintSet, white: 0, black: 2)
            ),
            highlight: MixingToneResponse(
                target: MixingTarget(red: 220, green: 235, blue: 220),
                recipe: response(paintSet, white: 6, black: 0)
            )
        )
    }

    private func paintCodes(_ paintSet: MixingPaintSet) -> (white: String, black: String) {
        paintSet == .fluid15 ? ("2380", "2040") : ("6755", "6745")
    }

    /// 样本仅用于计量与存档测试，不表示实测的颜料成色。
    private func response(_ paintSet: MixingPaintSet, white: Int, black: Int) -> MixingResponse {
        let codes = paintCodes(paintSet)
        let ingredients = paintSet.paints.map {
            PaintDose(paintCode: $0.code, drops: $0.code == codes.white ? white : ($0.code == codes.black ? black : 0))
        }
        return MixingResponse(
            name: "计量样本", ingredients: ingredients,
            steps: ingredients.filter { $0.drops > 0 }.map {
                MixingStep(paintCode: $0.paintCode, drops: $0.drops, instruction: "充分搅匀，薄涂后观察。")
            },
            notes: "计量测试样本，实际使用需干燥后对色。"
        )
    }
}
