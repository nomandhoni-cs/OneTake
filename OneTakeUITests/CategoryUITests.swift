//
//  CategoryUITests.swift
//  OneTakeUITests
//
//  End-to-end flow for script categories: create a script, create a
//  category from the editor, verify the filter chip appears, and clean up.
//

import XCTest

final class CategoryUITests: XCTestCase {
    @MainActor
    func testCreateCategoryFromEditorAndFilterLibrary() {
        let app = XCUIApplication()
        app.launch()

        // 1. Go to the Scripts tab.
        let scriptsTab = app.buttons["Scripts"]
        XCTAssertTrue(scriptsTab.waitForExistence(timeout: 10))
        scriptsTab.tap()

        // 2. Create a new script.
        let addScript = app.buttons["Add Script"]
        XCTAssertTrue(addScript.waitForExistence(timeout: 10))
        addScript.tap()

        // 3. Give it a title.
        let titleField = app.textFields["Script title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10))
        titleField.tap()
        titleField.typeText("CategoryUITest Script")

        // 4. Open the category menu and create a category.
        let chooseCategory = app.buttons["Choose category"]
        XCTAssertTrue(chooseCategory.waitForExistence(timeout: 10))
        chooseCategory.tap()

        let newCategory = app.buttons["New Category…"]
        XCTAssertTrue(newCategory.waitForExistence(timeout: 5))
        newCategory.tap()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.typeText("UITest Category")

        let create = app.buttons["Create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()

        // 5. Save the script.
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()

        // 6. Library should show the category chip bar.
        let chip = app.buttons["Filter by UITest Category"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "Category filter chip should appear in the library")

        // 7. Tapping the chip filters the list to that category.
        chip.tap()
        XCTAssertTrue(app.staticTexts["CategoryUITest Script"].waitForExistence(timeout: 5))
    }
}
