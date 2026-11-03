import XCTest
@testable import CADApp

final class CaddiyLinesTests: XCTestCase {
    func testEveryLineIsShortAndHasNoDashOrSemicolon() {
        for moment in CaddiyMoment.allCases {
            XCTAssertGreaterThanOrEqual(CaddiyLines.lines(moment).count, 2, "\(moment) needs two lines to rotate")
        }
        for entry in CaddiyLines.all {
            let line = entry.text
            XCTAssertFalse(line.contains("\u{2014}"), "em dash: \(line)")
            XCTAssertFalse(line.contains("\u{2013}"), "en dash: \(line)")
            XCTAssertFalse(line.contains(";"), "semicolon: \(line)")
            XCTAssertLessThanOrEqual(line.count, 60, "too long: \(line)")
        }
    }

    func testPickNeverRepeatsTheLastLine() {
        for moment in CaddiyMoment.allCases {
            var last: CaddiyLine?
            for _ in 0..<50 {
                let line = CaddiyLines.pick(moment, after: last)
                XCTAssertNotEqual(line, last)
                XCTAssertTrue(CaddiyLines.lines(moment).contains(line))
                last = line
            }
        }
    }

    @MainActor func testEveryPoseHasAnImageAndAtLeastEightAreUsed() {
        let poses = Set(CaddiyLines.all.map(\.pose))
        XCTAssertGreaterThanOrEqual(poses.count, 8, "Caddiy needs at least 8 poses across his lines")
        for pose in poses {
            XCTAssertNotNil(CaddiyView.image(pose), "no image for \(pose.rawValue)")
        }
    }
}
