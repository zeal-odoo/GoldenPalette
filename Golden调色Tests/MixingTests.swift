import Foundation
import Testing
import Darwin
@testable import Golden调色

struct MixingTests {
    @Test
    func testMaxReasoningHasTimeToFinishWithoutChangingItsEffort() throws {
        for effort in [AIReasoningEffort.max, .ultra] {
            let configuration = try AIConfiguration(model: AIModelSelection(reasoningEffort: effort)).validated()
            #expect(configuration.model.reasoningEffort == effort)
            #expect(configuration.model.reasoningEffort.generationTimeout == 1_200)
            #expect(configuration.model.reasoningEffort.generationWaitDescription.contains("20 分钟"))
        }
        #expect(AIReasoningEffort.xhigh.generationTimeout == 600)
        #expect(AIReasoningEffort.high.generationTimeout == 240)
    }

    @Test
    func testTimeoutMessageReportsTheActualWaitingLimit() {
        let error = MixingError.timedOut(after: AIReasoningEffort.max.generationTimeout)
        #expect(error.localizedDescription.contains("20 分钟"))
        #expect(!error.localizedDescription.contains("4 分钟"))
    }

    @Test
    func testOriginalSoFlatPaletteRetainsTheTwelveRequestedPaints() {
        #expect(GoldenPaint.all.map(\.code) == [
            "6755", "6745", "6660", "6610", "6505", "6550",
            "6645", "6510", "6570", "6530", "6595", "6675"
        ])
    }

    @Test
    func testRGBEntryRejectsInvalidOrIncompleteChannels() {
        #expect(MixingTarget(redText: "0", greenText: " 255 ", blueText: "128")?.green == 255)
        for value in ["", "256", "-1", "12.5", "NaN", "1e2", "999999999999999999999999"] {
            #expect(MixingTarget(redText: value, greenText: "128", blueText: "128") == nil)
        }
    }

    @Test
    func testValidRecipeCanSplitAPaintAcrossSteps() throws {
        let steps = [
            MixingStep(paintCode: "6755", drops: 100, instruction: "取白色作为基底。"),
            MixingStep(paintCode: "6745", drops: 1, instruction: "充分搅匀。"),
            MixingStep(paintCode: "6755", drops: 99, instruction: "加入剩余白色并搅匀。")
        ]
        let recipe = try MixingRecipe(target: .initial, response: response(steps: steps))
        let data = try JSONEncoder().encode(recipe)
        #expect(try JSONDecoder().decode(MixingRecipe.self, from: data) == recipe)
        #expect(recipe.formattedText.contains("200 滴"))
        #expect(recipe.formattedText.contains("群青 · Ultramarine Blue #6610：0 滴"))
        #expect(recipe.formattedText.contains("RGB 128, 160, 128"))
    }

    @Test
    func testWrongTotalIsRejectedInsteadOfSilentlyRescaled() {
        for drops in [198, 200] {
            let ingredients = doses(white: drops)
            #expect(throws: MixingError.self) {
                try MixingRecipe(target: .initial, response: response(ingredients: ingredients))
            }
        }
    }

    @Test
    func testMissingDuplicateUnknownAndNegativePaintDosesAreRejected() {
        var duplicate = doses()
        duplicate[2] = PaintDose(paintCode: "6755", drops: 0)
        var unknown = doses()
        unknown[2] = PaintDose(paintCode: "9999", drops: 0)
        var negative = doses()
        negative[2] = PaintDose(paintCode: "6660", drops: -1)
        for ingredients in [Array(doses().dropLast()), duplicate, unknown, negative] {
            #expect(throws: MixingError.self) {
                try MixingRecipe(target: .initial, response: response(ingredients: ingredients))
            }
        }
    }

    @Test
    func testStepDosesMustMatchEveryPaintInTheTable() {
        let mismatched = [
            MixingStep(paintCode: "6755", drops: 198, instruction: "搅匀。"),
            MixingStep(paintCode: "6745", drops: 2, instruction: "搅匀。")
        ]
        #expect(throws: MixingError.self) {
            try MixingRecipe(target: .initial, response: response(steps: mismatched))
        }
        #expect(throws: MixingError.self) {
            try MixingRecipe(target: .initial, response: response(steps: []))
        }
    }

    @Test
    func testFractionalDropsAndMalformedAIOutputAreRejected() throws {
        let encoded = try JSONEncoder().encode(response())
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var ingredients = try #require(object["ingredients"] as? [[String: Any]])
        ingredients[0]["drops"] = 199.5
        object["ingredients"] = ingredients
        let fractional = try JSONSerialization.data(withJSONObject: object)
        for data in [fractional, Data("not a recipe".utf8), Data(repeating: 32, count: 128_001)] {
            #expect(throws: MixingError.self) {
                try MixingRecipe.decode(data, for: .initial)
            }
        }
    }

    @Test
    func testCLIInvocationPinsRequestedModelAndReadOnlyExecution() {
        let directory = URL(fileURLWithPath: "/tmp/path with spaces")
        let arguments = CodexMixingService.arguments(
            schema: directory.appendingPathComponent("schema.json"),
            output: directory.appendingPathComponent("recipe.json"),
            directory: directory
        )
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        #expect(value(after: "--model") == "gpt-6.1-sol")
        #expect(arguments.contains("model_reasoning_effort=\"high\""))
        #expect(value(after: "--sandbox") == "read-only")
        #expect(arguments.contains("--ignore-user-config"))
        #expect(arguments.contains("--ephemeral"))
        #expect(value(after: "--cd") == directory.path)
        #expect(value(after: "--output-schema") == "/tmp/path with spaces/schema.json")
        #expect(arguments.last == "-")
    }

    @Test
    func testGUIEnvironmentCanFindHomebrewAndCustomNodeInstallations() {
        let customCLI = URL(fileURLWithPath: "/Users/example/.nvm/versions/node/v24/bin/codex")
        let environment = CodexMixingService.environment(
            for: customCLI, base: ["PATH": "/usr/bin:/bin", "CODEX_HOME": "/Users/example/.codex"]
        )
        let paths = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        #expect(paths.first == customCLI.deletingLastPathComponent().path)
        #expect(paths.contains("/opt/homebrew/bin"))
        #expect(paths.contains("/usr/local/bin"))
        #expect(environment["CODEX_HOME"] == "/Users/example/.codex")
    }

    @Test
    func testAIRecipeSavesAndReloadsWithAllDosesAndSteps() throws {
        try withDefaults { defaults in
            var library = RecipeLibrary(defaults: defaults)
            let palette = try MixingPalette(target: .initial, response: paletteResponse())
            let recipe = palette.base
            let savedID = library.addItem(named: "我的项目")
            let id = try #require(savedID)
            let didApplyChange1 = library.addMixingPalette(palette, to: id)
            #expect(didApplyChange1)
            let reloaded = RecipeLibrary(defaults: defaults)
            let color = try #require(reloaded.item(id: id)?.colors.first)
            #expect(color.mixingRecipe == recipe)
            #expect(color.red == 128)
            #expect(color.green == 160)
            #expect(color.method == recipe.response.notes)
        }
    }

    @Test
    func testEditingTargetDoesNotKeepAnUnrelatedAIRecipe() throws {
        let palette = try MixingPalette(target: .initial, response: paletteResponse())
        let recipe = palette.base
        var library = RecipeLibrary(previewItems: [])
        let savedID = library.addItem(named: "我的项目")
        let itemID = try #require(savedID)
        let didApplyChange2 = library.addMixingPalette(palette, to: itemID)
        #expect(didApplyChange2)
        var color = try #require(library.item(id: itemID)?.colors.first)
        color.name = "改名"
        let renamed = library.commitColorChange(color, for: .edit(listItemID: itemID, colorID: color.id))
        #expect(renamed)
        #expect(library.color(itemID: itemID, colorID: color.id)?.mixingRecipe == recipe)
        color.red = 50
        let edited = library.commitColorChange(color, for: .edit(listItemID: itemID, colorID: color.id))
        #expect(edited)
        #expect(library.color(itemID: itemID, colorID: color.id)?.mixingRecipe == nil)
    }

    @Test
    func testOldSandboxRecipesAreCopiedWithoutRemovingTheOriginal() throws {
        try withDefaults { defaults in
            let data = try JSONEncoder().encode([ListItem(text: "旧容器中的配方")])
            try withLegacyPreferences(value: data) { url in
                let original = try Data(contentsOf: url)
                let library = RecipeLibrary(defaults: defaults, legacyPreferencesURL: url)
                #expect(library.items.first?.text == "旧容器中的配方")
                #expect(defaults.data(forKey: RecipeLibrary.itemsKey) == data)
                #expect(try Data(contentsOf: url) == original)
            }
        }
    }

    @Test
    func testCurrentRecipesTakePriorityOverLegacyContainer() throws {
        try withDefaults { defaults in
            let current = try JSONEncoder().encode([ListItem(text: "当前配方")])
            defaults.set(current, forKey: RecipeLibrary.itemsKey)
            try withLegacyPreferences(value: Data("broken".utf8)) { url in
                let library = RecipeLibrary(defaults: defaults, legacyPreferencesURL: url)
                #expect(library.items.first?.text == "当前配方")
                #expect(!library.isReadOnly)
                #expect(defaults.data(forKey: RecipeLibrary.itemsKey) == current)
            }
        }
    }

    @Test
    func testCorruptLegacyRecipesAreNeverOverwritten() throws {
        try withDefaults { defaults in
            try withLegacyPreferences(value: Data("broken".utf8)) { url in
                var library = RecipeLibrary(defaults: defaults, legacyPreferencesURL: url)
                #expect(library.isReadOnly)
                let palette = try MixingPalette(target: .initial, response: paletteResponse())
                let didApplyChange3 = library.addMixingPalette(palette, to: UUID())
                #expect(!didApplyChange3)
                #expect(defaults.object(forKey: RecipeLibrary.itemsKey) == nil)
            }
        }
    }

    @Test
    func testTimedOutProcessIsTerminatedAndReaped() async throws {
        try await withProcessFiles { directory, input, log, logURL in
            do {
                _ = try await CodexProcessRunner().run(
                    executable: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", "echo $$; exec /bin/sleep 30"],
                    directory: directory, input: input, log: log, logURL: logURL, timeout: 0.3
                )
                Issue.record("Expected a timeout.")
            } catch MixingError.timedOut(let timeout) {
                #expect(timeout == 0.3)
                try expectProcessExited(logURL: logURL)
            }
        }
    }

    @Test
    func testCancellingARequestStopsItsProcess() async throws {
        try await withProcessFiles { directory, input, log, logURL in
            let task = Task {
                try await CodexProcessRunner().run(
                    executable: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", "echo $$; exec /bin/sleep 30"],
                    directory: directory, input: input, log: log, logURL: logURL
                )
            }
            try await Task.sleep(nanoseconds: 300_000_000)
            task.cancel()
            do {
                _ = try await task.value
                Issue.record("Expected cancellation.")
            } catch is CancellationError {
                try expectProcessExited(logURL: logURL)
            }
        }
    }

    @Test
    func testThreeToneResponseKeepsTheInputBaseAndValidatesEachRecipe() throws {
        let data = try JSONEncoder().encode(paletteResponse())
        let palette = try MixingPalette.decode(data, for: .initial)
        #expect(palette.base.target == .initial)
        #expect(palette.recipes.map(\.role) == [.base, .shadow, .highlight])
        #expect(palette.shadow.target.relativeLuminance < palette.base.target.relativeLuminance)
        #expect(palette.highlight.target.relativeLuminance > palette.base.target.relativeLuminance)
        for recipe in palette.recipes {
            #expect(recipe.response.ingredients.count == 12)
            #expect(recipe.response.ingredients.reduce(0) { $0 + $1.drops } == 200)
        }
        #expect(palette.formattedText.contains("三份共 600 滴"))
        for role in MixingRole.allCases {
            #expect(palette.formattedText.contains("\(role.title) ·"))
        }
    }

    @Test
    func testMissingToneCannotBeMistakenForACompletePalette() throws {
        let data = try JSONEncoder().encode(paletteResponse())
        let original = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["base", "shadow", "highlight"] {
            var object = original
            object.removeValue(forKey: key)
            let incomplete = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: MixingError.self) {
                try MixingPalette.decode(incomplete, for: .initial)
            }
        }
    }

    @Test
    func testEveryToneMustHaveItsOwnTwoHundredDrops() {
        let valid = paletteResponse()
        let bad = response(ingredients: doses(white: 198))
        let badShadow = MixingToneResponse(target: valid.shadow.target, recipe: bad)
        let badHighlight = MixingToneResponse(target: valid.highlight.target, recipe: bad)
        let responses = [
            MixingPaletteResponse(base: bad, shadow: valid.shadow, highlight: valid.highlight),
            MixingPaletteResponse(base: valid.base, shadow: badShadow, highlight: valid.highlight),
            MixingPaletteResponse(base: valid.base, shadow: valid.shadow, highlight: badHighlight)
        ]
        for response in responses {
            #expect(throws: MixingError.self) {
                try MixingPalette(target: .initial, response: response)
            }
        }
    }

    @Test
    func testReversedOrIdenticalToneBrightnessIsRejected() {
        let base = MixingTarget.initial
        let tooLight = MixingTarget(red: 240, green: 240, blue: 240)
        let tooDark = MixingTarget(red: 20, green: 20, blue: 20)
        for shadow in [base, tooLight] {
            #expect(throws: MixingError.self) {
                try MixingPalette(target: base, response: paletteResponse(shadow: shadow))
            }
        }
        for highlight in [base, tooDark] {
            #expect(throws: MixingError.self) {
                try MixingPalette(target: base, response: paletteResponse(highlight: highlight))
            }
        }
    }

    @Test
    func testPreviewLightnessHandlesDarkAndMidtoneSwatches() {
        let samples: [(Int, Double)] = [(0, 0), (10, 2.741748), (25, 8.757011), (128, 53.585013), (255, 100)]
        for (channel, expected) in samples {
            let value = Double(channel)
            let target = MixingTarget(red: value, green: value, blue: value)
            #expect(abs(target.perceptualLightness - expected) < 0.0001)
        }
        let green = MixingTarget(red: 0, green: 255, blue: 0)
        let blue = MixingTarget(red: 0, green: 0, blue: 255)
        #expect(green.perceptualLightness > blue.perceptualLightness)
    }

    @Test
    func testSubtleShadowsAndHighlightsAreRejectedDespiteDistinctDoses() throws {
        for difference in [1.0, 15.0, 30.0] {
            let shadow = MixingTarget(red: 128 - difference, green: 160 - difference, blue: 128 - difference)
            let highlight = MixingTarget(red: 128 + difference, green: 160 + difference, blue: 128 + difference)
            for response in [paletteResponse(shadow: shadow), paletteResponse(highlight: highlight)] {
                let data = try JSONEncoder().encode(response)
                #expect(throws: MixingError.self) {
                    try MixingPalette.decode(data, for: .initial)
                }
            }
        }
    }

    @Test
    func testModerateContrastPassesAtTheMinimumLightnessDifference() throws {
        let base = MixingTarget(red: 128, green: 128, blue: 128)
        let shadow = MixingTarget(red: 90, green: 90, blue: 90)
        let highlight = MixingTarget(red: 168, green: 168, blue: 168)
        let palette = try MixingPalette(target: base, response: paletteResponse(shadow: shadow, highlight: highlight))
        #expect(palette.base.target == base)
        #expect(palette.shadow.target == shadow)
        #expect(palette.highlight.target == highlight)
        // These adjacent RGB values fall just below the 15-point minimum.
        let subtleShadow = MixingTarget(red: 91, green: 91, blue: 91)
        let subtleHighlight = MixingTarget(red: 167, green: 167, blue: 167)
        for response in [
            paletteResponse(shadow: subtleShadow, highlight: highlight),
            paletteResponse(shadow: shadow, highlight: subtleHighlight)
        ] {
            #expect(throws: MixingError.self) {
                try MixingPalette(target: base, response: response)
            }
        }
    }

    @Test
    func testNearBlackAndWhiteUseTheRemainingLightnessRange() throws {
        let middle = MixingTarget(red: 128, green: 128, blue: 128)
        let cases: [(MixingTarget, MixingTarget, MixingTarget)] = [
            (MixingTarget(red: 32, green: 32, blue: 32), MixingTarget(red: 8, green: 8, blue: 8), middle),
            (MixingTarget(red: 248, green: 248, blue: 248), middle, MixingTarget(red: 254, green: 254, blue: 254)),
            (MixingTarget(red: 0, green: 0, blue: 1), MixingTarget(red: 0, green: 0, blue: 0), middle),
            (MixingTarget(red: 255, green: 255, blue: 254), middle, MixingTarget(red: 255, green: 255, blue: 255))
        ]
        for (base, shadow, highlight) in cases {
            let palette = try MixingPalette(target: base, response: paletteResponse(shadow: shadow, highlight: highlight))
            #expect(palette.base.target == base)
            #expect(palette.shadow.target == shadow)
            #expect(palette.highlight.target == highlight)
        }
    }

    @Test
    func testNearBoundaryDoesNotPermitAnArbitrarilySmallDifference() {
        let dark = MixingTarget(red: 32, green: 32, blue: 32)
        let light = MixingTarget(red: 248, green: 248, blue: 248)
        let subtleShadow = MixingTarget(red: 25, green: 25, blue: 25)
        let subtleHighlight = MixingTarget(red: 250, green: 250, blue: 250)
        #expect(throws: MixingError.self) {
            try MixingPalette(target: dark, response: paletteResponse(shadow: subtleShadow))
        }
        #expect(throws: MixingError.self) {
            try MixingPalette(target: light, response: paletteResponse(highlight: subtleHighlight))
        }
    }

    @Test
    func testReferenceAndBlendResponsesRejectInsufficientToneContrast() throws {
        for reference in [
            PaintReference(series: .tamiyaAcrylic, paintCode: "XF-53"),
            PaintReference(series: .mrColor, paintCode: "C13")
        ] {
            let target = try #require(reference.previewTarget)
            let subtle = MixingTarget(
                red: Double(target.red - 1), green: Double(target.green - 1), blue: Double(target.blue - 1)
            )
            let data = try JSONEncoder().encode(paletteResponse(shadow: subtle))
            #expect(throws: MixingError.self) {
                try MixingPalette.decode(data, for: target, referencePaint: reference)
            }
        }
        let request = try sampleBlendRequest()
        var blend = try #require(JSONSerialization.jsonObject(with: blendFixture()) as? [String: Any])
        let subtleHighlight = MixingTarget(red: 129, green: 161, blue: 129)
        blend["palette"] = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(paletteResponse(highlight: subtleHighlight))
        )
        let data = try JSONSerialization.data(withJSONObject: blend)
        #expect(throws: MixingError.self) {
            try request.decodePalette(data)
        }
    }

    @Test
    func testPreviouslySavedSubtleShadowRemainsReadable() throws {
        let recipe = try MixingRecipe(
            target: MixingTarget(red: 127, green: 159, blue: 127),
            response: toneRecipe(white: 100), role: .shadow
        )
        let saved = try JSONEncoder().encode(recipe)
        #expect(try JSONDecoder().decode(MixingRecipe.self, from: saved) == recipe)
    }

    @Test
    func testDistinctRGBLabelsCannotHideIdenticalPaintFormulas() {
        let valid = paletteResponse()
        let repeated = MixingPaletteResponse(
            base: valid.base,
            shadow: MixingToneResponse(target: valid.shadow.target, recipe: valid.base),
            highlight: valid.highlight
        )
        #expect(throws: MixingError.self) {
            try MixingPalette(target: .initial, response: repeated)
        }
    }

    @Test
    func testPureBlackAndWhiteAllowTheMatchingBoundaryTone() throws {
        let black = MixingTarget(red: 0, green: 0, blue: 0)
        let white = MixingTarget(red: 255, green: 255, blue: 255)
        let middle = MixingTarget(red: 128, green: 128, blue: 128)
        let dark = toneRecipe(white: 0)
        let light = toneRecipe(white: 200)
        let middleRecipe = toneRecipe(white: 100)
        let blackPalette = try MixingPalette(
            target: black,
            response: MixingPaletteResponse(
                base: dark,
                shadow: MixingToneResponse(target: black, recipe: dark),
                highlight: MixingToneResponse(target: middle, recipe: middleRecipe)
            )
        )
        let whitePalette = try MixingPalette(
            target: white,
            response: MixingPaletteResponse(
                base: light,
                shadow: MixingToneResponse(target: middle, recipe: middleRecipe),
                highlight: MixingToneResponse(target: white, recipe: light)
            )
        )
        #expect(blackPalette.shadow.target.isBlack)
        #expect(whitePalette.highlight.target.isWhite)
    }

    @Test
    func testInvalidGeneratedRGBIsRejectedWithoutClamping() throws {
        let data = try JSONEncoder().encode(paletteResponse())
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var highlight = try #require(object["highlight"] as? [String: Any])
        highlight["target"] = ["red": 300, "green": 240, "blue": 240]
        object["highlight"] = highlight
        let invalid = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: MixingError.self) {
            try MixingPalette.decode(invalid, for: .initial)
        }
    }

    @Test
    func testThreeRecipesSaveTogetherAndKeepTheirRolesAfterReload() throws {
        try withDefaults { defaults in
            var library = RecipeLibrary(defaults: defaults)
            let palette = try MixingPalette(
                target: .initial, response: paletteResponse(),
                model: AIModelSelection(modelID: "custom-model", reasoningEffort: .low)
            )
            let savedID = library.addItem(named: "手动创建的项目")
            let id = try #require(savedID)
            let didApplyChange4 = library.addMixingPalette(palette, to: id)
            #expect(didApplyChange4)
            let reloaded = RecipeLibrary(defaults: defaults)
            let item = try #require(reloaded.item(id: id))
            #expect(reloaded.items.count == 1)
            #expect(item.text == "手动创建的项目")
            #expect(item.colors.count == 3)
            #expect(item.colors.compactMap(\.mixingRecipe) == palette.recipes)
            #expect(item.colors.map(\.name) == palette.recipes.map { "\($0.role.title) · \($0.response.name)" })
        }
    }

    @Test
    func testOldAIRecipeWithoutARoleStillDecodesAsBaseColor() throws {
        let recipe = try MixingRecipe(target: .initial, response: response())
        let data = try JSONEncoder().encode(recipe)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "role")
        object.removeValue(forKey: "model")
        object.removeValue(forKey: "paintSeries")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(MixingRecipe.self, from: legacy)
        #expect(decoded == recipe)
        #expect(decoded.role == .base)
    }

    @Test
    func testAISettingsRetainCustomModelEffortAndExistingCLIPath() throws {
        try withDefaults { defaults in
            defaults.set("/Applications/My CLI/codex", forKey: "CodexExecutablePath")
            var configuration = AIConfiguration.load(from: defaults)
            #expect(configuration.model == AIModelSelection())
            #expect(configuration.executablePath == "/Applications/My CLI/codex")
            configuration.model = AIModelSelection(modelID: "my-custom-model", reasoningEffort: .ultra)
            configuration.save(to: defaults)
            #expect(AIConfiguration.load(from: defaults) == configuration)
        }
    }

    @Test
    func testEmptyModelCannotStartAndWhitespaceIsTrimmed() throws {
        var configuration = AIConfiguration()
        configuration.model.modelID = " \n "
        #expect(!configuration.isValid)
        #expect(throws: MixingError.self) { try configuration.validated() }
        configuration.model.modelID = "  account-model  \n"
        configuration.executablePath = "  /tmp/my cli/codex  "
        let validated = try configuration.validated()
        #expect(validated.model.modelID == "account-model")
        #expect(validated.executablePath == "/tmp/my cli/codex")
    }

    @Test
    func testCustomModelAndEffortReachCLIArgumentsWithoutChangingPermissions() {
        let directory = URL(fileURLWithPath: "/tmp/mixing")
        for effort in AIReasoningEffort.allCases {
            let model = AIModelSelection(modelID: "my-custom-model", reasoningEffort: effort)
            let arguments = CodexMixingService.arguments(
                schema: directory.appendingPathComponent("schema.json"),
                output: directory.appendingPathComponent("recipe.json"),
                directory: directory, model: model
            )
            let modelIndex = arguments.firstIndex(of: "--model")
            #expect(modelIndex.map { arguments[$0 + 1] } == "my-custom-model")
            let effortArguments = arguments.filter { $0.hasPrefix("model_reasoning_effort=") }
            #expect(effortArguments == (effort == .modelDefault ? [] : ["model_reasoning_effort=\"\(effort.rawValue)\""]))
            #expect(arguments.contains("read-only"))
            #expect(arguments.contains("shell_tool"))
        }
    }

    @Test
    func testGeneratedPaletteKeepsModelSnapshotWhenGlobalSettingsChange() throws {
        var configuration = AIConfiguration()
        configuration.model = AIModelSelection(modelID: "custom-model", reasoningEffort: .medium)
        let originalModel = configuration.model
        let data = try JSONEncoder().encode(paletteResponse())
        let palette = try MixingPalette.decode(data, for: .initial, model: configuration.model)
        configuration.model = AIModelSelection()
        for recipe in palette.recipes {
            let restored = try JSONDecoder().decode(MixingRecipe.self, from: JSONEncoder().encode(recipe))
            #expect(restored.model == originalModel)
            #expect(restored.formattedText.contains("custom-model · medium"))
            #expect(!restored.formattedText.contains(configuration.model.summary))
        }
    }

    @Test
    func testSavingPaletteAppendsOnlyToItsOriginalProject() throws {
        let first = ListItem(text: "第一个项目", colors: [ColorInfo(red: 10, green: 20, blue: 30)])
        let second = ListItem(text: "第二个项目")
        var library = RecipeLibrary(previewItems: [first, second])
        let palette = try MixingPalette(target: .initial, response: paletteResponse())
        let didApplyChange5 = library.renameItem(id: first.id, to: "更名后的项目")
        #expect(didApplyChange5)
        let didApplyChange6 = library.addMixingPalette(palette, to: first.id)
        #expect(didApplyChange6)
        let didApplyChange7 = library.addMixingPalette(palette, to: first.id)
        #expect(didApplyChange7)
        #expect(library.items.count == 2)
        #expect(library.item(id: second.id) == second)
        let project = try #require(library.item(id: first.id))
        #expect(project.text == "更名后的项目")
        #expect(project.colors.first == first.colors.first)
        #expect(project.colors.count == 7)
        #expect(Set(project.colors.map(\.id)).count == 7)
    }

    @Test
    func testDeletedProjectCannotBeRecreatedBySavingAPalette() throws {
        let deleted = ListItem(text: "被删除的项目")
        let kept = ListItem(text: "保留的项目")
        var library = RecipeLibrary(previewItems: [deleted, kept])
        let palette = try MixingPalette(target: .initial, response: paletteResponse())
        let didApplyChange8 = library.removeItem(id: deleted.id)
        #expect(didApplyChange8)
        let didApplyChange9 = library.addMixingPalette(palette, to: deleted.id)
        #expect(!didApplyChange9)
        #expect(library.items == [kept])
    }

    @Test
    func testDeletingAIShadowKeepsBaseAndHighlightRecipes() throws {
        let palette = try MixingPalette(target: .initial, response: paletteResponse())
        let project = ListItem(text: "AI 调色项目")
        var library = RecipeLibrary(previewItems: [project])
        let appended = library.addMixingPalette(palette, to: project.id)
        #expect(appended)
        let shadow = try #require(library.item(id: project.id)?.colors.first { $0.mixingRecipe?.role == .shadow })
        let deleted = library.removeColor(itemID: project.id, colorID: shadow.id)
        #expect(deleted)
        #expect(library.item(id: project.id)?.colors.compactMap(\.mixingRecipe) == [palette.base, palette.highlight])
    }

    @Test
    func testBlendKeepsEverySourceAndNormalizesRelativePercentages() throws {
        let request = try sampleBlendRequest()
        #expect(request.totalPercentage == 90)
        #expect(request.sources.map(\.percentage) == [40, 20, 10, 20])
        for source in request.sources {
            #expect(request.prompt().contains(source.target.description))
            #expect(request.prompt().contains("输入 \(source.percentageText)%"))
        }
        #expect(request.sourceDescription.contains("44.44%"))
        #expect(request.sourceDescription.contains("22.22%"))
        #expect(request.sourceDescription.contains("11.11%"))
        #expect(request.prompt().contains("不得将不足 100% 的部分补成"))
    }

    @Test
    func testBlendRejectsInvalidPercentagesAndSourceRGB() throws {
        let valid = ColorBlendSource(target: .initial, percentage: 40)
        for percentage in [0, -1, 100.01, Double.nan, Double.infinity, -Double.infinity] {
            #expect(throws: MixingError.self) {
                try ColorBlendRequest(sources: [valid, ColorBlendSource(target: .initial, percentage: percentage)])
            }
        }
        for sources in [[], [valid]] {
            #expect(throws: MixingError.self) { try ColorBlendRequest(sources: sources) }
        }
        let invalidTarget = try JSONDecoder().decode(
            MixingTarget.self, from: Data(#"{"red":256,"green":0,"blue":0}"#.utf8)
        )
        #expect(throws: MixingError.self) {
            try ColorBlendRequest(sources: [valid, ColorBlendSource(target: invalidTarget, percentage: 20)])
        }
    }

    @Test
    func testBlendInputDraftDoesNotSilentlyDropAnInvalidRow() throws {
        let valid = ColorBlendEntry(target: .initial, percentage: 33.5)
        var invalid = ColorBlendEntry(target: .initial, percentage: 20)
        invalid.redText = "256"
        #expect(ColorBlendEntry.request(from: [valid, valid, invalid]) == nil)
        invalid.redText = "128"
        for text in ["", "abc", "nan", "inf", "0", "101"] {
            invalid.percentageText = text
            #expect(ColorBlendEntry.request(from: [valid, invalid]) == nil)
        }
        invalid.percentageText = " 16.5 "
        let request = try #require(ColorBlendEntry.request(from: [valid, invalid]))
        #expect(request.sources.count == 2)
        #expect(request.totalPercentage == 50)
    }

    @Test
    func testBlendUsesAIChosenRGBAndPreservesOriginalInputs() throws {
        let request = try sampleBlendRequest()
        let model = AIModelSelection(modelID: "blend-custom-model", reasoningEffort: .high)
        let palette = try request.decodePalette(blendFixture(), model: model)
        // The fixture's green channel differs from the input RGB weighted average (28).
        #expect(palette.base.target == .initial)
        #expect(palette.base.target.green == 160)
        for recipe in palette.recipes {
            #expect(recipe.synthesis?.sources == request.sources)
            #expect(recipe.synthesis?.target == .initial)
            #expect(recipe.synthesis?.explanation == "AI 合成说明测试")
            #expect(recipe.model == model)
            #expect(recipe.response.ingredients.reduce(0) { $0 + $1.drops } == 200)
            #expect(recipe.formattedText.contains("RGB 255, 0, 0 · 40%"))
        }
        #expect(palette.formattedText.contains("AI 合成本色"))
    }

    @Test
    func testBlendRejectsMissingInvalidOrOversizedAIResults() throws {
        let request = try sampleBlendRequest()
        let data = try blendFixture()
        let valid = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for missing in ["synthesis", "palette"] {
            var object = valid
            object.removeValue(forKey: missing)
            let invalid = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: MixingError.self) { try request.decodePalette(invalid) }
        }
        for explanation in ["", " \n ", String(repeating: "色", count: 3_001)] {
            #expect(throws: MixingError.self) {
                try request.decodePalette(blendFixture(explanation: explanation))
            }
        }
        var invalidRGB = valid
        invalidRGB["synthesis"] = [
            "target": ["red": -1, "green": 160, "blue": 128], "explanation": "无效 RGB"
        ]
        let invalid = try JSONSerialization.data(withJSONObject: invalidRGB)
        #expect(throws: MixingError.self) { try request.decodePalette(invalid) }
        #expect(throws: MixingError.self) {
            try request.decodePalette(Data(repeating: 32, count: MixingPalette.maximumResponseBytes + 1))
        }

        // A valid AI target must not bypass the existing 200-drop validation.
        var invalidDoses = valid
        var palette = try #require(valid["palette"] as? [String: Any])
        palette["base"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(response(ingredients: doses(white: 198))))
        invalidDoses["palette"] = palette
        let invalidPalette = try JSONSerialization.data(withJSONObject: invalidDoses)
        #expect(throws: MixingError.self) { try request.decodePalette(invalidPalette) }
    }

    @Test
    func testBlendProvenanceSurvivesSavingReloadingAndIndependentDeletion() throws {
        try withDefaults { defaults in
            var library = RecipeLibrary(defaults: defaults)
            let savedID = library.addItem(named: "多色合成项目")
            let id = try #require(savedID)
            let request = try sampleBlendRequest()
            let palette = try request.decodePalette(blendFixture())
            let saved = library.addMixingPalette(palette, to: id)
            #expect(saved)
            var reloaded = RecipeLibrary(defaults: defaults)
            let item = try #require(reloaded.item(id: id))
            #expect(item.colors.compactMap(\.mixingRecipe) == palette.recipes)
            let base = try #require(item.colors.first)
            let removed = reloaded.removeColor(itemID: id, colorID: base.id)
            #expect(removed)
            let final = RecipeLibrary(defaults: defaults)
            #expect(final.item(id: id)?.colors.compactMap(\.mixingRecipe) == [palette.shadow, palette.highlight])
            #expect(final.item(id: id)?.colors.last?.mixingRecipe?.synthesis?.sources == request.sources)
        }
    }

    @Test
    func testBlendServiceSendsAllInputsAndSchemaToCLI() async throws {
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent("Golden Blend Test-\(UUID().uuidString)")
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fake-codex")
        let script = #"""
        #!/bin/sh
        set -eu
        fixture_dir=${0%/*}
        printf '%s\n' "$@" > "$fixture_dir/arguments.txt"
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
        let configuration = AIConfiguration(
            model: AIModelSelection(modelID: "blend-integration-model", reasoningEffort: .high),
            executablePath: executable.path
        )
        let cases: [(ColorBlendRequest, MixingPaintSet)] = [
            (try sampleBlendRequest(), .soFlat12),
            (try brandBlendRequest(), .soFlat12),
            (try brandBlendRequest(), .fluid13)
        ]
        for (request, paintSet) in cases {
            try blendFixture(paintSet: paintSet).write(to: directory.appendingPathComponent("fixture.json"))
            let palette = try await CodexMixingService().generate(
                from: request, paintSet: paintSet, configuration: configuration
            )
            let prompt = try String(contentsOf: directory.appendingPathComponent("prompt.txt"), encoding: .utf8)
            #expect(prompt == request.prompt(paintSet: paintSet))
            let arguments = try String(contentsOf: directory.appendingPathComponent("arguments.txt"), encoding: .utf8)
            #expect(arguments.contains("--model\nblend-integration-model\n"))
            #expect(arguments.contains("model_reasoning_effort=\"high\""))
            let schema = try Data(contentsOf: directory.appendingPathComponent("schema.json"))
            let expectedSchema = try ColorBlendRequest.outputSchema(paintSet: paintSet)
            #expect(schema == expectedSchema)
            let object = try #require(JSONSerialization.jsonObject(with: schema) as? [String: Any])
            #expect(Set(object["required"] as? [String] ?? []) == ["synthesis", "palette"])
            #expect(palette.base.target == .initial)
            #expect(palette.base.synthesis?.sources == request.sources)
            #expect(palette.base.model == configuration.model)
            #expect(palette.base.paintSet == paintSet)
        }
    }

    @Test
    func testBrandBlendCarriesColorCodesAndRelativeWeightsToBothPaintSets() throws {
        let request = try brandBlendRequest()
        #expect(request.sources.map(\.referencePaint?.paintCode) == ["H1", "H2"])
        #expect(request.sources.map(\.percentage) == [30, 70])
        #expect(request.totalPercentage == 100)
        for paintSet in MixingPaintSet.selectable {
            let prompt = request.prompt(paintSet: paintSet)
            for source in request.sources {
                let reference = try #require(source.referencePaint)
                #expect(prompt.contains(reference.summary))
                #expect(prompt.contains(reference.previewNote))
                #expect(prompt.contains("输入 \(source.percentageText)%"))
            }
            #expect(prompt.contains("归一化 30.00%"))
            #expect(prompt.contains("归一化 70.00%"))
            #expect(prompt.contains(paintSet.title))
            #expect(prompt.contains("不是最终调色原料，不得写入 ingredients 或 steps"))
            #expect(!prompt.contains("用户提供的不是颜料编号"))
        }
    }

    @Test
    func testMixedBlendDraftRequiresExplicitReferenceAndClearsSharedCodesAcrossSeries() throws {
        let rgb = ColorBlendEntry(target: .initial, percentage: 70)
        var reference = ColorBlendEntry(target: MixingTarget(red: 12, green: 34, blue: 56), percentage: 30)
        reference.inputMode = .reference
        #expect(ColorBlendEntry.request(from: [reference, rgb]) == nil)
        reference.selectReferenceSeries(.aqueous)
        reference.selectedPaintCode = "H1"
        let request = try #require(ColorBlendEntry.request(from: [reference, rgb]))
        #expect(request.sources[0].referencePaint?.paintCode == "H1")
        #expect(request.sources[0].referencePaint?.series == .aqueous)
        #expect(request.sources[0].target == PaintReference(series: .aqueous, paintCode: "H1").previewTarget)
        #expect(request.sources[1].referencePaint == nil)
        #expect(request.sources[1].target == .initial)

        reference.inputMode = .rgb
        #expect(reference.source?.referencePaint == nil)
        #expect(reference.source?.target == MixingTarget(red: 12, green: 34, blue: 56))
        reference.inputMode = .reference
        #expect(reference.source?.referencePaint?.paintCode == "H1")
        reference.selectReferenceSeries(.tamiyaAcrylic)
        #expect(reference.selectedPaintCode == nil)
        reference.selectedPaintCode = "X-2"
        let acrylic = try #require(reference.source)
        reference.selectReferenceSeries(.tamiyaEnamel)
        #expect(reference.selectedPaintCode == nil)
        #expect(ColorBlendEntry.request(from: [reference, rgb]) == nil)
        reference.selectedPaintCode = "X-2"
        let enamel = try #require(reference.source)
        let sameCode = try ColorBlendRequest(sources: [acrylic, enamel])
        #expect(sameCode.sources.map(\.referencePaint?.series) == [.tamiyaAcrylic, .tamiyaEnamel])
        #expect(sameCode.sourceDescription.contains(PaintSeries.tamiyaAcrylic.title))
        #expect(sameCode.sourceDescription.contains(PaintSeries.tamiyaEnamel.title))
        reference.selectedPaintCode = "H1"
        #expect(ColorBlendEntry.request(from: [reference, rgb]) == nil)
    }

    @Test
    func testBrandBlendRejectsUnknownCodesAndMismatchedRGBIncludingSavedSources() throws {
        let valid = ColorBlendSource(target: .initial, percentage: 70)
        for reference in [
            PaintReference(series: .aqueous, paintCode: "H1"),
            PaintReference(series: .aqueous, paintCode: "H999")
        ] {
            let invalid = ColorBlendSource(target: .initial, percentage: 30, referencePaint: reference)
            #expect(throws: MixingError.self) {
                try ColorBlendRequest(sources: [invalid, valid])
            }
            let sourceData = try JSONEncoder().encode([invalid, valid])
            let object: [String: Any] = [
                "sources": try JSONSerialization.jsonObject(with: sourceData),
                "target": ["red": 128, "green": 160, "blue": 128],
                "explanation": "无效的参考色不能进入已保存合成。"
            ]
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: MixingError.self) {
                try JSONDecoder().decode(ColorBlendSynthesis.self, from: data)
            }
        }
    }

    @Test
    func testSavedBlendsReadLegacyRGBSourcesAndPreserveReferenceRGBSnapshots() throws {
        let request = try sampleBlendRequest()
        let original = try ColorBlendSynthesis(sources: request.sources, target: .initial, explanation: "旧版合成")
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any]
        )
        // Pre-feature JSON had only target and percentage in each source.
        let sources = try #require(object["sources"] as? [[String: Any]])
        object["sources"] = sources.map { source in source.filter { $0.key != "referencePaint" } }
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(ColorBlendSynthesis.self, from: legacyData) == original)

        let referenceData = Data(#"{"series":"aqueous","paintCode":"H1","previewTargetSnapshot":{"red":230,"green":231,"blue":232}}"#.utf8)
        let reference = try JSONDecoder().decode(PaintReference.self, from: referenceData)
        let snapshot = MixingTarget(red: 230, green: 231, blue: 232)
        let mixed = try ColorBlendSynthesis(
            sources: [
                ColorBlendSource(target: snapshot, percentage: 30, referencePaint: reference),
                ColorBlendSource(target: .initial, percentage: 70)
            ], target: .initial, explanation: "保留原始标准色预览"
        )
        let restored = try JSONDecoder().decode(ColorBlendSynthesis.self, from: JSONEncoder().encode(mixed))
        #expect(restored == mixed)
        #expect(restored.sources[0].referencePaint?.previewTarget == snapshot)
        #expect(restored.formattedText.contains("#H1"))
        #expect(restored.formattedText.contains("RGB 230, 231, 232"))
    }

    @Test
    func testBrandBlendProvenanceSurvivesSavingAllTonesInEitherGoldenPaintSet() throws {
        for paintSet in MixingPaintSet.selectable {
            try withDefaults { defaults in
                var library = RecipeLibrary(defaults: defaults)
                let savedID = library.addItem(named: "H1 30% + H2 70%")
                let id = try #require(savedID)
                let request = try brandBlendRequest()
                let palette = try request.decodePalette(blendFixture(paintSet: paintSet), paintSet: paintSet)
                let saved = library.addMixingPalette(palette, to: id)
                #expect(saved)
                var reloaded = RecipeLibrary(defaults: defaults)
                let item = try #require(reloaded.item(id: id))
                #expect(item.colors.compactMap(\.mixingRecipe) == palette.recipes)
                for recipe in item.colors.compactMap(\.mixingRecipe) {
                    #expect(recipe.synthesis?.sources == request.sources)
                    #expect(recipe.referencePaint == nil)
                    #expect(recipe.paintSet == paintSet)
                    #expect(recipe.response.ingredients.reduce(0) { $0 + $1.drops } == 200)
                    #expect(Set(recipe.response.ingredients.map(\.paintCode)).isSubset(of: Set(paintSet.paints.map(\.code))))
                    for source in request.sources {
                        let reference = try #require(source.referencePaint)
                        #expect(recipe.formattedText.contains(reference.summary))
                        #expect(recipe.formattedText.contains("\(source.percentageText)%"))
                    }
                }
                let shadow = try #require(item.colors.first { $0.mixingRecipe?.role == .shadow })
                let removed = reloaded.removeColor(itemID: id, colorID: shadow.id)
                #expect(removed)
                #expect(RecipeLibrary(defaults: defaults).item(id: id)?.colors.compactMap(\.mixingRecipe) == [
                    palette.base, palette.highlight
                ])
            }
        }
    }

    private func brandBlendRequest() throws -> ColorBlendRequest {
        try ColorBlendRequest(sources: try [("H1", 30.0), ("H2", 70.0)].map { code, percentage in
            let reference = PaintReference(series: .aqueous, paintCode: code)
            return ColorBlendSource(
                target: try #require(reference.previewTarget), percentage: percentage, referencePaint: reference
            )
        })
    }

    private func sampleBlendRequest() throws -> ColorBlendRequest {
        try ColorBlendRequest(sources: [
            ColorBlendSource(target: MixingTarget(red: 255, green: 0, blue: 0), percentage: 40),
            ColorBlendSource(target: MixingTarget(red: 0, green: 0, blue: 255), percentage: 20),
            ColorBlendSource(target: MixingTarget(red: 255, green: 255, blue: 0), percentage: 10),
            ColorBlendSource(target: MixingTarget(red: 0, green: 0, blue: 0), percentage: 20)
        ])
    }

    private func blendFixture(
        explanation: String = "AI 合成说明测试", paintSet: MixingPaintSet = .soFlat12
    ) throws -> Data {
        let palette = try JSONSerialization.jsonObject(with: JSONEncoder().encode(paletteResponse(paintSet: paintSet)))
        return try JSONSerialization.data(withJSONObject: [
            "synthesis": [
                "target": ["red": 128, "green": 160, "blue": 128],
                "explanation": explanation
            ],
            "palette": palette
        ])
    }

    private func paletteResponse(
        shadow: MixingTarget = MixingTarget(red: 64, green: 80, blue: 64),
        highlight: MixingTarget = MixingTarget(red: 220, green: 235, blue: 220),
        paintSet: MixingPaintSet = .soFlat12
    ) -> MixingPaletteResponse {
        MixingPaletteResponse(
            base: response(ingredients: doses(paintSet: paintSet)),
            shadow: MixingToneResponse(target: shadow, recipe: toneRecipe(white: 100, paintSet: paintSet)),
            highlight: MixingToneResponse(target: highlight, recipe: toneRecipe(white: 200, paintSet: paintSet))
        )
    }

    private func toneRecipe(white: Int, paintSet: MixingPaintSet = .soFlat12) -> MixingResponse {
        let whiteCode = paintSet == .fluid13 ? "2380" : "6755"
        let blackCode = paintSet == .fluid13 ? "2040" : "6745"
        return response(ingredients: paintSet.paints.map {
            PaintDose(paintCode: $0.code, drops: $0.code == whiteCode ? white : ($0.code == blackCode ? 200 - white : 0))
        })
    }

    private func doses(white: Int = 199, paintSet: MixingPaintSet = .soFlat12) -> [PaintDose] {
        let whiteCode = paintSet == .fluid13 ? "2380" : "6755"
        let blackCode = paintSet == .fluid13 ? "2040" : "6745"
        return paintSet.paints.map {
            PaintDose(paintCode: $0.code, drops: $0.code == whiteCode ? white : ($0.code == blackCode ? 1 : 0))
        }
    }

    private func response(ingredients: [PaintDose]? = nil, steps: [MixingStep]? = nil) -> MixingResponse {
        let ingredients = ingredients ?? doses()
        return MixingResponse(
            name: "示例灰色",
            ingredients: ingredients,
            steps: steps ?? ingredients.filter { $0.drops > 0 }.map {
                MixingStep(paintCode: $0.paintCode, drops: $0.drops, instruction: "充分搅匀。")
            },
            notes: "请先做小样，干燥后对色。"
        )
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "GoldenMixingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    private func withLegacyPreferences(value: Any, body: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: [RecipeLibrary.itemsKey: value], format: .binary, options: 0
        )
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        try body(url)
    }

    private func withProcessFiles(
        _ body: (URL, FileHandle, FileHandle, URL) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logURL = directory.appendingPathComponent("output.log")
        #expect(FileManager.default.createFile(atPath: logURL.path, contents: nil))
        let input = FileHandle.nullDevice
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }
        try await body(directory, input, log, logURL)
    }

    private func expectProcessExited(logURL: URL) throws {
        let output = try String(contentsOf: logURL, encoding: .utf8)
        let pid = try #require(Int32(output.trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }
}
