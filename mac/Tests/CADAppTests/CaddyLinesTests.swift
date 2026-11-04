import XCTest
@testable import CADApp

final class CaddyLinesTests: XCTestCase {
    func testEveryLineIsShortAndHasNoDashOrSemicolon() {
        for moment in CaddyMoment.allCases {
            XCTAssertGreaterThanOrEqual(CaddyLines.lines(moment).count, 2, "\(moment) needs two lines to rotate")
        }
        for entry in CaddyLines.all {
            let line = entry.text
            XCTAssertFalse(line.contains("\u{2014}"), "em dash: \(line)")
            XCTAssertFalse(line.contains("\u{2013}"), "en dash: \(line)")
            XCTAssertFalse(line.contains(";"), "semicolon: \(line)")
            XCTAssertLessThanOrEqual(line.count, 60, "too long: \(line)")
        }
    }

    func testPickNeverRepeatsTheLastLine() {
        for moment in CaddyMoment.allCases {
            var last: CaddyLine?
            for _ in 0..<50 {
                let line = CaddyLines.pick(moment, after: last)
                XCTAssertNotEqual(line, last)
                XCTAssertTrue(CaddyLines.lines(moment).contains(line))
                last = line
            }
        }
    }

    @MainActor func testEveryPoseHasAnImageAndAtLeastEightAreUsed() {
        let poses = Set(CaddyLines.all.map(\.pose))
        XCTAssertGreaterThanOrEqual(poses.count, 8, "Caddy needs at least 8 poses across his lines")
        for pose in poses {
            XCTAssertNotNil(CaddyView.image(pose), "no image for \(pose.rawValue)")
        }
    }
}

final class ToolKeyTests: XCTestCase {
    func testLetterPicksTool() {
        XCTAssertEqual(PartTool.forKey("m"), .move)
        XCTAssertEqual(PartTool.forKey("M"), .move)
        XCTAssertEqual(PartTool.forKey("t"), .turn)
        XCTAssertNil(PartTool.forKey("x"))
        XCTAssertNil(PartTool.forKey(nil))
    }
}
