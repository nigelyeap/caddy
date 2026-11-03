import XCTest
@testable import CADApp

final class ScanFilesTests: XCTestCase {
    func url(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/\(name)") }

    func testTurntableFilesAreAcceptedAsMeshes() {
        for name in ["scan_001.txt", "scan.csv", "SCAN_001.TXT", "part.stl", "part.PLY"] {
            XCTAssertTrue(ScanFiles.accepts(url(name)), name)
            XCTAssertEqual(ScanFiles.source(url(name)), .mesh, name)
        }
    }

    func testVideosAndOtherFiles() {
        XCTAssertEqual(ScanFiles.source(url("walk.mov")), .video)
        XCTAssertFalse(ScanFiles.accepts(url("notes.docx")))
        XCTAssertFalse(ScanFiles.accepts(url("noextension")))
    }
}
