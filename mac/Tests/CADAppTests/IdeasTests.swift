import AppKit
import XCTest
@testable import CADApp

final class IdeasTests: XCTestCase {
    func testEveryIdeaHasAGroupASymbolAndAShortLabel() {
        let groups = Ideas.groups + Ideas.moreGroups
        XCTAssertEqual(Set(Ideas.all.map(\.group)), Set(groups))
        XCTAssertEqual(Set(Ideas.all.map(\.label)).count, Ideas.all.count, "labels are ids, so they must be unique")
        XCTAssertEqual(Set(Ideas.all.map(\.short)).count, Ideas.all.count)
        for idea in Ideas.all {
            XCTAssertNotNil(NSImage(systemSymbolName: idea.symbol, accessibilityDescription: nil), idea.symbol)
            XCTAssertLessThanOrEqual(idea.short.count, 12, "\(idea.short) is too long for the two column grid")
        }
    }

    func testTheTutorialChipIsShownAndSends() throws {
        let taller = try XCTUnwrap(Ideas.all.first { $0.short == "Taller" })
        XCTAssertTrue(Ideas.groups.contains(taller.group))
        XCTAssertFalse(taller.fill)
    }
}
