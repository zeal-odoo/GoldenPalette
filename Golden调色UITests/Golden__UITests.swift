import XCTest
import XCUIAutomation

@MainActor
final class Golden__UITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
    }

    func testColorEditingPreservesMethod() throws {
        let app = launchApp(mixingResponse: try threeToneFixture())
        createRecipe("Recipe A", in: app)
        generatePalette(in: app)

        let methodButton = app.buttons["编辑调色方法：界面验证用配方。"].firstMatch
        let detail = app.scrollViews["recipeDetailScrollView"]
        for _ in 0..<8 {
            if methodButton.exists && methodButton.isHittable { break }
            detail.scroll(byDeltaX: 0, deltaY: -160)
        }
        methodButton.click()
        let methodEditor = app.textViews.firstMatch
        XCTAssertTrue(methodEditor.waitForExistence(timeout: 5))
        replaceText(in: methodEditor, with: "Two thin coats")
        app.buttons["saveMethodButton"].click()

        app.buttons["编辑颜色：本色 · UI 本色"].click()
        let nameField = app.textFields["colorNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        app.activate()
        replaceText(in: nameField, with: "Updated color")
        app.buttons["saveColorButton"].click()

        XCTAssertTrue(app.buttons["编辑颜色：Updated color"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["编辑调色方法：Two thin coats"].exists)
    }

    func testColorEditorKeepsItsRecipeWhenSelectionChanges() throws {
        let app = launchApp(mixingResponse: try threeToneFixture())
        createRecipe("Second recipe", in: app)
        createRecipe("First recipe", in: app)
        generatePalette(in: app)

        app.buttons["编辑颜色：本色 · UI 本色"].click()
        XCTAssertTrue(app.textFields["colorNameField"].waitForExistence(timeout: 5))
        selectRecipe("Second recipe", in: app)
        XCTAssertTrue(app.staticTexts["留白待色"].waitForExistence(timeout: 5), app.windows.debugDescription)

        replaceText(in: app.textFields["colorNameField"], with: "Updated first color")
        app.buttons["saveColorButton"].click()
        XCTAssertTrue(app.staticTexts["留白待色"].waitForExistence(timeout: 5), app.windows.debugDescription)

        selectRecipe("First recipe", in: app)
        XCTAssertTrue(app.buttons["编辑颜色：Updated first color"].waitForExistence(timeout: 5))
    }

    func testRecipeChangesAreSharedAcrossWindows() {
        let app = launchApp()
        createRecipe("Shared recipe A", in: app)

        app.typeKey("n", modifierFlags: [.command])
        let twoWindows = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == 2"),
            object: app.windows
        )
        XCTAssertEqual(XCTWaiter.wait(for: [twoWindows], timeout: 5), .completed)

        createRecipe("Shared recipe B", in: app)
        for window in app.windows.allElementsBoundByIndex {
            XCTAssertTrue(window.staticTexts["Shared recipe A"].firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(window.staticTexts["Shared recipe B"].firstMatch.waitForExistence(timeout: 5))
        }
    }

    func testNewRecipeWindowCanBeCancelledAndReopened() {
        let app = launchApp()

        app.buttons["newRecipeButton"].firstMatch.click()
        let field = app.textFields["recipeNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Discarded recipe")
        app.typeKey(.escape, modifierFlags: [])
        waitUntilGone(field)

        createRecipe("Saved recipe", in: app)
        XCTAssertFalse(app.staticTexts["Discarded recipe"].exists)
        XCTAssertTrue(app.staticTexts["Saved recipe"].firstMatch.exists)
    }

    func testAIMixingRejectsInvalidRGBAndCanReopen() {
        let app = launchApp()
        XCTAssertFalse(app.buttons["aiMixingButton"].exists)
        XCTAssertTrue(app.buttons["emptyNewProjectButton"].exists)
        createRecipe("RGB 项目", in: app)
        app.buttons["aiMixingButton"].firstMatch.click()
        let red = app.textFields["mixingRField"]
        XCTAssertTrue(red.waitForExistence(timeout: 5))
        replaceText(in: red, with: "256")
        XCTAssertFalse(app.buttons["generateMixingButton"].isEnabled)
        replaceText(in: red, with: "255")
        replaceText(in: app.textFields["mixingGField"], with: "0")
        replaceText(in: app.textFields["mixingBField"], with: "255")
        XCTAssertTrue(app.buttons["generateMixingButton"].isEnabled)
        XCTAssertEqual(app.staticTexts["mixingRGBStatus"].value as? String, "sRGB · #FF00FF")
        app.buttons["closeAIMixingButton"].click()
        waitUntilGone(red)
        app.buttons["aiMixingButton"].firstMatch.click()
        XCTAssertTrue(app.textFields["mixingRField"].waitForExistence(timeout: 5))
        app.buttons["closeAIMixingButton"].click()
    }

    func testGeneratedRecipeCanBeSavedAndViewed() throws {
        // The process layer has separate integration coverage; UI runs use no account quota or saved defaults.
        let app = launchApp(mixingResponse: try threeToneFixture())
        app.buttons["aiSettingsButton"].firstMatch.click()
        let model = app.textFields["aiModelField"]
        XCTAssertTrue(model.waitForExistence(timeout: 5))
        replaceText(in: model, with: "ui-custom-model")
        chooseMenuOption("低 · low", picker: "aiReasoningPicker", in: app)
        app.typeKey("w", modifierFlags: [.command])
        waitUntilGone(model)

        // Settings are global and survive closing the settings window.
        app.typeKey(",", modifierFlags: [.command])
        XCTAssertTrue(model.waitForExistence(timeout: 5))
        XCTAssertEqual(model.value as? String, "ui-custom-model")
        app.typeKey("w", modifierFlags: [.command])
        waitUntilGone(model)

        createRecipe("Other project", in: app)
        createRecipe("My painting project", in: app)
        app.buttons["aiMixingButton"].firstMatch.click()
        XCTAssertTrue(app.buttons["generateMixingButton"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["mixingProjectTitle"].value as? String, "AI 调色 · My painting project")
        XCTAssertEqual(app.staticTexts["mixingModelSummary"].value as? String, "ui-custom-model · low")
        app.buttons["generateMixingButton"].click()
        XCTAssertTrue(app.buttons["mixingRole-base"].waitForExistence(timeout: 10))

        let roles = [("base", "本色"), ("shadow", "阴影色"), ("highlight", "高光色")]
        for (identifier, title) in roles {
            app.buttons["mixingRole-\(identifier)"].click()
            let heading = app.descendants(matching: .any)["mixingRoleTitle"].firstMatch
            let changed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", "\(title) · UI \(title)"),
                object: heading
            )
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, app.sheets.debugDescription)
            XCTAssertTrue(app.descendants(matching: .any)["mixingTotal"].firstMatch.exists)
        }

        XCTAssertTrue(app.buttons["saveAIMixingButton"].isEnabled)
        app.buttons["saveAIMixingButton"].click()
        let detail = app.scrollViews["recipeDetailScrollView"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertEqual(app.outlines.outlineRows.count, 2)
        selectRecipe("Other project", in: app)
        XCTAssertTrue(app.staticTexts["留白待色"].waitForExistence(timeout: 5), app.windows.debugDescription)
        selectRecipe("My painting project", in: app)

        // Changing the global model must not relabel recipes that were already generated.
        app.buttons["aiSettingsButton"].firstMatch.click()
        XCTAssertTrue(model.waitForExistence(timeout: 5))
        app.buttons["resetAIModelButton"].click()
        app.typeKey("w", modifierFlags: [.command])
        waitUntilGone(model)

        for (_, title) in roles {
            let viewRecipe = app.buttons["查看\(title)配方"].firstMatch
            for _ in 0..<6 {
                if viewRecipe.exists && viewRecipe.isHittable { break }
                detail.scroll(byDeltaX: 0, deltaY: -220)
            }
            XCTAssertTrue(viewRecipe.waitForExistence(timeout: 5))
            viewRecipe.click()
            let recipeWindow = app.windows["\(title)配方 · My painting project"]
            XCTAssertTrue(recipeWindow.waitForExistence(timeout: 5), app.windows.debugDescription)
            let heading = recipeWindow.descendants(matching: .any)["mixingRoleTitle"].firstMatch
            XCTAssertTrue(heading.waitForExistence(timeout: 5))
            let changed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", "\(title) · UI \(title)"),
                object: heading
            )
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, recipeWindow.debugDescription)
            XCTAssertTrue(recipeWindow.descendants(matching: .any)["mixingTotal"].firstMatch.exists)
            XCTAssertTrue(recipeWindow.buttons["copySavedMixingRecipeButton"].exists)
            XCTAssertEqual(
                recipeWindow.descendants(matching: .any)["savedMixingModelSummary"].firstMatch.value as? String,
                "ui-custom-model · low"
            )
            recipeWindow.buttons["closeSavedMixingRecipeButton"].click()
            waitUntilGone(recipeWindow)
        }
    }

    func testIndividualColorsCanBeDeletedWhileKeepingTheProject() throws {
        let app = launchApp(mixingResponse: try threeToneFixture())
        createRecipe("Delete colors project", in: app)
        generatePalette(in: app)

        let detail = app.scrollViews["recipeDetailScrollView"]
        for name in ["本色 · UI 本色", "阴影色 · UI 阴影色", "高光色 · UI 高光色"] {
            let deleteButton = app.buttons["删除颜色：\(name)"]
            for _ in 0..<8 {
                if deleteButton.exists && deleteButton.isHittable { break }
                detail.scroll(byDeltaX: 0, deltaY: -160)
            }
            XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
            deleteButton.click()
            waitUntilGone(app.buttons["编辑颜色：\(name)"])
            XCTAssertEqual(app.outlines.outlineRows.count, 1)
            XCTAssertTrue(app.staticTexts["Delete colors project"].firstMatch.exists)
            if name == "本色 · UI 本色" {
                XCTAssertTrue(app.buttons["编辑颜色：阴影色 · UI 阴影色"].exists)
            }
        }
        XCTAssertTrue(app.staticTexts["留白待色"].waitForExistence(timeout: 5))
    }

    func testBlendInputsValidateAndRowsCanBeRemoved() {
        let app = launchApp()
        createRecipe("合成输入项目", in: app)
        openBlendEditor(in: app)
        let generate = app.buttons["generateMixingButton"]
        let red = app.textFields["blendRField-0"]
        replaceText(in: red, with: "256")
        XCTAssertFalse(generate.isEnabled)
        replaceText(in: red, with: "255")
        let percentage = app.textFields["blendPercentageField-0"]
        replaceText(in: percentage, with: "0")
        XCTAssertFalse(generate.isEnabled)
        replaceText(in: percentage, with: "40")
        replaceText(in: app.textFields["blendPercentageField-1"], with: "20")
        XCTAssertTrue(generate.isEnabled)
        XCTAssertEqual(
            app.staticTexts["blendPercentageStatus"].value as? String,
            "占比合计 60% · 按相对比例换算为 100%"
        )

        let add = app.buttons["addBlendSourceButton"]
        revealBlendInput(add, in: app)
        add.click()
        let thirdPercentage = app.textFields["blendPercentageField-2"]
        XCTAssertTrue(thirdPercentage.waitForExistence(timeout: 5))
        revealBlendInput(thirdPercentage, in: app)
        replaceText(in: thirdPercentage, with: "10")
        let remove = app.buttons["removeBlendSource-2"]
        revealBlendInput(remove, in: app)
        remove.click()
        waitUntilGone(thirdPercentage)
        XCTAssertEqual(app.textFields["blendPercentageField-0"].value as? String, "40")
        XCTAssertEqual(app.textFields["blendPercentageField-1"].value as? String, "20")
        XCTAssertFalse(app.buttons["removeBlendSource-0"].isEnabled)
        app.buttons["closeAIMixingButton"].click()
    }

    func testAIBlendCanBeRegeneratedSavedAndViewed() throws {
        let app = launchApp(blendResponse: try blendFixture())
        createRecipe("AI 合成项目", in: app)
        openBlendEditor(in: app)
        for (index, channels) in [(0, ["255", "0", "0"]), (1, ["0", "0", "255"])] {
            for (channel, value) in zip(["R", "G", "B"], channels) {
                replaceText(in: app.textFields["blend\(channel)Field-\(index)"], with: value)
            }
        }
        replaceText(in: app.textFields["blendPercentageField-0"], with: "40")
        replaceText(in: app.textFields["blendPercentageField-1"], with: "20")
        let generate = app.buttons["generateMixingButton"]
        revealBlendInput(generate, in: app)
        generate.click()
        let target = app.staticTexts["blendTargetRGB"]
        XCTAssertTrue(target.waitForExistence(timeout: 10), app.sheets.debugDescription)
        // Only the injected AI response contains this RGB; the inputs are red and blue.
        XCTAssertEqual(target.value as? String, "RGB 128, 160, 128")
        XCTAssertTrue(app.staticTexts["blendExplanation"].exists)
        XCTAssertTrue(app.buttons["saveAIMixingButton"].isEnabled)

        let percentage = app.textFields["blendPercentageField-0"]
        revealBlendInput(percentage, in: app, scrollDown: false)
        replaceText(in: percentage, with: "50")
        XCTAssertFalse(app.buttons["saveAIMixingButton"].isEnabled)
        XCTAssertFalse(target.exists)
        revealBlendInput(generate, in: app)
        generate.click()
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        app.buttons["saveAIMixingButton"].click()
        waitUntilGone(generate)

        let viewRecipe = app.buttons["查看本色配方"].firstMatch
        XCTAssertTrue(viewRecipe.waitForExistence(timeout: 5))
        viewRecipe.click()
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertEqual(target.value as? String, "RGB 128, 160, 128")
        XCTAssertEqual(app.staticTexts["blendExplanation"].value as? String, "AI 按输入颜色及比例合成的测试结果。")
        XCTAssertTrue(app.staticTexts["1. RGB 255, 0, 0 · 50%"].exists)
        XCTAssertTrue(app.staticTexts["2. RGB 0, 0, 255 · 20%"].exists)
        app.buttons["closeSavedMixingRecipeButton"].click()
    }

    func testTamiyaReferenceUsesGoldenIngredientsAndSurvivesSaving() throws {
        let app = launchApp(mixingResponse: try threeToneFixture())
        createRecipe("Tamiya reference project", in: app)
        app.buttons["aiMixingButton"].firstMatch.click()
        app.radioButtons["品牌标准色"].click()
        chooseMenuOption("Lacquer 溶剂型漆 · LP", picker: "referencePaintSeriesPicker", in: app)
        selectReference("LP-34", in: app)
        let generate = app.buttons["generateMixingButton"]
        revealBlendInput(generate, in: app)
        generate.click()
        XCTAssertTrue(app.buttons["mixingRole-base"].waitForExistence(timeout: 10), app.sheets.debugDescription)
        XCTAssertEqual(app.staticTexts["savedMixingPaintSeries"].value as? String, "调色用漆：GOLDEN SoFlat")
        XCTAssertTrue((app.staticTexts["savedReferencePaint"].value as? String)?.contains("#LP-34") == true)
        XCTAssertTrue(app.descendants(matching: .any)["recipePaint-6755"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["recipePaint-LP-34"].firstMatch.exists)

        let brand = app.popUpButtons["referencePaintBrandPicker"]
        revealBlendInput(brand, in: app, scrollDown: false)
        chooseMenuOption("郡士 Mr.Hobby", picker: "referencePaintBrandPicker", in: app)
        XCTAssertFalse(app.buttons["mixingRole-base"].exists)
        XCTAssertFalse(app.buttons["saveAIMixingButton"].isEnabled)
        XCTAssertFalse(generate.isEnabled)
        XCTAssertFalse(app.staticTexts["selectedReferencePaint"].exists)
        chooseMenuOption("田宫 Tamiya", picker: "referencePaintBrandPicker", in: app)
        chooseMenuOption("Lacquer 溶剂型漆 · LP", picker: "referencePaintSeriesPicker", in: app)
        selectReference("LP-34", in: app)
        revealBlendInput(generate, in: app)
        generate.click()
        XCTAssertTrue(app.buttons["mixingRole-base"].waitForExistence(timeout: 10))
        app.buttons["saveAIMixingButton"].click()
        waitUntilGone(generate)

        app.buttons["查看本色配方"].firstMatch.click()
        let savedReference = app.staticTexts["savedReferencePaint"].firstMatch
        XCTAssertTrue(savedReference.waitForExistence(timeout: 5))
        XCTAssertTrue((savedReference.value as? String)?.contains("田宫 Tamiya") == true)
        XCTAssertTrue((savedReference.value as? String)?.contains("#LP-34") == true)
        XCTAssertEqual(app.staticTexts["savedMixingPaintSeries"].value as? String, "调色用漆：GOLDEN SoFlat")
        app.buttons["closeSavedMixingRecipeButton"].click()
        waitUntilGone(savedReference)

        app.buttons["aiMixingButton"].firstMatch.click()
        let selected = app.staticTexts["selectedReferencePaint"]
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertTrue((selected.value as? String)?.contains("#LP-34") == true)
        app.buttons["closeAIMixingButton"].click()
        waitUntilGone(selected)
        app.buttons["编辑颜色：本色 · UI 本色"].click()
        let editorSeries = app.popUpButtons["editorPaintSeriesPicker"]
        XCTAssertTrue(editorSeries.waitForExistence(timeout: 5))
        XCTAssertEqual(editorSeries.value as? String, "Lacquer 溶剂型漆 · LP")
        app.typeKey(.escape, modifierFlags: [])
    }

    func testTamiyaSprayReferenceGeneratesSavesAndReopensWithGoldenPaints() throws {
        let app = launchApp(mixingResponse: try threeToneFixture())
        createRecipe("TS reference project", in: app)
        app.buttons["aiMixingButton"].firstMatch.click()
        app.radioButtons["品牌标准色"].click()
        chooseMenuOption("喷罐漆 · TS", picker: "referencePaintSeriesPicker", in: app)
        selectReference("TS-32", in: app)
        XCTAssertTrue((app.staticTexts["referencePreviewRGB"].value as? String)?.contains("RGB 137, 147, 145") == true)
        let generate = app.buttons["generateMixingButton"]
        revealBlendInput(generate, in: app)
        generate.click()
        XCTAssertTrue(app.buttons["mixingRole-base"].waitForExistence(timeout: 10), app.sheets.debugDescription)
        XCTAssertTrue((app.staticTexts["savedReferencePaint"].value as? String)?.contains("#TS-32") == true)
        XCTAssertEqual(app.staticTexts["savedMixingPaintSeries"].value as? String, "调色用漆：GOLDEN SoFlat")
        XCTAssertTrue(app.descendants(matching: .any)["recipePaint-6755"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["recipePaint-TS-32"].firstMatch.exists)
        app.buttons["saveAIMixingButton"].click()
        waitUntilGone(generate)

        for role in ["本色", "阴影色", "高光色"] {
            app.buttons["查看\(role)配方"].firstMatch.click()
            let savedReference = app.staticTexts["savedReferencePaint"]
            XCTAssertTrue(savedReference.waitForExistence(timeout: 5))
            XCTAssertTrue((savedReference.value as? String)?.contains("喷罐漆 · TS") == true)
            XCTAssertTrue((savedReference.value as? String)?.contains("#TS-32") == true)
            XCTAssertEqual(app.staticTexts["savedMixingPaintSeries"].value as? String, "调色用漆：GOLDEN SoFlat")
            XCTAssertEqual(app.staticTexts["mixingTotal"].value as? String, "合计 200 滴")
            app.buttons["closeSavedMixingRecipeButton"].click()
            waitUntilGone(savedReference)
        }

        app.buttons["aiMixingButton"].firstMatch.click()
        let selected = app.staticTexts["selectedReferencePaint"]
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertTrue((selected.value as? String)?.contains("#TS-32") == true)
        XCTAssertEqual(app.popUpButtons["referencePaintSeriesPicker"].value as? String, "喷罐漆 · TS")
        app.buttons["closeAIMixingButton"].click()
        waitUntilGone(selected)
        app.buttons["编辑颜色：本色 · UI 本色"].click()
        let editorSeries = app.popUpButtons["editorPaintSeriesPicker"]
        XCTAssertTrue(editorSeries.waitForExistence(timeout: 5))
        XCTAssertEqual(editorSeries.value as? String, "喷罐漆 · TS")
        app.typeKey(.escape, modifierFlags: [])
    }

    func testMrHobbyReferenceIsClearedWhenSwitchingToRGBAndBlend() throws {
        let app = launchApp(
            mixingResponse: try threeToneFixture(whiteCode: "2380", blackCode: "2040"),
            blendResponse: try blendFixture(whiteCode: "2380", blackCode: "2040")
        )
        createRecipe("MrHobby reference project", in: app)
        app.buttons["aiMixingButton"].firstMatch.click()
        chooseMenuOption("Fluid Acrylics 13 色", picker: "mixingPaintSetPicker", in: app)
        app.radioButtons["品牌标准色"].click()
        chooseMenuOption("郡士 Mr.Hobby", picker: "referencePaintBrandPicker", in: app)
        selectReference("C13", in: app)
        let generate = app.buttons["generateMixingButton"]
        revealBlendInput(generate, in: app)
        generate.click()
        XCTAssertTrue(app.staticTexts["savedReferencePaint"].waitForExistence(timeout: 10), app.sheets.debugDescription)
        XCTAssertTrue((app.staticTexts["savedReferencePaint"].value as? String)?.contains("#C13") == true)
        XCTAssertEqual(app.staticTexts["savedMixingPaintSeries"].value as? String, "调色用漆：GOLDEN Fluid Acrylics")
        XCTAssertFalse(app.descendants(matching: .any)["recipePaint-C13"].firstMatch.exists)

        let single = app.radioButtons["单个颜色"]
        revealBlendInput(single, in: app, scrollDown: false)
        single.click()
        XCTAssertFalse(app.buttons["saveAIMixingButton"].isEnabled)
        revealBlendInput(generate, in: app)
        generate.click()
        XCTAssertTrue(app.buttons["mixingRole-base"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["savedReferencePaint"].exists)

        let blend = app.radioButtons["多色合成"]
        revealBlendInput(blend, in: app, scrollDown: false)
        blend.click()
        XCTAssertFalse(app.buttons["saveAIMixingButton"].isEnabled)
        revealBlendInput(generate, in: app)
        generate.click()
        XCTAssertTrue(app.staticTexts["blendTargetRGB"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["savedReferencePaint"].exists)
        app.buttons["saveAIMixingButton"].click()
        waitUntilGone(generate)
        app.buttons["查看本色配方"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["blendTargetRGB"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["savedReferencePaint"].exists)
        XCTAssertEqual(app.staticTexts["savedMixingPaintSeries"].value as? String, "调色用漆：GOLDEN Fluid Acrylics")
        app.buttons["closeSavedMixingRecipeButton"].click()
    }

    func testReferenceCannotSaveAIResponseUsingForeignIngredients() throws {
        let app = launchApp(mixingResponse: try threeToneFixture(whiteCode: "LP-2", blackCode: "LP-1"))
        createRecipe("Invalid ingredients project", in: app)
        app.buttons["aiMixingButton"].firstMatch.click()
        app.radioButtons["品牌标准色"].click()
        selectReference("XF-53", in: app)
        let generate = app.buttons["generateMixingButton"]
        revealBlendInput(generate, in: app)
        generate.click()
        XCTAssertTrue(app.staticTexts["mixingError"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["mixingRole-base"].exists)
        XCTAssertFalse(app.buttons["saveAIMixingButton"].isEnabled)
        app.buttons["closeAIMixingButton"].click()
    }

    func testFluidIngredientsDisplayAndRemainInSavedRecipes() throws {
        let app = launchApp(mixingResponse: try threeToneFixture(whiteCode: "2380", blackCode: "2040"))
        createRecipe("Fluid recipe project", in: app)
        app.buttons["aiMixingButton"].firstMatch.click()
        let summary = app.staticTexts["mixingPaintSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue((summary.value as? String)?.contains("12 色") == true)
        let soFlatNote = app.staticTexts["paintPreviewNote-goldenSoFlat"]
        XCTAssertTrue((soFlatNote.value as? String)?.contains("近似屏幕参考") == true)
        chooseMenuOption("Fluid Acrylics 13 色", picker: "mixingPaintSetPicker", in: app)
        let fluidNote = app.staticTexts["paintPreviewNote-goldenFluid"]
        XCTAssertTrue(fluidNote.waitForExistence(timeout: 5))
        XCTAssertTrue((fluidNote.value as? String)?.contains("官方调色器的 sRGB") == true)
        XCTAssertTrue((summary.value as? String)?.contains("13 色") == true)
        XCTAssertFalse((summary.value as? String)?.contains("SoFlat") == true)
        XCTAssertFalse(app.descendants(matching: .any)["availablePaint-6755"].firstMatch.exists)
        app.radioButtons["品牌标准色"].click()
        chooseMenuOption("GOLDEN", picker: "referencePaintBrandPicker", in: app)
        chooseMenuOption("Fluid Acrylics · 指定 13 色", picker: "referencePaintSeriesPicker", in: app)
        selectReference("2276", in: app)
        XCTAssertTrue((app.staticTexts["referencePreviewRGB"].value as? String)?.contains("RGB 243, 60, 0") == true)
        let generate = app.buttons["generateMixingButton"]
        revealBlendInput(generate, in: app)
        generate.click()
        XCTAssertTrue(app.buttons["mixingRole-base"].waitForExistence(timeout: 10))
        XCTAssertTrue((app.buttons["mixingRole-base"].value as? String)?.contains("RGB 243, 60, 0") == true)
        XCTAssertFalse(app.descendants(matching: .any)["recipePaint-6755"].firstMatch.exists)
        let generatedWhite = app.descendants(matching: .any)["recipePaint-2380"].firstMatch
        revealPaintRow(generatedWhite, in: app.scrollViews["mixingResultsScrollView"])
        XCTAssertTrue(generatedWhite.label.contains("GOLDEN Fluid Acrylics"), generatedWhite.debugDescription)
        app.buttons["saveAIMixingButton"].click()
        waitUntilGone(generate)
        app.buttons["查看本色配方"].firstMatch.click()
        let series = app.staticTexts["savedMixingPaintSeries"]
        XCTAssertTrue(series.waitForExistence(timeout: 5))
        XCTAssertEqual(series.value as? String, "调色用漆：GOLDEN Fluid Acrylics")
        XCTAssertTrue((app.staticTexts["mixingTargetRGB"].value as? String)?.contains("RGB 243, 60, 0") == true)
        XCTAssertTrue((app.staticTexts["savedReferencePaint"].value as? String)?.contains("#2276") == true)
        let fluidWhite = app.descendants(matching: .any)["recipePaint-2380"].firstMatch
        revealPaintRow(fluidWhite, in: app.scrollViews["savedMixingRecipeScrollView"])
        XCTAssertTrue(fluidWhite.label.contains("199 滴"), fluidWhite.label)
        XCTAssertTrue(fluidWhite.label.contains("GOLDEN Fluid Acrylics"), fluidWhite.label)
        XCTAssertFalse(app.descendants(matching: .any)["recipePaint-6755"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["recipePaint-2407"].firstMatch.exists)
        app.buttons["closeSavedMixingRecipeButton"].click()
        waitUntilGone(series)
        app.buttons["aiMixingButton"].firstMatch.click()
        let picker = app.popUpButtons["mixingPaintSetPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, "Fluid Acrylics 13 色")
        app.buttons["closeAIMixingButton"].click()
    }

    func testSwitchingIngredientKitClearsResultsAndRejectsOtherKit() throws {
        let app = launchApp(mixingResponse: try threeToneFixture())
        createRecipe("Kit selection project", in: app)
        app.buttons["aiMixingButton"].firstMatch.click()
        let generate = app.buttons["generateMixingButton"]
        revealBlendInput(generate, in: app)
        generate.click()
        XCTAssertTrue(app.buttons["mixingRole-base"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["saveAIMixingButton"].isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["recipePaint-6755"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["recipePaint-2380"].firstMatch.exists)

        let picker = app.popUpButtons["mixingPaintSetPicker"]
        revealBlendInput(picker, in: app, scrollDown: false)
        chooseMenuOption("Fluid Acrylics 13 色", picker: "mixingPaintSetPicker", in: app)
        XCTAssertFalse(app.buttons["mixingRole-base"].exists)
        XCTAssertFalse(app.buttons["saveAIMixingButton"].isEnabled)
        XCTAssertFalse(app.buttons["复制三色配方"].isEnabled)
        revealBlendInput(generate, in: app)
        generate.click()
        // The fixture still contains SoFlat codes: Fluid must reject them.
        XCTAssertTrue(app.staticTexts["mixingError"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["saveAIMixingButton"].isEnabled)

        revealBlendInput(picker, in: app, scrollDown: false)
        chooseMenuOption("SoFlat 12 色", picker: "mixingPaintSetPicker", in: app)
        XCTAssertFalse(app.staticTexts["mixingError"].exists)
        revealBlendInput(generate, in: app)
        generate.click()
        XCTAssertTrue(app.buttons["mixingRole-base"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["saveAIMixingButton"].isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["recipePaint-2380"].firstMatch.exists)
        app.buttons["closeAIMixingButton"].click()
    }

    private func revealPaintRow(_ row: XCUIElement, in scrollView: XCUIElement) {
        for _ in 0..<16 {
            if row.exists && row.isHittable { break }
            scrollView.scroll(byDeltaX: 0, deltaY: -200)
        }
        XCTAssertTrue(row.isHittable, row.debugDescription)
    }

    private func selectReference(_ code: String, in app: XCUIApplication) {
        let search = app.textFields["referencePaintSearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        replaceText(in: search, with: code)
        let paint = app.buttons["referencePaint-\(code)"]
        XCTAssertTrue(paint.waitForExistence(timeout: 5))
        paint.click()
        XCTAssertTrue(app.staticTexts["selectedReferencePaint"].exists)
    }

    private func chooseMenuOption(_ option: String, picker: String, in app: XCUIApplication) {
        let control = app.popUpButtons[picker]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        app.activate()
        control.click()
        let item = app.menuItems[option]
        // A restored macOS window can consume the first click while becoming active.
        if !item.waitForExistence(timeout: 2) { control.click() }
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
    }

    func testBrandBlendH1AndH2CanBeGeneratedSavedAndViewed() throws {
        let app = launchApp(blendResponse: try blendFixture())
        createRecipe("H1 H2 blend project", in: app)
        openBlendEditor(in: app)
        let generate = app.buttons["generateMixingButton"]
        for (index, code, name, percentage) in [(0, "H1", "白色", "30"), (1, "H2", "黑色", "70")] {
            let modeID = "blendInputMode-\(index)"
            revealBlendInput(app.popUpButtons[modeID], in: app)
            chooseMenuOption("品牌标准色", picker: modeID, in: app)
            XCTAssertFalse(generate.isEnabled)
            let brandID = "blend\(index)PaintBrandPicker"
            revealBlendInput(app.popUpButtons[brandID], in: app)
            chooseMenuOption("郡士 Mr.Hobby", picker: brandID, in: app)
            let seriesID = "blend\(index)PaintSeriesPicker"
            revealBlendInput(app.popUpButtons[seriesID], in: app)
            chooseMenuOption("水性 Hobby Color · H", picker: seriesID, in: app)
            let search = app.textFields["blendPaintSearchField-\(index)"]
            revealBlendInput(search, in: app)
            replaceText(in: search, with: code)
            let codeID = "blendPaintCodePicker-\(index)"
            revealBlendInput(app.popUpButtons[codeID], in: app)
            chooseMenuOption("\(code) · \(name)", picker: codeID, in: app)
            XCTAssertTrue((app.staticTexts["blendSelectedReference-\(index)"].value as? String)?.contains("#\(code)") == true)
            let percentageField = app.textFields["blendPercentageField-\(index)"]
            revealBlendInput(percentageField, in: app)
            replaceText(in: percentageField, with: percentage)
        }
        XCTAssertTrue(generate.isEnabled)
        XCTAssertEqual(app.staticTexts["blendPercentageStatus"].value as? String, "占比合计 100% · 按相对比例换算为 100%")
        revealBlendInput(generate, in: app)
        generate.click()
        let target = app.staticTexts["blendTargetRGB"]
        XCTAssertTrue(target.waitForExistence(timeout: 10), app.sheets.debugDescription)
        XCTAssertEqual(target.value as? String, "RGB 128, 160, 128")

        // Switching the source paint system must invalidate the generated result and clear its old code.
        let seriesID = "blend0PaintSeriesPicker"
        revealBlendInput(app.popUpButtons[seriesID], in: app, scrollDown: false)
        chooseMenuOption("Mr.Color 溶剂型漆 · C", picker: seriesID, in: app)
        XCTAssertFalse(target.exists)
        XCTAssertFalse(generate.isEnabled)
        XCTAssertFalse(app.buttons["saveAIMixingButton"].isEnabled)
        XCTAssertFalse(app.staticTexts["blendSelectedReference-0"].exists)
        chooseMenuOption("水性 Hobby Color · H", picker: seriesID, in: app)
        let codeID = "blendPaintCodePicker-0"
        revealBlendInput(app.popUpButtons[codeID], in: app)
        chooseMenuOption("H1 · 白色", picker: codeID, in: app)
        revealBlendInput(generate, in: app)
        generate.click()
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["savedReferencePaint"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["recipePaint-H1"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["recipePaint-H2"].firstMatch.exists)
        app.buttons["saveAIMixingButton"].click()
        waitUntilGone(generate)

        for role in ["本色", "阴影色", "高光色"] {
            app.buttons["查看\(role)配方"].firstMatch.click()
            XCTAssertTrue(target.waitForExistence(timeout: 5))
            for (index, code, percentage) in [(0, "H1", "30"), (1, "H2", "70")] {
                let source = app.staticTexts["blendSourceSummary-\(index)"]
                XCTAssertTrue(source.exists)
                let summary = source.value as? String ?? ""
                XCTAssertTrue(summary.contains("郡士 Mr.Hobby"))
                XCTAssertTrue(summary.contains("水性 Hobby Color · H"))
                XCTAssertTrue(summary.contains("#\(code)"))
                XCTAssertTrue(summary.contains("\(percentage)%"))
            }
            XCTAssertEqual(app.staticTexts["savedMixingPaintSeries"].value as? String, "调色用漆：GOLDEN SoFlat")
            XCTAssertEqual(app.staticTexts["mixingTotal"].value as? String, "合计 200 滴")
            XCTAssertTrue(app.descendants(matching: .any)["recipePaint-6755"].firstMatch.exists)
            app.buttons["closeSavedMixingRecipeButton"].click()
            waitUntilGone(target)
        }
    }

    private func openBlendEditor(in app: XCUIApplication) {
        app.buttons["aiMixingButton"].firstMatch.click()
        let mode = app.radioButtons["多色合成"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5), app.sheets.debugDescription)
        mode.click()
        XCTAssertTrue(app.textFields["blendRField-0"].waitForExistence(timeout: 5))
    }

    private func revealBlendInput(_ element: XCUIElement, in app: XCUIApplication, scrollDown: Bool = true) {
        let scrollView = app.scrollViews["mixingInputScrollView"]
        // macOS can report a clipped button as hittable while its center sits behind the sheet footer.
        func isVisible() -> Bool {
            guard element.exists, element.isHittable else { return false }
            let viewport = scrollView.frame.insetBy(dx: 0, dy: 8)
            return element.frame.minY >= viewport.minY && element.frame.maxY <= viewport.maxY
        }
        for _ in 0..<8 {
            if isVisible() { break }
            scrollView.scroll(byDeltaX: 0, deltaY: scrollDown ? -140 : 140)
        }
        XCTAssertTrue(isVisible(), element.debugDescription)
    }

    private func blendFixture(whiteCode: String = "6755", blackCode: String = "6745") throws -> String {
        let palette = try JSONSerialization.jsonObject(with: Data(threeToneFixture(whiteCode: whiteCode, blackCode: blackCode).utf8))
        return String(decoding: try JSONSerialization.data(withJSONObject: [
            "synthesis": [
                "target": ["red": 128, "green": 160, "blue": 128],
                "explanation": "AI 按输入颜色及比例合成的测试结果。"
            ],
            "palette": palette
        ]), as: UTF8.self)
    }

    private func threeToneFixture(whiteCode: String = "6755", blackCode: String = "6745") throws -> String {
        let isGolden = ["6755", "2380"].contains(whiteCode)
        let codes: [String]
        switch whiteCode {
        case "6755":
            codes = ["6755", "6745", "6660", "6610", "6505", "6550", "6645", "6510", "6570", "6530", "6595", "6675"]
        case "2380":
            codes = ["2009", "2008", "2210", "2305", "2260", "2255", "2270", "2275", "2040", "2380", "2276", "2150", "2407"]
        default:
            codes = [whiteCode, blackCode]
        }
        func recipe(_ name: String, white: Int) -> [String: Any] {
            let ingredients: [[String: Any]] = codes.map {
                ["paintCode": $0, "drops": $0 == whiteCode ? white : ($0 == blackCode ? 200 - white : 0)]
            }.filter { isGolden || ($0["drops"] as? Int ?? 0) > 0 }
            let steps: [[String: Any]] = ingredients.compactMap { ingredient in
                guard let drops = ingredient["drops"] as? Int, drops > 0 else { return nil }
                return [
                    "paintCode": ingredient["paintCode"] ?? "",
                    "drops": drops,
                    "instruction": "加入颜料并充分搅匀。"
                ]
            }
            return ["name": name, "ingredients": ingredients, "steps": steps, "notes": "界面验证用配方。"]
        }
        let object: [String: Any] = [
            "base": recipe("UI 本色", white: 199),
            "shadow": [
                "target": ["red": 64, "green": 80, "blue": 64],
                "recipe": recipe("UI 阴影色", white: 100)
            ],
            "highlight": [
                "target": ["red": 220, "green": 235, "blue": 220],
                "recipe": recipe("UI 高光色", white: 200)
            ]
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private func launchApp(mixingResponse: String? = nil, blendResponse: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        // Use an in-memory library so UI automation cannot modify real recipes.
        app.launchArguments = ["--ui-testing"]
        if let mixingResponse {
            app.launchEnvironment["GOLDEN_UI_MIXING_RESPONSE"] = mixingResponse
        }
        if let blendResponse {
            app.launchEnvironment["GOLDEN_UI_BLEND_RESPONSE"] = blendResponse
        }
        app.launch()
        // macOS can restore a previous run with all windows closed; use the app's New Window command.
        if !app.windows.firstMatch.waitForExistence(timeout: 3) {
            app.typeKey("n", modifierFlags: [.command])
        }
        XCTAssertTrue(app.buttons["newRecipeButton"].firstMatch.waitForExistence(timeout: 5), app.windows.debugDescription)
        return app
    }

    private func createRecipe(_ name: String, in app: XCUIApplication) {
        app.activate()
        app.buttons["newRecipeButton"].firstMatch.click()
        let field = app.textFields["recipeNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText(name)
        app.buttons["saveRecipeButton"].click()
        waitUntilGone(field)
        XCTAssertTrue(app.staticTexts[name].firstMatch.waitForExistence(timeout: 5))
    }

    private func generatePalette(in app: XCUIApplication) {
        app.activate()
        app.buttons["aiMixingButton"].firstMatch.click()
        let generateButton = app.buttons["generateMixingButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 5))
        generateButton.click()
        XCTAssertTrue(app.buttons["mixingRole-base"].waitForExistence(timeout: 10))
        app.buttons["saveAIMixingButton"].click()
        waitUntilGone(generateButton)
        XCTAssertTrue(app.buttons["编辑颜色：本色 · UI 本色"].waitForExistence(timeout: 5))
    }

    private func selectRecipe(_ name: String, in app: XCUIApplication) {
        app.activate()
        let row = app.outlines.outlineRows.containing(.staticText, identifier: name).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        // Use the leading edge that remains exposed beside a floating editor.
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        field.click()
        field.typeKey("a", modifierFlags: [.command])
        field.typeText(text)
    }

    private func waitUntilGone(_ element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }
}
