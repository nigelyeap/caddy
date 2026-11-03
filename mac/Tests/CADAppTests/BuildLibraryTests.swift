import XCTest
@testable import CADApp

@MainActor final class BuildLibraryTests: XCTestCase {
    func testSaveListAndDelete() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("builds-\(UUID().uuidString)")
        let stl = FileManager.default.temporaryDirectory.appendingPathComponent("b-\(UUID().uuidString).stl")
        try Data("solid x\nendsolid x\n".utf8).write(to: stl)
        let lib = BuildLibrary(dir: dir)
        XCTAssertTrue(lib.items.isEmpty)
        let item = try lib.save(stl, name: "Taller; cup/1")
        XCTAssertEqual(item.name, "Taller cup1")
        XCTAssertEqual(BuildLibrary(dir: dir).items.map(\.name), ["Taller cup1"])
        lib.delete(item)
        XCTAssertTrue(lib.items.isEmpty)
    }
}
