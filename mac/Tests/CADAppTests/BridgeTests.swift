import XCTest
import AppKit
@testable import CADApp

final class BridgeTests: XCTestCase {
    // CADDY strip titles from EditScreen.swift. Update when a tool is added or renamed.
    private let caddyTitles: Set<String> = ["Look", "Move", "Cut", "Turn", "Lift", "Size", "Add"]

    func testMovesAreShortCleanAndUnique() {
        let moves = BridgeMove.all
        XCTAssertEqual(Set(moves.map(\.id)).count, moves.count, "duplicate id")
        for m in moves {
            XCTAssertEqual(m.steps.count, 3, "\(m.id) needs exactly 3 steps")
            for s in m.steps + [m.caddy, m.tinkercad] {
                XCTAssertFalse(s.contains("\u{2014}"), "em dash: \(s)")
                XCTAssertFalse(s.contains("\u{2013}"), "en dash: \(s)")
                XCTAssertFalse(s.contains(";"), "semicolon: \(s)")
            }
            for s in m.steps { XCTAssertLessThan(s.count, 90, "too long: \(s)") }
            XCTAssertNotNil(NSImage(systemSymbolName: m.symbol, accessibilityDescription: nil), "no SF Symbol \(m.symbol)")
        }
    }

    func testEveryCaddyNameIsARealTool() {
        // "import" is the export flow, not a strip tool.
        for m in BridgeMove.all where m.id != "import" {
            XCTAssertTrue(caddyTitles.contains(m.caddy), "\(m.id): no CADDY tool called \(m.caddy)")
        }
    }

    func testBridgeFolderIsBundled() {
        XCTAssertNotNil(Bundle.module.url(forResource: "README", withExtension: "txt", subdirectory: "Bridge"),
                        "Resources/Bridge did not reach the bundle. Check the .copy in Package.swift")
    }

    func testScreenshotsMatchIdsAndLoad() {
        let ids = Set(BridgeMove.all.map(\.id))
        let pngs = Bundle.module.urls(forResourcesWithExtension: "png", subdirectory: "Bridge") ?? []
        for url in pngs {
            let id = url.deletingPathExtension().lastPathComponent
            XCTAssertTrue(ids.contains(id), "\(url.lastPathComponent) matches no move id, so it never shows")
            XCTAssertNotNil(NSImage(contentsOf: url), "\(url.lastPathComponent) does not load")
        }
        // Missing files are fine: the card falls back to the symbol, checked above.
        XCTAssertNil(Bundle.module.url(forResource: "no-such-move", withExtension: "png", subdirectory: "Bridge"))
    }
}
