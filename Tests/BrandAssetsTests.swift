import AppKit
import XCTest
@testable import PasteMemo

@MainActor
final class BrandAssetsTests: XCTestCase {
    func testLogoIconResolvesFromItsSemanticAsset() {
        XCTAssertEqual(BrandAssets.logoResourceName, "logo_icon")
        XCTAssertNotNil(BrandAssets.logoIcon)
    }

    func testMenuBarStateResourceMapping() {
        XCTAssertEqual(BrandAssets.resourceName(for: .normal), "menu_normal")
        XCTAssertEqual(BrandAssets.resourceName(for: .paused), "menu_paused")
        XCTAssertEqual(BrandAssets.resourceName(for: .relay), "menu_relay")
    }

    func testEveryMenuBarImageResolvesAtTemplateSize() {
        for state in MenuBarIconState.allCases {
            let image = BrandAssets.menuBarIcon(for: state)
            XCTAssertNotNil(image, "Missing image for \(state)")
            XCTAssertEqual(image?.size, NSSize(width: 18, height: 18))
            XCTAssertEqual(image?.isTemplate, true)
        }
    }
}
