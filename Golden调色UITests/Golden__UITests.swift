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
        app.popUpButtons["aiReasoningPicker"].click()
        app.menuItems["低 · low"].click()
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

    private func openBlendEditor(in app: XCUIApplication) {
        app.buttons["aiMixingButton"].firstMatch.click()
        let mode = app.radioButtons["多色合成"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5), app.sheets.debugDescription)
        mode.click()
        XCTAssertTrue(app.textFields["blendRField-0"].waitForExistence(timeout: 5))
    }

    private func revealBlendInput(_ element: XCUIElement, in app: XCUIApplication, scrollDown: Bool = true) {
        let scrollView = app.scrollViews["mixingInputScrollView"]
        for _ in 0..<8 {
            if element.exists && element.isHittable { break }
            scrollView.scroll(byDeltaX: 0, deltaY: scrollDown ? -140 : 140)
        }
        XCTAssertTrue(element.isHittable)
    }

    private func blendFixture() throws -> String {
        let palette = try JSONSerialization.jsonObject(with: Data(threeToneFixture().utf8))
        return String(decoding: try JSONSerialization.data(withJSONObject: [
            "synthesis": [
                "target": ["red": 128, "green": 160, "blue": 128],
                "explanation": "AI 按输入颜色及比例合成的测试结果。"
            ],
            "palette": palette
        ]), as: UTF8.self)
    }

    private func threeToneFixture() throws -> String {
        let codes = ["6755", "6745", "6660", "6610", "6505", "6550", "6645", "6510", "6570", "6530", "6595", "6675"]
        func recipe(_ name: String, white: Int) -> [String: Any] {
            let ingredients: [[String: Any]] = codes.map {
                ["paintCode": $0, "drops": $0 == "6755" ? white : ($0 == "6745" ? 200 - white : 0)]
            }
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
