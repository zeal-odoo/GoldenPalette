// 色库与商品参考色回归测试：验证系列身份、原料套装、来源色样及历史配方兼容。
// 参数化用例对每个当前可选套装重复执行，防止某一套装漏掉同样的约束。
import Foundation
import Testing
@testable import Golden调色

/// 重点保证“目标参考色”与“实际调色原料”始终分开解释。
struct PaintCatalogTests {
    /// 目录身份必须包含系列，且不能混入不属于有色颜料的产品。
    @Test
    func testCatalogsKeepSeriesIdentityAndExcludeNonPaintProducts() throws {
        let expectedCounts: [PaintSeries: Int] = [
            .goldenSoFlat: 12, .goldenFluid: 15, .tamiyaAcrylic: 101, .tamiyaEnamel: 82,
            .tamiyaLacquer: 79, .tamiyaSpray: 98, .tamiyaAircraft: 33, .tamiyaPolycarbonate: 60, .mrColor: 50, .aqueous: 38, .acrysion: 40
        ]
        var ids = Set<String>()
        for series in PaintSeries.allCases {
            #expect(series.paints.count == expectedCounts[series])
            #expect(Set(series.paints.map(\.code)).count == series.paints.count)
            for paint in series.paints {
                #expect(paint.series == series)
                #expect(ids.insert(paint.id).inserted)
                #expect(!paint.name.isEmpty && !paint.chineseName.isEmpty)
                #expect(paint.hex.count == 6 && Int(paint.hex, radix: 16) != nil)
            }
        }
        #expect(PaintSeries.goldenSoFlat.paints.map(\.code) == GoldenPaint.all.map(\.code))
        #expect(PaintSeries.tamiyaAcrylic.matchingPaints("xf2").first?.code == "XF-2")
        #expect(PaintSeries.mrColor.matchingPaints("钴蓝").first?.code == "C80")
        #expect(!PaintSeries.tamiyaLacquer.paints.contains { ["LP-9", "LP-10", "LP-22"].contains($0.code) })
        #expect(!PaintSeries.acrysion.paints.contains { ["N29", "N40"].contains($0.code) })
        let acrylicWhite = try #require(PaintSeries.tamiyaAcrylic.paints.first { $0.code == "X-2" })
        let enamelWhite = try #require(PaintSeries.tamiyaEnamel.paints.first { $0.code == "X-2" })
        #expect(acrylicWhite.id != enamelWhite.id)
    }
    /// 以官网实际编号范围核对六类田宫颜色，避免按最大号码把空号或无色涂层当作颜色。
    @Test
    func testCompleteTamiyaCatalogMatchesVerifiedProductRanges() {
        let gloss = Array(1...19) + Array(23...28) + Array(31...34)
        let acrylicFlat = Array(1...28) + Array(49...85) + Array(87...93)
        let enamelFlat = Array(1...28) + Array(49...66) + [70, 71, 84, 85]
        let expected: [PaintSeries: Set<String>] = [
            .tamiyaAcrylic: Set(gloss.map { "X-\($0)" } + acrylicFlat.map { "XF-\($0)" }),
            .tamiyaEnamel: Set(gloss.map { "X-\($0)" } + enamelFlat.map { "XF-\($0)" }),
            .tamiyaLacquer: Set((1...85).filter { ![9, 10, 22, 23, 24, 49].contains($0) }.map { "LP-\($0)" }),
            .tamiyaSpray: Set((1...102).filter { ![13, 65, 79, 80].contains($0) }.map { "TS-\($0)" }),
            .tamiyaAircraft: Set((1...33).map { "AS-\($0)" }),
            .tamiyaPolycarbonate: Set((1...63).filter { ![26, 53, 55, 58].contains($0) }.map { "PS-\($0)" } + ["69944"])
        ]
        #expect(Set(PaintBrand.tamiya.series) == Set(expected.keys))
        for (series, codes) in expected {
            #expect(Set(series.matchingPaints("").map(\.code)) == codes)
        }
        #expect(PaintBrand.tamiya.series.reduce(0) { $0 + $1.matchingPaints("").count } == 450)
        #expect(PaintSeries.tamiyaEnamel.matchingPaints("XF-90").isEmpty)
        #expect(PaintSeries.tamiyaPolycarbonate.matchingPaints("PS-64").isEmpty)
        #expect(PaintSeries.tamiyaPolycarbonate.matchingPaints("69944").first?.name == "PS Dark Blue (Special Edition)")
    }

    /// 用户报告的 XF-85 在两个真实漆系中均可搜索，并能进入 GOLDEN 调色和快照保存。
    @Test(arguments: [PaintSeries.tamiyaAcrylic, .tamiyaEnamel])
    func testRubberBlackSearchAndRecipeRoundTrip(_ series: PaintSeries) throws {
        for search in ["XF-85", "xf85", "橡胶黑", "Rubber Black"] {
            #expect(series.matchingPaints(search).map(\.code) == ["XF-85"])
        }
        let reference = PaintReference(series: series, paintCode: "XF-85")
        let target = try #require(reference.previewTarget)
        #expect(target == MixingTarget(red: 35, green: 25, blue: 22))
        #expect(reference.paint?.hex == "231916")
        #expect(PaintSwatchData.swatch(series: series, code: "XF-85")?.source == .tamiyaChart)
        for paintSet in MixingPaintSet.selectable {
            let prompt = MixingPalette.prompt(for: target, referencePaint: reference, paintSet: paintSet)
            #expect(prompt.contains(reference.summary))
            #expect(prompt.contains(reference.previewNote))
            let recipe = try MixingRecipe(
                target: target, response: paletteResponse(paintSet: paintSet).base,
                paintSeries: paintSet.primarySeries, paintSet: paintSet, referencePaint: reference
            )
            #expect(try JSONDecoder().decode(MixingRecipe.self, from: JSONEncoder().encode(recipe)) == recipe)
            #expect(recipe.response.ingredients.allSatisfy { !$0.paintCode.hasPrefix("XF-") })
        }
    }

    /// 未获官网确认的旧珐琅色不再供选择；读取旧引用仍保留原来的身份和快照。
    @Test
    func testUnverifiedEnamelEntriesStayReadableWithoutAppearingInNewSearches() throws {
        for code in ["XF-67", "XF-68", "XF-69"] {
            #expect(PaintSeries.tamiyaEnamel.matchingPaints(code).isEmpty)
            #expect(PaintSeries.tamiyaAcrylic.matchingPaints(code).map(\.code) == [code])
            let reference = PaintReference(series: .tamiyaEnamel, paintCode: code)
            try reference.validate()
            #expect(reference.paint?.isSelectable == false)
            #expect(reference.previewNote.contains("当前官方目录未确认"))
            #expect(try JSONDecoder().decode(PaintReference.self, from: JSONEncoder().encode(reference)) == reference)
        }
    }

    /// 新增金属、透明和变色商品的使用限制会传入 AI，并保留 PS 的材料说明。
    @Test
    func testExpandedTamiyaEffectsCarryTheirLimitationsIntoPrompts() throws {
        let cases: [(PaintSeries, String)] = [
            (.tamiyaAcrylic, "X-11"), (.tamiyaEnamel, "X-27"),
            (.tamiyaLacquer, "LP-68"), (.tamiyaAircraft, "AS-12"),
            (.tamiyaPolycarbonate, "PS-46")
        ]
        for (series, code) in cases {
            let reference = PaintReference(series: series, paintCode: code)
            let target = try #require(reference.previewTarget)
            #expect(reference.previewNote.contains("不复现金属"))
            #expect(reference.previewNote.contains("随角度变化"))
            #expect(MixingPalette.prompt(for: target, referencePaint: reference).contains(reference.previewNote))
        }
        #expect(PaintReference(series: .tamiyaPolycarbonate, paintCode: "PS-46").previewNote.contains("聚碳酸酯"))
    }

