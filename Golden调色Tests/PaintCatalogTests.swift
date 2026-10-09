import Foundation
import Testing
@testable import Golden调色

struct PaintCatalogTests {
    @Test
    func testCatalogsKeepSeriesIdentityAndExcludeNonPaintProducts() throws {
        let expectedCounts: [PaintSeries: Int] = [
            .goldenSoFlat: 12, .goldenFluid: 13, .tamiyaAcrylic: 42, .tamiyaEnamel: 42,
            .tamiyaLacquer: 32, .tamiyaSpray: 98, .mrColor: 50, .aqueous: 38, .acrysion: 40
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
        let otherSet: MixingPaintSet = paintSet == .soFlat12 ? .fluid13 : .soFlat12
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
                #expect(recipe.response.ingredients.reduce(0) { $0 + $1.drops } == 200)
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
        let otherSet: MixingPaintSet = paintSet == .soFlat12 ? .fluid13 : .soFlat12
        try JSONEncoder().encode(paletteResponse(paintSet: otherSet)).write(to: fixtureURL)
        await #expect(throws: MixingError.self) {
            try await CodexMixingService().generate(for: .initial, paintSet: paintSet, configuration: configuration)
        }
    }

    @Test
    func testFluidCatalogContainsExactlyTheThirteenRequestedColors() {
        let expected = [
            "2009": "Benzimidazolone Yellow Light", "2008": "Benzimidazolone Yellow Medium",
            "2210": "Naphthol Red Light", "2305": "Quinacridone Magenta",
            "2260": "Phthalo Blue (Red Shade)", "2255": "Phthalo Blue (Green Shade)",
            "2270": "Phthalo Green (Blue Shade)", "2275": "Phthalo Green (Yellow Shade)",
            "2040": "Carbon Black", "2380": "Titanium White",
            "2276": "Pyrrole Orange", "2150": "Dioxazine Purple", "2407": "Yellow Ochre"
        ]
        #expect(Dictionary(uniqueKeysWithValues: PaintSeries.goldenFluid.paints.map { ($0.code, $0.name) }) == expected)
        #expect(MixingPaintSet.selectable == [.soFlat12, .fluid13])
        #expect(MixingPaintSet.defaultSelection == .soFlat12)
        #expect(MixingPaintSet.soFlat12.paints.count == 12)
        #expect(MixingPaintSet.fluid13.paints.count == 13)
        #expect(Set(MixingPaintSet.soFlat12.paints.map(\.series)) == [.goldenSoFlat])
        #expect(Set(MixingPaintSet.fluid13.paints.map(\.series)) == [.goldenFluid])
    }

    @Test
    func testEveryFluidColorIsAcceptedAndNamedWithItsSeries() throws {
        for paint in PaintSeries.goldenFluid.paints {
            let ingredients = MixingPaintSet.fluid13.paints.map {
                PaintDose(paintCode: $0.code, drops: $0.code == paint.code ? 200 : 0)
            }
            let response = MixingResponse(
                name: "Fluid 单色", ingredients: ingredients,
                steps: [MixingStep(paintCode: paint.code, drops: 200, instruction: "取色并充分搅匀。")],
                notes: "测试指定 Fluid 颜色能作为原料。"
            )
            let recipe = try MixingRecipe.decode(JSONEncoder().encode(response), for: .initial, paintSet: .fluid13)
            #expect(recipe.paintSet == .fluid13)
            #expect(recipe.drops(for: paint.code) == 200)
            #expect(recipe.displayedPaints.count == 13)
            #expect(recipe.displayedPaints.contains(paint))
            #expect(!recipe.formattedText.contains("SoFlat"))
            #expect(recipe.formattedText.contains("\(paint.ingredientName) #\(paint.code)：200 滴"))
            #expect(try JSONDecoder().decode(MixingRecipe.self, from: JSONEncoder().encode(recipe)) == recipe)
        }
    }

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
        unrequested[last] = PaintDose(paintCode: "2400", drops: 0)
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
        let otherSet: MixingPaintSet = paintSet == .soFlat12 ? .fluid13 : .soFlat12
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

