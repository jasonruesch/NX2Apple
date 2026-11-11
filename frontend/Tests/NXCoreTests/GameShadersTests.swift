import Foundation
import XCTest
@testable import NXCore

final class GameShadersTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("game-shaders-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    private func write(_ relative: String, _ text: String) throws {
        let url = root.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ relative: String) -> String? {
        fm.contents(atPath: root.appendingPathComponent(relative).path).map { String(decoding: $0, as: UTF8.self) }
    }

    func testPlacingCopiesTheFrameworksShadersAndDropsAnOlderChain() throws {
        try write("fw/msl/b-new.img", "new library")
        try write("data/romfs.img", "romfs")
        try write("data/msl/b-old.img", "old library")
        let framework = root.appendingPathComponent("fw").path, data = root.appendingPathComponent("data").path
        XCTAssertEqual(try GameShaders.place(framework: framework, in: data), 1)
        XCTAssertEqual(read("data/msl/b-new.img"), "new library")
        XCTAssertNil(read("data/msl/b-old.img"))
        XCTAssertEqual(read("data/romfs.img"), "romfs")
        XCTAssertEqual(try GameShaders.place(framework: framework, in: data), 0, "a file of the same size stays")
        XCTAssertEqual(ShellInstall.localFiles(in: data).keys.sorted(), ["msl/b-new.img", "romfs.img"])
    }

    func testAFrameworkWithoutShadersChangesNothing() throws {
        try write("data/msl/b-old.img", "old library")
        try fm.createDirectory(at: root.appendingPathComponent("fw"), withIntermediateDirectories: true)
        XCTAssertEqual(try GameShaders.place(framework: root.appendingPathComponent("fw").path, in: root.appendingPathComponent("data").path), 0)
        XCTAssertEqual(read("data/msl/b-old.img"), "old library")
    }

    func testTheDataFilesCountTheShadersTheCopyWillPlace() throws {
        try write("fw/msl/b-new.img", "new library")
        try write("data/romfs.img", "romfs")
        try write("data/msl/b-old.img", "old library")
        let files = GameShaders.dataFiles(archive: root.appendingPathComponent("data").path, framework: root.appendingPathComponent("fw").path)
        XCTAssertEqual(files, ["romfs.img": 5, "msl/b-new.img": 11])
        XCTAssertEqual(GameShaders.dataFiles(archive: root.appendingPathComponent("data").path, framework: nil), ["romfs.img": 5])
    }

    func testTheDriveKeepsOnlyTheShadersTheCopySent() throws {
        try write("drive/game/msl/b-old.img", "old library")
        try write("drive/game/msl/b-new.img", "new library")
        try write("drive/game/romfs.img", "romfs")
        GameShaders.removeOthers(in: root.appendingPathComponent("drive/game").path, keeping: ["romfs.img": 5, "msl/b-new.img": 11])
        XCTAssertEqual(ShellInstall.localFiles(in: root.appendingPathComponent("drive/game").path).keys.sorted(), ["msl/b-new.img", "romfs.img"])
    }

    func testStrippingRemovesLooseAndPackedShadersAndLeavesTheMarker() throws {
        try write("fw/msl/b-new.img", "library")
        try write("fw/msl-\(UUID().uuidString).aar", "packed")
        try write("fw/game.manifest.json", "{}")
        let framework = root.appendingPathComponent("fw")
        XCTAssertTrue(try GameShaders.strip(framework: framework))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: framework.path).sorted(), ["game.manifest.json", GameShaders.externalMarker])
        XCTAssertFalse(try GameShaders.strip(framework: framework), "nothing left to strip")
    }
}