    /// 不同目标品牌共用所选 GOLDEN 原料约束，提示词和各层 Schema 应一致。
    @Test(arguments: MixingPaintSet.selectable)
    func testReferencePromptsAndAllSchemasUseOnlyTheSelectedKit(_ paintSet: MixingPaintSet) throws {
        let expectedCodes = Set(paintSet.paints.map(\.code))
        let schema = try #require(JSONSerialization.jsonObject(with: MixingPalette.outputSchema(paintSet: paintSet)) as? [String: Any])
        let properties = try #require(schema["properties"] as? [String: Any])
        var recipeSchemas = [try #require(properties["base"] as? [String: Any])]
        for role in ["shadow", "highlight"] {
            let tone = try #require(properties[role] as? [String: Any])
            let toneProperties = try #require(tone["properties"] as? [String: Any])
            recipeSchemas.append(try #require(toneProperties["recipe"] as? [String: Any]))
        }
        for recipeSchema in recipeSchemas {
            #expect(try allowedCodes(in: recipeSchema) == expectedCodes)
            let fields = try #require(recipeSchema["properties"] as? [String: Any])
            let ingredients = try #require(fields["ingredients"] as? [String: Any])
            #expect(ingredients["minItems"] as? Int == paintSet.paints.count)
            #expect(ingredients["maxItems"] as? Int == paintSet.paints.count)
            let steps = try #require(fields["steps"] as? [String: Any])
            let step = try #require(steps["items"] as? [String: Any])
            let stepFields = try #require(step["properties"] as? [String: Any])
            let code = try #require(stepFields["paintCode"] as? [String: Any])
            #expect(Set(code["enum"] as? [String] ?? []) == expectedCodes)
        }
        let blend = try #require(JSONSerialization.jsonObject(with: ColorBlendRequest.outputSchema(paintSet: paintSet)) as? [String: Any])
        let blendProperties = try #require(blend["properties"] as? [String: Any])
        #expect(NSDictionary(dictionary: try #require(blendProperties["palette"] as? [String: Any])).isEqual(to: schema))
        var prompts = [try blendRequest().prompt(paintSet: paintSet), MixingPalette.prompt(for: .initial, paintSet: paintSet)]
        for reference in references {
            let target = try #require(reference.previewTarget)
            let prompt = MixingPalette.prompt(for: target, referencePaint: reference, paintSet: paintSet)
            #expect(prompt.contains(reference.summary))
            #expect(prompt.contains(reference.previewNote))
            prompts.append(prompt)
        }
        let otherSet: MixingPaintSet = paintSet == .soFlat12 ? .fluid15 : .soFlat12
        for prompt in prompts {
            #expect(prompt.contains("用户选择的调色原料套装：\(paintSet.title)"))
            #expect(prompt.contains("禁止混入另一套 GOLDEN 原料"))
            for paint in paintSet.paints {
                #expect(prompt.contains("\(paint.code):"))
                #expect(prompt.contains(paint.rgbDescription))
                #expect(prompt.contains(paint.series.previewNote))
            }
            for paint in otherSet.paints { #expect(!prompt.contains("\(paint.code):")) }
        }
    }

    /// 外部品牌原料和与参考色不一致的本色目标必须被拒绝。
    @Test
    func testReferenceRecipesRejectForeignPaintsAndMismatchedTargets() throws {
        let reference = PaintReference(series: .mrColor, paintCode: "C13")
        let target = try #require(reference.previewTarget)
        let response = paletteResponse()
        for code in ["C13", "XF-53", "LP-2", "TS-32", "H1", "N1"] {
            var ingredients = response.base.ingredients
            ingredients[0] = PaintDose(paintCode: code, drops: response.base.ingredients[0].drops)
            let foreign = MixingResponse(name: "无效", ingredients: ingredients, steps: response.base.steps, notes: "测试")
            let data = try JSONEncoder().encode(MixingPaletteResponse(base: foreign, shadow: response.shadow, highlight: response.highlight))
            #expect(throws: MixingError.self) {
                try MixingPalette.decode(data, for: target, referencePaint: reference)
            }
        }
        #expect(throws: MixingError.self) {
            try MixingPalette(target: .initial, response: response, referencePaint: reference)
        }
        #expect(throws: MixingError.self) {
            try MixingPalette(
                target: target, response: response,
                referencePaint: PaintReference(series: .mrColor, paintCode: "XF-53")
            )
        }
        let invalidStep = MixingResponse(
            name: "无效", ingredients: response.base.ingredients,
            steps: [MixingStep(paintCode: "C1", drops: 200, instruction: "搅拌")], notes: "测试"
        )
        #expect(throws: MixingError.self) {
            try MixingRecipe(target: target, response: invalidStep, paintSet: .soFlat12, referencePaint: reference)
        }
    }

    /// 各系列参考色都能构造三色方案，并完整保留其商品身份。
    @Test(arguments: MixingPaintSet.selectable)
    func testEveryReferenceProducesThreeGoldenRecipesAndRetainsItsIdentity(_ paintSet: MixingPaintSet) throws {
        for reference in references {
            let target = try #require(reference.previewTarget)
            let palette = try MixingPalette.decode(
                JSONEncoder().encode(paletteResponse(paintSet: paintSet)),
                for: target, paintSet: paintSet, referencePaint: reference
            )
            #expect(palette.base.target == target)
            #expect(palette.recipes.map(\.role) == [.base, .shadow, .highlight])
            for recipe in palette.recipes {
                #expect(recipe.paintSet == paintSet)
                #expect(recipe.paintSetForNewMixing == paintSet)
                #expect(recipe.paintSeries == paintSet.primarySeries)
                #expect(recipe.referencePaint == reference)
                #expect(Set(recipe.response.ingredients.map(\.paintCode)) == Set(paintSet.paints.map(\.code)))
                #expect(recipe.ingredientDrops == (recipe.role == .base ? 200 : (recipe.role == .shadow ? 2 : 6)))
                #expect(recipe.formattedText.contains("调色用漆：\(paintSet.title)"))
                #expect(recipe.formattedText.contains(reference.summary))
                #expect(try JSONDecoder().decode(MixingRecipe.self, from: JSONEncoder().encode(recipe)) == recipe)
            }
            let baseColor = color(for: palette.base)
            #expect(PaintReference.forColor(baseColor) == reference)
            #expect(PaintReference.forColor(color(for: palette.shadow)) == nil)
            #expect(PaintReference.forColor(color(for: palette.highlight)) == nil)
            #expect(PaintSeries.forColor(baseColor) == reference.series)
        }
    }

    /// 参考色项目重新读取后保留来源，历史配方不被自动扩大原料范围。
    @Test
    func testReferenceProjectsReloadAndLegacyRecipesKeepTheirOriginalPaints() throws {
        let suite = "PaintReferenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var library = RecipeLibrary(defaults: defaults)
        let addedID = library.addItem(named: "标准色项目")
        let id = try #require(addedID)
        var expected: [MixingRecipe] = []
        for paintSet in MixingPaintSet.selectable {
            for reference in references {
                let target = try #require(reference.previewTarget)
                let palette = try MixingPalette(
                    target: target, response: paletteResponse(paintSet: paintSet),
                    paintSet: paintSet, referencePaint: reference
                )
                let saved = library.addMixingPalette(palette, to: id)
                #expect(saved)
                expected += palette.recipes
            }
        }
        let restored = RecipeLibrary(defaults: defaults)
        #expect(!restored.isReadOnly)
        #expect(restored.item(id: id)?.colors.compactMap(\.mixingRecipe) == expected)

        // Version 1.0.4 recipes must not be silently relabeled as SoFlat when loading.
        let legacy = try MixingRecipe(
            target: .initial,
            response: MixingResponse(
                name: "旧配方", ingredients: [PaintDose(paintCode: "X-2", drops: 200)],
                steps: [MixingStep(paintCode: "X-2", drops: 200, instruction: "搅匀")], notes: "旧版配方"
            ),
            paintSeries: .tamiyaEnamel
        )
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        object.removeValue(forKey: "referencePaint")
        let decoded = try JSONDecoder().decode(MixingRecipe.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded == legacy)
        #expect(decoded.referencePaint == nil)
        #expect(decoded.formattedText.contains(PaintSeries.tamiyaEnamel.title))
    }

    /// 仅当当前 RGB 仍匹配商品预览时，项目颜色才能重新用作商品参考。
    @Test
    func testCatalogColorCanBeReusedAsReferenceOnlyWhileItsRGBMatches() throws {
        let paint = try #require(PaintSeries.tamiyaAcrylic.paints.first { $0.code == "XF-53" })
        var color = ColorInfo(
            red: paint.red, green: paint.green, blue: paint.blue,
            paintName: paint.name, paintCode: paint.code, paintSeries: paint.series.title
        )
        #expect(PaintReference.forColor(color) == PaintReference(series: .tamiyaAcrylic, paintCode: "XF-53"))
        color.red += 1
        #expect(PaintReference.forColor(color) == nil)

        let reference = PaintReference(series: .tamiyaAcrylic, paintCode: "XF-53")
        let target = try #require(reference.previewTarget)
        let palette = try MixingPalette(target: target, response: paletteResponse(), referencePaint: reference)
        let project = ListItem(text: "编辑参考色")
        var library = RecipeLibrary(previewItems: [project])
        let saved = library.addMixingPalette(palette, to: project.id)
        #expect(saved)
        var edited = try #require(library.item(id: project.id)?.colors.first)
        edited.paintCode = paint.code
        edited.paintSeries = PaintSeries.tamiyaEnamel.title
        let committed = library.commitColorChange(edited, for: .edit(listItemID: project.id, colorID: edited.id))
        #expect(committed)
        #expect(library.color(itemID: project.id, colorID: edited.id)?.mixingRecipe == nil)
    }

    /// 通过假 CLI 核对目标身份被传入，但 Schema 的允许原料始终来自所选套装。
    @Test(arguments: MixingPaintSet.selectable)
    func testCLIUsesReferenceIdentityButAlwaysRequestsTheSelectedKit(_ paintSet: MixingPaintSet) async throws {
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent("SoFlat Reference CLI-\(UUID().uuidString)")
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fake-codex")
        let script = #"""
        #!/bin/sh
        set -eu
        fixture_dir=${0%/*}
        output_path=''
        schema_path=''
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --output-last-message) output_path=$2; shift ;;
                --output-schema) schema_path=$2; shift ;;
            esac
            shift
        done
        cat > "$fixture_dir/prompt.txt"
        cp "$schema_path" "$fixture_dir/schema.json"
        cp "$fixture_dir/fixture.json" "$output_path"
        """#
        try Data(script.utf8).write(to: executable)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let configuration = AIConfiguration(executablePath: executable.path)
        let fixtureURL = directory.appendingPathComponent("fixture.json")
        let fixture = try JSONEncoder().encode(paletteResponse(paintSet: paintSet))
        try fixture.write(to: fixtureURL)
        for reference in [
            PaintReference(series: .tamiyaAcrylic, paintCode: "XF-53"),
            PaintReference(series: .tamiyaSpray, paintCode: "TS-32"),
            PaintReference(series: .mrColor, paintCode: "C13")
        ] {
            let target = try #require(reference.previewTarget)
            let palette = try await CodexMixingService().generate(for: target, referencePaint: reference, paintSet: paintSet, configuration: configuration)
            let prompt = try String(contentsOf: directory.appendingPathComponent("prompt.txt"), encoding: .utf8)
            let schema = try Data(contentsOf: directory.appendingPathComponent("schema.json"))
            #expect(prompt == MixingPalette.prompt(for: target, referencePaint: reference, paintSet: paintSet))
            #expect(try schema == MixingPalette.outputSchema(paintSet: paintSet))
            #expect(palette.recipes.allSatisfy { $0.paintSet == paintSet && $0.referencePaint == reference })
        }
        let plain = try await CodexMixingService().generate(for: .initial, paintSet: paintSet, configuration: configuration)
        #expect(plain.recipes.allSatisfy { $0.paintSet == paintSet && $0.referencePaint == nil })
        try JSONSerialization.data(withJSONObject: [
            "synthesis": [
                "target": ["red": 128, "green": 160, "blue": 128],
                "explanation": "合成后的目标颜色。"
            ],
            "palette": JSONSerialization.jsonObject(with: fixture)
        ]).write(to: fixtureURL)
        let blend = try await CodexMixingService().generate(from: blendRequest(), paintSet: paintSet, configuration: configuration)
        let schema = try Data(contentsOf: directory.appendingPathComponent("schema.json"))
        #expect(try schema == ColorBlendRequest.outputSchema(paintSet: paintSet))
        #expect(blend.recipes.allSatisfy { $0.paintSet == paintSet && $0.referencePaint == nil })
        let blendPrompt = try String(contentsOf: directory.appendingPathComponent("prompt.txt"), encoding: .utf8)
        #expect(try blendPrompt == blendRequest().prompt(paintSet: paintSet))

        // A response made for the other kit must never pass the service's decode boundary.
        let otherSet: MixingPaintSet = paintSet == .soFlat12 ? .fluid15 : .soFlat12
        try JSONEncoder().encode(paletteResponse(paintSet: otherSet)).write(to: fixtureURL)
        await #expect(throws: MixingError.self) {
            try await CodexMixingService().generate(for: .initial, paintSet: paintSet, configuration: configuration)
        }
    }

    /// Fluid 指定目录恰好包含用户要求的 15 色，包含新增群青蓝与永久浅绿。
    @Test
    func testFluidCatalogContainsExactlyTheFifteenRequestedColors() {
        let expected = [
            "2009": "Benzimidazolone Yellow Light", "2008": "Benzimidazolone Yellow Medium",
            "2210": "Naphthol Red Light", "2305": "Quinacridone Magenta",
            "2260": "Phthalo Blue (Red Shade)", "2255": "Phthalo Blue (Green Shade)",
            "2270": "Phthalo Green (Blue Shade)", "2275": "Phthalo Green (Yellow Shade)",
            "2040": "Carbon Black", "2380": "Titanium White",
            "2276": "Pyrrole Orange", "2150": "Dioxazine Purple", "2407": "Yellow Ochre",
            "2400": "Ultramarine Blue", "2250": "Permanent Green Light"
        ]
        #expect(Dictionary(uniqueKeysWithValues: PaintSeries.goldenFluid.paints.map { ($0.code, $0.name) }) == expected)
        #expect(MixingPaintSet.selectable == [.soFlat12, .fluid15])
        #expect(MixingPaintSet.defaultSelection == .soFlat12)
        #expect(MixingPaintSet.soFlat12.paints.count == 12)
        #expect(MixingPaintSet.fluid15.paints.count == 15)
        #expect(Set(MixingPaintSet.soFlat12.paints.map(\.series)) == [.goldenSoFlat])
        #expect(Set(MixingPaintSet.fluid15.paints.map(\.series)) == [.goldenFluid])
        let screenshotColors = [
            "2008": "Benzimidazolone Yellow Medium", "2210": "Naphthol Red Light",
            "2400": "Ultramarine Blue", "2250": "Perm Green Light",
            "2040": "Carbon Black", "2380": "Titanium White"
        ]
        for (code, name) in screenshotColors {
            #expect(PaintSeries.goldenFluid.matchingPaints(name).map(\.code) == [code])
        }
        #expect(PaintSeries.goldenFluid.matchingPaints("群青蓝").first?.code == "2400")
        #expect(PaintSeries.goldenFluid.matchingPaints("永久浅绿").first?.code == "2250")
    }

    /// 每个 Fluid 原料都可用于有效配方，输出名称必须保留其系列。
    @Test
    func testEveryFluidColorIsAcceptedAndNamedWithItsSeries() throws {
        for paint in PaintSeries.goldenFluid.paints {
            let ingredients = MixingPaintSet.fluid15.paints.map {
                PaintDose(paintCode: $0.code, drops: $0.code == paint.code ? 200 : 0)
            }
            let response = MixingResponse(
                name: "Fluid 单色", ingredients: ingredients,
                steps: [MixingStep(paintCode: paint.code, drops: 200, instruction: "取色并充分搅匀。")],
                notes: "测试指定 Fluid 颜色能作为原料。"
            )
            let recipe = try MixingRecipe.decode(JSONEncoder().encode(response), for: .initial, paintSet: .fluid15)
            #expect(recipe.paintSet == .fluid15)
            #expect(recipe.drops(for: paint.code) == 200)
            #expect(recipe.displayedPaints.count == 15)
            #expect(recipe.displayedPaints.contains(paint))
            #expect(!recipe.formattedText.contains("SoFlat"))
            #expect(recipe.formattedText.contains("\(paint.ingredientName) #\(paint.code)：200 滴"))
            #expect(try JSONDecoder().decode(MixingRecipe.self, from: JSONEncoder().encode(recipe)) == recipe)
        }
    }

    /// 各套装统一拒绝缺色号、重复色号、跨套装和无效滴数。
    @Test(arguments: MixingPaintSet.selectable)
    func testKitRecipesRejectMissingDuplicateOtherKitAndInvalidDoses(_ paintSet: MixingPaintSet) throws {
        let valid = paletteResponse(paintSet: paintSet).base
        let last = valid.ingredients.count - 1
        let lastCode = valid.ingredients[last].paintCode
        var duplicate = valid.ingredients
        duplicate[last] = valid.ingredients[0]
        var otherKit = valid.ingredients
        otherKit[last] = PaintDose(paintCode: paintSet == .soFlat12 ? "2380" : "6755", drops: 0)
        var unrequested = valid.ingredients
        unrequested[last] = PaintDose(paintCode: "2005", drops: 0)
        var negative = valid.ingredients
        negative[last] = PaintDose(paintCode: lastCode, drops: -1)
        var wrongTotal = valid.ingredients
        wrongTotal[last] = PaintDose(paintCode: lastCode, drops: 1)
        for ingredients in [Array(valid.ingredients.dropLast()), duplicate, otherKit, unrequested, negative, wrongTotal] {
            let response = MixingResponse(name: valid.name, ingredients: ingredients, steps: valid.steps, notes: valid.notes)
            #expect(throws: MixingError.self) {
                try MixingRecipe.decode(JSONEncoder().encode(response), for: .initial, paintSet: paintSet)
            }
        }
        let otherSet: MixingPaintSet = paintSet == .soFlat12 ? .fluid15 : .soFlat12
        #expect(throws: MixingError.self) {
            try MixingPalette(target: .initial, response: paletteResponse(paintSet: otherSet), paintSet: paintSet)
        }
        let response = paletteResponse(paintSet: paintSet)
        let wrongTone = MixingToneResponse(target: response.shadow.target, recipe: paletteResponse(paintSet: otherSet).shadow.recipe)
        #expect(throws: MixingError.self) {
            try MixingPalette(
                target: .initial,
                response: MixingPaletteResponse(base: response.base, shadow: wrongTone, highlight: response.highlight),
                paintSet: paintSet
            )
        }
    }

    /// Fluid 操作步骤的逐色累计量必须与其自身用量表一致。
    @Test
    func testFluidStepAmountsMustMatchTheirOwnSeriesDoses() {
        let valid = paletteResponse(paintSet: .fluid15).base
        let steps = valid.steps.map {
            let adjustment = $0.paintCode == "2380" ? 1 : -1
            return MixingStep(paintCode: $0.paintCode, drops: $0.drops + adjustment, instruction: $0.instruction)
        }
        let response = MixingResponse(name: valid.name, ingredients: valid.ingredients, steps: steps, notes: valid.notes)
        #expect(throws: MixingError.self) {
            try MixingRecipe.decode(JSONEncoder().encode(response), for: .initial, paintSet: .fluid15)
        }
        let wrongSeries = MixingResponse(
            name: valid.name, ingredients: valid.ingredients,
            steps: [MixingStep(paintCode: "6755", drops: 200, instruction: "搅匀")], notes: valid.notes
        )
        #expect(throws: MixingError.self) {
            try MixingRecipe.decode(JSONEncoder().encode(wrongSeries), for: .initial, paintSet: .fluid15)
        }
    }

    /// 三色层次校验同样检查 Fluid 用量，不能只改 RGB 而照抄本色配方。
    @Test
    func testToneValidationAlsoComparesFluidDoses() throws {
        /// 构造不同白色滴数的 Fluid 配方，用于比较本色与伴随色用量。
        func recipe(white: Int, total: Int = 200) -> MixingResponse {
            let ingredients = MixingPaintSet.fluid15.paints.map {
                PaintDose(paintCode: $0.code, drops: $0.code == "2380" ? white : ($0.code == "2040" ? total - white : 0))
            }
            return MixingResponse(
                name: "Fluid 灰色", ingredients: ingredients,
                steps: ingredients.filter { $0.drops > 0 }.map {
                    MixingStep(paintCode: $0.paintCode, drops: $0.drops, instruction: "充分搅匀。")
                }, notes: "三种深浅分别调制。"
            )
        }
        let shadow = MixingToneResponse(target: MixingTarget(red: 64, green: 80, blue: 64), recipe: recipe(white: 0, total: 2))
        let highlight = MixingToneResponse(target: MixingTarget(red: 220, green: 235, blue: 220), recipe: recipe(white: 6, total: 6))
        let base = recipe(white: 150)
        let palette = try MixingPalette(target: .initial, response: MixingPaletteResponse(base: base, shadow: shadow, highlight: highlight), paintSet: .fluid15)
        #expect(palette.recipes.allSatisfy { $0.drops(for: "6755") == 0 && $0.drops(for: "6745") == 0 })
        #expect(palette.recipes.map { $0.drops(for: "2380") } == [150, 0, 6])
        let repeated = MixingToneResponse(target: shadow.target, recipe: base)
        #expect(throws: MixingError.self) {
            try MixingPalette(target: .initial, response: MixingPaletteResponse(base: base, shadow: repeated, highlight: highlight), paintSet: .fluid15)
        }
    }

    /// 旧 SoFlat 配方始终恢复原来的 12 色集合。
    @Test
    func testLegacySoFlatRecipesKeepTheirOriginalTwelveColors() throws {
        let response = paletteResponse().base
        let original = try MixingRecipe(target: .initial, response: response)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "paintSet")
        let restored = try JSONDecoder().decode(MixingRecipe.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(restored == original)
        #expect(restored.paintSet == nil)
        #expect(restored.paintSetForNewMixing == .soFlat12)
        #expect(restored.displayedPaints.count == 12)
        #expect(!restored.formattedText.contains("Fluid"))
        let newRecipe = try MixingRecipe.decode(JSONEncoder().encode(response), for: .initial)
        #expect(newRecipe.paintSet == .soFlat12)
    }

    /// 旧 Fluid 13 色配方可读，重新发起调色时才映射到当前 15 色套装。
    @Test
    func testLegacyFluidThirteenColorRecipesStillLoadAndUseFifteenColorsForNewMixing() throws {
        // Use the original saved code list, independent of the current catalog.
        let originalCodes = [
            "2009", "2008", "2210", "2305", "2260", "2255", "2270",
            "2275", "2040", "2380", "2276", "2150", "2407"
        ]
        let response = MixingResponse(
            name: "旧版 Fluid 配方",
            ingredients: originalCodes.map {
                PaintDose(paintCode: $0, drops: $0 == "2380" ? 150 : ($0 == "2040" ? 50 : 0))
            },
            steps: [
                MixingStep(paintCode: "2380", drops: 150, instruction: "加入钛白。"),
                MixingStep(paintCode: "2040", drops: 50, instruction: "加入炭黑并搅匀。")
            ],
            notes: "保留旧版原料与用量。"
        )
        let object: [String: Any] = [
            "target": ["red": 128, "green": 160, "blue": 128],
            "response": try JSONSerialization.jsonObject(with: JSONEncoder().encode(response)),
            "paintSeries": "goldenFluid", "paintSet": "fluid13"
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        let restored = try JSONDecoder().decode(MixingRecipe.self, from: data)
        #expect(restored.paintSet == .fluid13)
        #expect(restored.displayedPaints.map(\.code) == originalCodes)
        #expect(restored.response == response)
        #expect(restored.paintSetForNewMixing == .fluid15)
        #expect(!restored.formattedText.contains("#2400"))
        #expect(!restored.formattedText.contains("#2250"))
        #expect(try JSONDecoder().decode(MixingRecipe.self, from: JSONEncoder().encode(restored)) == restored)
        #expect(!MixingPaintSet.selectable.contains(.fluid13))
        #expect(throws: MixingError.self) { try MixingPalette.outputSchema(paintSet: .fluid13) }
        #expect(throws: MixingError.self) {
            try MixingRecipe.decode(JSONEncoder().encode(response), for: .initial, paintSet: .fluid15)
        }

        let suite = "FluidCatalogExpansionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let saved = try JSONSerialization.data(withJSONObject: [[
            "text": "旧版 Fluid 项目",
            "colors": [["red": 128, "green": 160, "blue": 128, "mixingRecipe": object]]
        ]])
        defaults.set(saved, forKey: RecipeLibrary.itemsKey)
        var library = RecipeLibrary(defaults: defaults)
        #expect(!library.isReadOnly)
        #expect(defaults.data(forKey: RecipeLibrary.itemsKey) == saved)
        let project = try #require(library.items.first)
        #expect(project.colors.first?.mixingRecipe == restored)
        let renamed = library.renameItem(id: project.id, to: "继续使用旧配方")
        #expect(renamed)
        #expect(RecipeLibrary(defaults: defaults).items.first?.colors.first?.mixingRecipe == restored)
    }

    /// 旧 25 色组合保留阅读与展示能力，但不能用作新的生成请求。
    @Test
    func testLegacyCombinedRecipesRemainReadableButCannotBeRequested() throws {
        let response = paletteResponse(paintSet: .soFlatAndFluid25).base
        let original = try MixingRecipe(target: .initial, response: response, paintSet: .soFlatAndFluid25)
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(MixingRecipe.self, from: data)
        #expect(restored == original)
        #expect(restored.displayedPaints.count == 25)
        #expect(restored.drops(for: "6755") == 75)
        #expect(restored.drops(for: "2380") == 75)
        #expect(restored.paintSetForNewMixing == .soFlat12)
        #expect(restored.formattedText.contains("GOLDEN SoFlat + Fluid Acrylics"))
        #expect(!MixingPaintSet.selectable.contains(.soFlatAndFluid25))
        for paintSet in MixingPaintSet.selectable + [.soFlatAndFluid25] {
            #expect(throws: MixingError.self) {
                try MixingPalette(target: .initial, response: paletteResponse(paintSet: .soFlatAndFluid25), paintSet: paintSet)
            }
        }
        #expect(throws: MixingError.self) { try MixingPalette.outputSchema(paintSet: .soFlatAndFluid25) }
        #expect(throws: MixingError.self) {
            try MixingRecipe.decode(JSONEncoder().encode(response), for: .initial, paintSet: .soFlatAndFluid25)
        }
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "paintSet")
        #expect(throws: MixingError.self) {
            try JSONDecoder().decode(MixingRecipe.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }


    /// 固定预期值核对 Fluid 屏幕色与已采集的官方调色器数据一致。
    @Test
    func testFluidSwatchesMatchOfficialMixerSRGB() throws {
        // Captured 2026-10-09; added 2400/2250 on 2026-11-11 from mixerPaintData/index.json, paintColor.srgb.
        // Product codes are Fluid 2xxx; the source IDs are the corresponding 1xxx.
        let expected: [String: [Int]] = [
            "2009": [246, 207, 0],
            "2008": [254, 192, 0],
            "2210": [201, 31, 16],
            "2305": [91, 23, 45],
            "2260": [30, 19, 52],
            "2255": [32, 17, 75],
            "2270": [1, 40, 51],
            "2275": [0, 44, 42],
            "2040": [35, 34, 34],
            "2380": [247, 247, 242],
            "2276": [243, 60, 0],
            "2150": [40, 31, 29],
            "2407": [178, 121, 47],
            "2400": [25, 18, 62],
            "2250": [0, 118, 57]
        ]
        #expect(Set(PaintSeries.goldenFluid.paints.map(\.code)) == Set(expected.keys))
        for paint in PaintSeries.goldenFluid.paints {
            let rgb = try #require(expected[paint.code])
            #expect([Int(paint.red), Int(paint.green), Int(paint.blue)] == rgb)
            let reference = PaintReference(series: .goldenFluid, paintCode: paint.code)
            let target = try #require(reference.previewTarget)
            #expect([target.red, target.green, target.blue] == rgb)
            #expect(reference.previewNote.contains("官方调色器的 sRGB"))
            #expect(try JSONDecoder().decode(PaintReference.self, from: JSONEncoder().encode(reference)) == reference)
        }
    }

    /// SoFlat 使用其自身官方色样，不能被 Fluid 的同名色替换。
    @Test
    func testSoFlatSwatchesUseItsOwnOfficialSRGBImages() {
        // Official 6xxx SoFlat brush-outs, ICC sRGB, white-backed 50x40 pixel median.
        // Exclude the black opacity-test stripes visible through translucent paints.
        let expected = [
            "6755": "F4F8F9",
            "6745": "1F241F",
            "6660": "017240",
            "6610": "0126D6",
            "6505": "FFF116",
            "6550": "F02B12",
            "6645": "02A7A8",
            "6510": "FFEB02",
            "6570": "EF4150",
            "6530": "FE660D",
            "6595": "6F3568",
            "6675": "AEE834"
        ]
        #expect(Dictionary(uniqueKeysWithValues: PaintSeries.goldenSoFlat.paints.map { ($0.code, $0.hex) }) == expected)
        #expect(Dictionary(uniqueKeysWithValues: GoldenPaint.all.map { ($0.code, $0.hex) }) == expected)
        #expect(PaintSeries.goldenSoFlat.previewNote.contains("官方色样"))
        #expect(PaintSeries.goldenSoFlat.previewNote.contains("近似"))
        for paint in PaintSeries.goldenSoFlat.paints {
            #expect(PaintSwatchData.swatch(series: paint.series, code: paint.code)?.source == .goldenSoFlatSwatch)
        }
    }

    /// 商品预览快照能跨色库更新保存，同时继续拒绝错误的目标 RGB。
    @Test
    func testReferenceSnapshotSurvivesCatalogChangesWithoutWeakeningTargetValidation() throws {
        // A saved preview may differ from the current catalog; retain it through later saves.
        let data = Data(#"""
        {"series":"goldenFluid","paintCode":"2276",
         "previewTargetSnapshot":{"red":235,"green":80,"blue":38}}
        """#.utf8)
        let reference = try JSONDecoder().decode(PaintReference.self, from: data)
        let originalTarget = MixingTarget(red: 235, green: 80, blue: 38)
        let current = PaintReference(series: .goldenFluid, paintCode: "2276")
        #expect(reference.previewTarget == originalTarget)
        #expect(current.previewTarget == MixingTarget(red: 243, green: 60, blue: 0))
        #expect(reference.previewNote.contains("保存时"))
        #expect(!reference.previewNote.contains("官方调色器的 sRGB"))
        let recipe = try MixingRecipe(
            target: originalTarget, response: paletteResponse().base,
            paintSet: .soFlat12, referencePaint: reference
        )
        #expect(recipe.formattedText.contains(reference.previewNote))
        #expect(try JSONDecoder().decode(MixingRecipe.self, from: JSONEncoder().encode(recipe)) == recipe)
        #expect(throws: MixingError.self) {
            try MixingRecipe(
                target: #require(current.previewTarget), response: paletteResponse().base,
                paintSet: .soFlat12, referencePaint: reference
            )
        }
    }

    /// 没有快照的旧 Fluid 商品引用在所有三色角色中恢复同一个历史参考色。
    @Test(arguments: [MixingPaintSet.soFlat12, .fluid13, .soFlatAndFluid25])
    func testLegacyFluidReferenceProjectsRetainAllThreeTones(_ paintSet: MixingPaintSet) throws {
        let oldRGB: [String: [Int]] = [
            "2009": [244, 229, 43],
            "2008": [235, 197, 45],
            "2210": [218, 53, 37],
            "2305": [167, 22, 88],
            "2260": [21, 40, 100],
            "2255": [12, 64, 106],
            "2270": [7, 80, 71],
            "2275": [36, 93, 55],
            "2040": [32, 32, 32],
            "2380": [243, 244, 240],
            "2276": [236, 81, 39],
            "2150": [48, 32, 62],
            "2407": [179, 138, 59]
        ]
        let suite = "OfficialRGBMigrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = paletteResponse(paintSet: paintSet, independentTones: true)
        let responses: [MixingRole: MixingResponse] = [
            .base: fixture.base, .shadow: fixture.shadow.recipe, .highlight: fixture.highlight.recipe
        ]
        var colors: [[String: Any]] = []
        for (code, rgb) in oldRGB.sorted(by: { $0.key < $1.key }) {
            for role in MixingRole.allCases {
                let targetRGB = role == .base ? rgb : (role == .shadow ? [16, 16, 16] : [240, 240, 240])
                let targetObject = Dictionary(uniqueKeysWithValues: zip(["red", "green", "blue"], targetRGB))
                let response = try #require(responses[role])
                let recipe: [String: Any] = [
                    "target": targetObject,
                    "response": try JSONSerialization.jsonObject(with: JSONEncoder().encode(response)),
                    "role": role.rawValue, "paintSeries": paintSet.primarySeries.rawValue,
                    "paintSet": paintSet.rawValue,
                    // Older versions saved no RGB snapshot in their reference.
                    "referencePaint": ["series": "goldenFluid", "paintCode": code]
                ]
                colors.append([
                    "red": targetRGB[0], "green": targetRGB[1], "blue": targetRGB[2],
                    "name": "\(role.title) · 旧配方", "mixingRecipe": recipe
                ])
            }
        }
        let data = try JSONSerialization.data(withJSONObject: [["text": "旧 Fluid 标准色项目", "colors": colors]])
        defaults.set(data, forKey: RecipeLibrary.itemsKey)
        var library = RecipeLibrary(defaults: defaults)
        #expect(!library.isReadOnly)
        #expect(library.errorMessage == nil)
        #expect(defaults.data(forKey: RecipeLibrary.itemsKey) == data)
        let project = try #require(library.items.first)
        #expect(project.colors.count == 39)
        for color in project.colors {
            let recipe = try #require(color.mixingRecipe)
            let reference = try #require(recipe.referencePaint)
            let rgb = try #require(oldRGB[reference.paintCode])
            let originalReference = MixingTarget(red: Double(rgb[0]), green: Double(rgb[1]), blue: Double(rgb[2]))
            #expect(reference.previewTarget == originalReference)
            #expect(reference.previewNote.contains("保存时"))
            #expect(recipe.response == responses[recipe.role])
            #expect(recipe.paintSet == paintSet)
            #expect(recipe.target == MixingTarget(red: color.red, green: color.green, blue: color.blue))
            #expect(recipe.response.ingredients.reduce(0) { $0 + $1.drops } == 200)
            #expect(color.normalized().mixingRecipe == recipe)
            if recipe.role == .base {
                #expect(recipe.target == originalReference)
                #expect(PaintReference.forColor(color) == reference)
            } else {
                #expect(PaintReference.forColor(color) == nil)
            }
        }
        let renamed = library.renameItem(id: project.id, to: "仍可编辑")
        #expect(renamed)
        let reloaded = RecipeLibrary(defaults: defaults)
        #expect(!reloaded.isReadOnly)
        #expect(reloaded.items == library.items)
        let saved = try #require(defaults.data(forKey: RecipeLibrary.itemsKey))
        let objects = try #require(JSONSerialization.jsonObject(with: saved) as? [[String: Any]])
        let savedColors = try #require(objects.first?["colors"] as? [[String: Any]])
        for savedColor in savedColors {
            let recipe = try #require(savedColor["mixingRecipe"] as? [String: Any])
            let reference = try #require(recipe["referencePaint"] as? [String: Any])
            #expect(reference["previewTargetSnapshot"] != nil)
        }
    }

    /// 无效预览快照和不匹配的历史目标不能利用兼容路径绕过校验。
    @Test
    func testInvalidReferenceSnapshotsAndLegacyTargetMismatchesAreRejected() throws {
        for channel in [-1, 256] {
            for key in ["red", "green", "blue"] {
                var snapshot = ["red": 243, "green": 60, "blue": 0]
                snapshot[key] = channel
                let data = try JSONSerialization.data(withJSONObject: [
                    "series": "goldenFluid", "paintCode": "2276", "previewTargetSnapshot": snapshot
                ])
                #expect(throws: MixingError.self) {
                    try JSONDecoder().decode(PaintReference.self, from: data)
                }
            }
        }
        let unknown = Data(#"""
        {"series":"goldenFluid","paintCode":"6755",
         "previewTargetSnapshot":{"red":243,"green":60,"blue":0}}
        """#.utf8)
        #expect(throws: MixingError.self) { try JSONDecoder().decode(PaintReference.self, from: unknown) }

        let current = PaintReference(series: .goldenFluid, paintCode: "2276")
        let recipe = try MixingRecipe(
            target: #require(current.previewTarget), response: paletteResponse().base,
            paintSet: .soFlat12, referencePaint: current
        )
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(recipe)) as? [String: Any])
        object["referencePaint"] = ["series": "goldenFluid", "paintCode": "2276"]
        // A legacy record must match the known old preview, not an arbitrary saved target.
        #expect(throws: MixingError.self) {
            try JSONDecoder().decode(MixingRecipe.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }

    /// TS 商品色支持色号搜索，保存后仍保留喷罐系列身份。
    @Test
    func testTamiyaSprayCatalogSupportsSearchAndPersistentReferenceIdentity() throws {
        let excludedNumbers = Set([13, 65, 79, 80])
        let expectedCodes = Set((1...102).filter { !excludedNumbers.contains($0) }.map { "TS-\($0)" })
        let series = PaintSeries.tamiyaSpray
        #expect(series.brand == .tamiya)
        #expect(PaintBrand.tamiya.series.contains(series))
        #expect(series.shortTitle == "喷罐漆 · TS")
        #expect(Set(series.paints.map(\.code)) == expectedCodes)
        #expect(series.matchingPaints("ts50").map(\.code) == ["TS-50"])
        #expect(series.matchingPaints("TS-102").first?.name == "Cobalt Green")
        #expect(series.matchingPaints("云母蓝").contains { $0.code == "TS-50" })
        #expect(series.matchingPaints("Haze Grey").first?.code == "TS-32")
        #expect(series.matchingPaints("不存在的色号").isEmpty)
        for paint in series.paints {
            let reference = PaintReference(series: series, paintCode: paint.code)
            try reference.validate()
            #expect(try JSONDecoder().decode(PaintReference.self, from: JSONEncoder().encode(reference)) == reference)
            let color = ColorInfo(
                red: paint.red, green: paint.green, blue: paint.blue,
                paintName: paint.name, paintCode: paint.code, paintSeries: series.title
            )
            #expect(PaintSeries.forColor(color) == series)
            #expect(PaintReference.forColor(color) == reference)
        }
        for number in excludedNumbers {
            let reference = PaintReference(series: series, paintCode: "TS-\(number)")
            #expect(reference.previewTarget == nil)
            #expect(throws: MixingError.self) { try reference.validate() }
        }
        #expect(MixingPaintSet.selectable.allSatisfy { !$0.series.contains(series) })
    }

    /// 特殊效果喷罐只作为颜色参考，界面说明与提示词保留无法复现效果的限制。
    @Test
    func testTamiyaSprayEffectColorsRemainReferencesWithPreviewLimitations() throws {
        for code in ["TS-36", "TS-50", "TS-71", "TS-97"] {
            let reference = PaintReference(series: .tamiyaSpray, paintCode: code)
            let target = try #require(reference.previewTarget)
            #expect(reference.previewNote.contains("非官方实测 RGB"))
            for effect in ["金属", "珠光", "荧光", "透明"] {
                #expect(reference.previewNote.contains(effect))
            }
            for paintSet in MixingPaintSet.selectable {
                let prompt = MixingPalette.prompt(for: target, referencePaint: reference, paintSet: paintSet)
                #expect(prompt.contains(reference.summary))
                #expect(prompt.contains(reference.previewNote))
                #expect(prompt.contains("不复现"))
                #expect(prompt.contains("用户选择的调色原料套装：\(paintSet.title)"))
                let recipe = try MixingRecipe(
                    target: target, response: paletteResponse(paintSet: paintSet).base,
                    paintSeries: paintSet.primarySeries, paintSet: paintSet, referencePaint: reference
                )
                #expect(recipe.formattedText.contains(reference.summary))
                #expect(recipe.formattedText.contains(reference.previewNote))
                #expect(recipe.response.ingredients.allSatisfy { !$0.paintCode.hasPrefix("TS-") })
                #expect(try JSONDecoder().decode(MixingRecipe.self, from: JSONEncoder().encode(recipe)) == recipe)
            }
        }
    }

    /// 带出处的品牌色样覆盖目录，并按具体漆系分别读取。
    @Test
    func testSourcedBrandSwatchesAreCompleteAndKeepTheirSeries() throws {
        let expected: [(PaintSeries, String, String, PaintSwatchSource)] = [
            (.tamiyaEnamel, "XF-53", "6D787C", .encycolorpedia),
            (.tamiyaEnamel, "X-2", "FFFFFF", .tamiyaChart),
            (.tamiyaAcrylic, "XF-53", "71848E", .tamiyaChart),
            (.tamiyaLacquer, "LP-6", "005BAC", .tamiyaChart),
            (.tamiyaSpray, "TS-102", "00A497", .tamiyaChart),
            (.mrColor, "C13", "74858D", .mrHobbyChart),
            (.aqueous, "H53", "546572", .mrHobbyChart),
            (.acrysion, "N22", "546572", .mrHobbyChart)
        ]
        for (series, code, hex, source) in expected {
            let paint = try #require(series.paints.first { $0.code == code })
            #expect(paint.hex == hex)
            #expect(PaintSwatchData.swatch(series: series, code: code)?.source == source)
            let reference = PaintReference(series: series, paintCode: code)
            #expect(reference.previewTarget?.hex == "#" + hex)
            #expect(reference.previewNote.contains(source.note))
            let target = try #require(reference.previewTarget)
            #expect(MixingPalette.prompt(for: target, referencePaint: reference).contains(source.note))
        }
        var sourceCounts: [PaintSwatchSource: Int] = [:]
        for series in PaintSeries.allCases where series != .goldenFluid {
            for paint in series.paints {
                let swatch = try #require(PaintSwatchData.swatch(series: series, code: paint.code))
                sourceCounts[swatch.source, default: 0] += 1
                #expect(paint.hex == swatch.hex)
                #expect(paint.rgbDescription.contains("#" + swatch.hex))
                let reference = PaintReference(series: series, paintCode: paint.code)
                #expect(try JSONDecoder().decode(PaintReference.self, from: JSONEncoder().encode(reference)) == reference)
            }
        }
        #expect(sourceCounts == [.encycolorpedia: 35, .tamiyaChart: 418, .mrHobbyChart: 128, .goldenSoFlatSwatch: 12])
        #expect(PaintSwatchData.swatch(series: .goldenFluid, code: "2380") == nil)
        #expect(PaintSwatchData.swatch(series: .mrColor, code: "H53") == nil)
    }

    /// 更新来源 RGB 后，旧项目各色阶的原目标和用量仍可恢复。
    @Test(arguments: PaintSeries.allCases.filter { $0 != .goldenFluid })
    func testPreSRGBReferenceProjectsKeepOriginalTargetsAndDoses(_ series: PaintSeries) throws {
        let defaults = try #require(UserDefaults(suiteName: "SRGBMigration.\(UUID().uuidString)"))
        defer {
            defaults.removeObject(forKey: RecipeLibrary.itemsKey)
        }
        let fixture = paletteResponse(independentTones: true)
        let responses: [MixingRole: MixingResponse] = [
            .base: fixture.base, .shadow: fixture.shadow.recipe, .highlight: fixture.highlight.recipe
        ]
        var colors: [[String: Any]] = []
        for paint in series.paints {
            let hex = try #require(Int(paint.legacyHex, radix: 16))
            let rgb = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF]
            for role in MixingRole.allCases {
                let targetRGB = role == .base ? rgb : (role == .shadow ? [16, 16, 16] : [240, 240, 240])
                let target = Dictionary(uniqueKeysWithValues: zip(["red", "green", "blue"], targetRGB))
                let recipe: [String: Any] = [
                    "target": target,
                    "response": try JSONSerialization.jsonObject(with: JSONEncoder().encode(#require(responses[role]))),
                    "role": role.rawValue, "paintSeries": PaintSeries.goldenSoFlat.rawValue,
                    "paintSet": MixingPaintSet.soFlat12.rawValue,
                    "referencePaint": ["series": series.rawValue, "paintCode": paint.code]
                ]
                colors.append([
                    "red": targetRGB[0], "green": targetRGB[1], "blue": targetRGB[2],
                    "name": "旧颜色", "mixingRecipe": recipe
                ])
            }
        }
        let data = try JSONSerialization.data(withJSONObject: [["text": "旧标准色项目", "colors": colors]])
        defaults.set(data, forKey: RecipeLibrary.itemsKey)
        var library = RecipeLibrary(defaults: defaults)
        #expect(!library.isReadOnly)
        #expect(library.errorMessage == nil)
        #expect(defaults.data(forKey: RecipeLibrary.itemsKey) == data)
        let project = try #require(library.items.first)
        #expect(project.colors.count == series.paints.count * 3)
        for color in project.colors {
            let recipe = try #require(color.mixingRecipe)
            let reference = try #require(recipe.referencePaint)
            let paint = try #require(reference.paint)
            #expect(reference.previewTarget?.hex == "#" + paint.legacyHex)
            #expect(recipe.response == responses[recipe.role])
            #expect(recipe.target == MixingTarget(red: color.red, green: color.green, blue: color.blue))
            #expect(color.normalized().mixingRecipe == recipe)
            if recipe.role == .base {
                #expect(PaintReference.forColor(color) == reference)
                let current = PaintReference(series: series, paintCode: paint.code)
                #expect(current.previewTarget?.hex == "#" + paint.hex)
                if paint.hex != paint.legacyHex {
                    #expect(reference.previewNote.contains("保存时"))
                    #expect(throws: MixingError.self) { try reference.validate(target: #require(current.previewTarget)) }
                }
            }
        }
        let renamed = library.renameItem(id: project.id, to: "保留旧配方")
        #expect(renamed)
        let restored = RecipeLibrary(defaults: defaults)
        #expect(!restored.isReadOnly)
        #expect(restored.items == library.items)
        for color in try #require(restored.items.first).colors {
            let reference = try #require(color.mixingRecipe?.referencePaint)
            let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(reference)) as? [String: Any])
            #expect(object["previewTargetSnapshot"] != nil)
        }
    }

    // MARK: - 跨系列样本与固定响应
    /// 覆盖各品牌系列及新增 Fluid 颜色的代表性商品引用。
    private var references: [PaintReference] {
        [
            PaintReference(series: .goldenSoFlat, paintCode: "6610"),
            PaintReference(series: .goldenFluid, paintCode: "2276"),
            PaintReference(series: .goldenFluid, paintCode: "2400"),
            PaintReference(series: .goldenFluid, paintCode: "2250"),
            PaintReference(series: .tamiyaAcrylic, paintCode: "XF-53"),
            PaintReference(series: .tamiyaEnamel, paintCode: "XF-53"),
            PaintReference(series: .tamiyaLacquer, paintCode: "LP-34"),
            PaintReference(series: .tamiyaSpray, paintCode: "TS-32"),
            PaintReference(series: .mrColor, paintCode: "C13"),
            PaintReference(series: .aqueous, paintCode: "H53"),
            PaintReference(series: .acrysion, paintCode: "N22")
        ]
    }

    /// 提取单份配方 Schema 的色号枚举，直接核对 AI 可使用的原料集合。
    private func allowedCodes(in schema: [String: Any]) throws -> Set<String> {
        let properties = try #require(schema["properties"] as? [String: Any])
        let ingredients = try #require(properties["ingredients"] as? [String: Any])
        let item = try #require(ingredients["items"] as? [String: Any])
        let itemProperties = try #require(item["properties"] as? [String: Any])
        return Set(try #require(itemProperties["paintCode"] as? [String: Any])["enum"] as? [String] ?? [])
    }

    /// 将一份配方包装成可持久化的项目颜色，复用其目标通道。
    private func color(for recipe: MixingRecipe) -> ColorInfo {
        ColorInfo(
            red: Double(recipe.target.red), green: Double(recipe.target.green), blue: Double(recipe.target.blue),
            mixingRecipe: recipe
        )
    }

    /// 构造满足不同套装计量规则的三色响应，兼容旧组合套装的测试需要。
    private func paletteResponse(paintSet: MixingPaintSet = .soFlat12, independentTones: Bool = false) -> MixingPaletteResponse {
        /// 按指定白色总量分配原料，步骤同步采用实际非零用量。
        func recipe(white: Int, total: Int = 200) -> MixingResponse {
            let ingredients = paintSet.paints.map {
                let drops: Int
                if paintSet == .soFlatAndFluid25 {
                    switch $0.code {
                    case "6755": drops = white / 2
                    case "2380": drops = white - white / 2
                    case "2040": drops = total - white
                    default: drops = 0
                    }
                } else {
                    let whiteCode = paintSet.primarySeries == .goldenFluid ? "2380" : "6755"
                    let blackCode = paintSet.primarySeries == .goldenFluid ? "2040" : "6745"
                    drops = $0.code == whiteCode ? white : ($0.code == blackCode ? total - white : 0)
                }
                return PaintDose(paintCode: $0.code, drops: drops)
            }
            return MixingResponse(
                name: "测试色", ingredients: ingredients,
                steps: ingredients.filter { $0.drops > 0 }.map {
                    MixingStep(paintCode: $0.paintCode, drops: $0.drops, instruction: "充分搅匀。")
                }, notes: "先少量试调。"
            )
        }
        return MixingPaletteResponse(
            base: recipe(white: 150),
            // 使用边界目标确保深蓝与浅灰参考均有足够层次，避免来源测试被明度阈值干扰。
            // Deep ultramarine and light-gray references need boundary targets for sufficient contrast.
            shadow: MixingToneResponse(target: MixingTarget(red: 0, green: 0, blue: 0), recipe: recipe(white: independentTones ? 80 : 0, total: independentTones ? 200 : 2)),
            highlight: MixingToneResponse(target: MixingTarget(red: 255, green: 255, blue: 255), recipe: recipe(white: independentTones ? 190 : 6, total: independentTones ? 200 : 6))
        )
    }

    /// 创建占比合计不为 100 的简单输入，以核对合色路径的 Schema。
    private func blendRequest() throws -> ColorBlendRequest {
        try ColorBlendRequest(sources: [
            ColorBlendSource(target: MixingTarget(red: 255, green: 0, blue: 0), percentage: 40),
            ColorBlendSource(target: MixingTarget(red: 0, green: 0, blue: 255), percentage: 20)
        ])
    }
}