    @Test
    func testFluidStepAmountsMustMatchTheirOwnSeriesDoses() {
        let valid = paletteResponse(paintSet: .fluid13).base
        let steps = valid.steps.map {
            let adjustment = $0.paintCode == "2380" ? 1 : -1
            return MixingStep(paintCode: $0.paintCode, drops: $0.drops + adjustment, instruction: $0.instruction)
        }
        let response = MixingResponse(name: valid.name, ingredients: valid.ingredients, steps: steps, notes: valid.notes)
        #expect(throws: MixingError.self) {
            try MixingRecipe.decode(JSONEncoder().encode(response), for: .initial, paintSet: .fluid13)
        }
        let wrongSeries = MixingResponse(
            name: valid.name, ingredients: valid.ingredients,
            steps: [MixingStep(paintCode: "6755", drops: 200, instruction: "搅匀")], notes: valid.notes
        )
        #expect(throws: MixingError.self) {
            try MixingRecipe.decode(JSONEncoder().encode(wrongSeries), for: .initial, paintSet: .fluid13)
        }
    }

    @Test
    func testToneValidationAlsoComparesFluidDoses() throws {
        func recipe(white: Int) -> MixingResponse {
            let ingredients = MixingPaintSet.fluid13.paints.map {
                PaintDose(paintCode: $0.code, drops: $0.code == "2380" ? white : ($0.code == "2040" ? 200 - white : 0))
            }
            return MixingResponse(
                name: "Fluid 灰色", ingredients: ingredients,
                steps: ingredients.filter { $0.drops > 0 }.map {
                    MixingStep(paintCode: $0.paintCode, drops: $0.drops, instruction: "充分搅匀。")
                }, notes: "三种深浅分别调制。"
            )
        }
        let shadow = MixingToneResponse(target: MixingTarget(red: 64, green: 80, blue: 64), recipe: recipe(white: 80))
        let highlight = MixingToneResponse(target: MixingTarget(red: 220, green: 235, blue: 220), recipe: recipe(white: 190))
        let base = recipe(white: 150)
        let palette = try MixingPalette(target: .initial, response: MixingPaletteResponse(base: base, shadow: shadow, highlight: highlight), paintSet: .fluid13)
        #expect(palette.recipes.allSatisfy { $0.drops(for: "6755") == 0 && $0.drops(for: "6745") == 0 })
        #expect(palette.recipes.map { $0.drops(for: "2380") } == [150, 80, 190])
        let repeated = MixingToneResponse(target: shadow.target, recipe: base)
        #expect(throws: MixingError.self) {
            try MixingPalette(target: .initial, response: MixingPaletteResponse(base: base, shadow: repeated, highlight: highlight), paintSet: .fluid13)
        }
    }

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


    @Test
    func testFluidSwatchesMatchOfficialMixerSRGB() throws {
        // Captured 2026-10-09 from mixerPaintData/index.json, paintColor.srgb.
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
            "2407": [178, 121, 47]
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

    @Test
    func testSoFlatKeepsItsOwnApproximateSwatches() {
        let expected = [
            "6755": "F3F5F2", "6745": "222721", "6660": "007A48", "6610": "0736C8",
            "6505": "F5EA32", "6550": "DA321E", "6645": "00AAA8", "6510": "F4DF16",
            "6570": "D9485A", "6530": "F47719", "6595": "643761", "6675": "AAD62C"
        ]
        #expect(Dictionary(uniqueKeysWithValues: PaintSeries.goldenSoFlat.paints.map { ($0.code, $0.hex) }) == expected)
        #expect(PaintSeries.goldenSoFlat.previewNote.contains("未提供 SoFlat 专用 RGB"))
        #expect(PaintSeries.goldenSoFlat.previewNote.contains("近似"))
    }

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
        let fixture = paletteResponse(paintSet: paintSet)
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

    private var references: [PaintReference] {
        [
            PaintReference(series: .goldenSoFlat, paintCode: "6610"),
            PaintReference(series: .goldenFluid, paintCode: "2276"),
            PaintReference(series: .tamiyaAcrylic, paintCode: "XF-53"),
            PaintReference(series: .tamiyaEnamel, paintCode: "XF-53"),
            PaintReference(series: .tamiyaLacquer, paintCode: "LP-34"),
            PaintReference(series: .tamiyaSpray, paintCode: "TS-32"),
            PaintReference(series: .mrColor, paintCode: "C13"),
            PaintReference(series: .aqueous, paintCode: "H53"),
            PaintReference(series: .acrysion, paintCode: "N22")
        ]
    }

    private func allowedCodes(in schema: [String: Any]) throws -> Set<String> {
        let properties = try #require(schema["properties"] as? [String: Any])
        let ingredients = try #require(properties["ingredients"] as? [String: Any])
        let item = try #require(ingredients["items"] as? [String: Any])
        let itemProperties = try #require(item["properties"] as? [String: Any])
        return Set(try #require(itemProperties["paintCode"] as? [String: Any])["enum"] as? [String] ?? [])
    }

    private func color(for recipe: MixingRecipe) -> ColorInfo {
        ColorInfo(
            red: Double(recipe.target.red), green: Double(recipe.target.green), blue: Double(recipe.target.blue),
            mixingRecipe: recipe
        )
    }

    private func paletteResponse(paintSet: MixingPaintSet = .soFlat12) -> MixingPaletteResponse {
        func recipe(white: Int) -> MixingResponse {
            let ingredients = paintSet.paints.map {
                let drops: Int
                if paintSet == .soFlatAndFluid25 {
                    switch $0.code {
                    case "6755": drops = white / 2
                    case "2380": drops = white - white / 2
                    case "2040": drops = 200 - white
                    default: drops = 0
                    }
                } else {
                    let whiteCode = paintSet == .fluid13 ? "2380" : "6755"
                    let blackCode = paintSet == .fluid13 ? "2040" : "6745"
                    drops = $0.code == whiteCode ? white : ($0.code == blackCode ? 200 - white : 0)
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
            shadow: MixingToneResponse(target: MixingTarget(red: 16, green: 16, blue: 16), recipe: recipe(white: 80)),
            highlight: MixingToneResponse(target: MixingTarget(red: 240, green: 240, blue: 240), recipe: recipe(white: 190))
        )
    }

    private func blendRequest() throws -> ColorBlendRequest {
        try ColorBlendRequest(sources: [
            ColorBlendSource(target: MixingTarget(red: 255, green: 0, blue: 0), percentage: 40),
            ColorBlendSource(target: MixingTarget(red: 0, green: 0, blue: 255), percentage: 20)
        ])
    }
}
