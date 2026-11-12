import Foundation
import XCTest
@testable import NXCore

final class SharedAppGamesTests: XCTestCase {
    private let fm = FileManager.default
    private var root: String!

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("shared-app-games-" + UUID().uuidString).path
        try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(atPath: root) }

    private func framework(_ path: String) throws -> String {
        try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: URL(fileURLWithPath: path + "/game.manifest.json"))
        return path
    }

    func testExclusionsAreKeptBesideShellJSONAndAnEmptyListLeavesNoFile() throws {
        XCTAssertEqual(SharedAppGames.excluded(root: root), [])
        try SharedAppGames.setExcluded("0100000000000a00", true, root: root)
        try SharedAppGames.setExcluded("0100000000000B00", true, root: root)
        XCTAssertEqual(SharedAppGames.excluded(root: root), ["0100000000000A00", "0100000000000B00"])
        XCTAssertTrue(SharedAppGames.isExcluded("0100000000000A00", root: root))
        try SharedAppGames.setExcluded("0100000000000A00", false, root: root)
        try SharedAppGames.setExcluded("0100000000000b00", false, root: root)
        XCTAssertFalse(fm.fileExists(atPath: SharedAppGames.exclusionsFile(root: root)))
        XCTAssertFalse(fm.fileExists(atPath: ShellLibrary.stateFile(root: root)), "shell.json is not touched")
    }

    func testTheExportLeavesOutExcludedGamesButNeverTheOneItWasHanded() {
        let library = ShellLibrary(games: [.init(titleID: "0100000000000A00", name: "A", framework: "/f/A"),
                                           .init(titleID: "0100000000000B00", name: "B", framework: "/f/B"),
                                           .init(titleID: "0100000000000C00", name: "C", framework: "/f/C")])
        let exported = SharedAppGames.forExport(library, leavingOut: ["0100000000000A00", "0100000000000B00"], keeping: "0100000000000b00")
        XCTAssertEqual(exported.games.map(\.titleID), ["0100000000000B00", "0100000000000C00"])
        XCTAssertEqual(exported.bundleID, library.bundleID)
    }

    func testRemovingTakesTheGameOutOfShellJSONAndDiscardsOnlyTheShellsOwnCopy() throws {
        let mirrored = try framework(ShellInstall.frameworksMirror(root: root) + "/DmGame0100000000000A00.framework")
        let buildFolder = try framework(root + "/../build-\(UUID().uuidString)/DmGame0100000000000B00.framework")
        defer { try? fm.removeItem(atPath: (buildFolder as NSString).deletingLastPathComponent) }
        try ShellLibrary(games: [.init(titleID: "0100000000000A00", name: "A", framework: mirrored),
                                 .init(titleID: "0100000000000B00", name: "B", framework: buildFolder),
                                 .init(titleID: "0100000000000C00", name: "C", framework: "/elsewhere")]).save(root: root)
        try SharedAppGames.setExcluded("0100000000000A00", true, root: root)

        XCTAssertTrue(try SharedAppGames.remove("0100000000000a00", root: root))
        XCTAssertEqual(ShellLibrary.load(root: root).games.map(\.titleID), ["0100000000000B00", "0100000000000C00"])
        XCTAssertFalse(fm.fileExists(atPath: mirrored))
        XCTAssertEqual(SharedAppGames.excluded(root: root), [], "a removed game is no longer excluded")

        XCTAssertTrue(try SharedAppGames.remove("0100000000000B00", root: root))
        XCTAssertTrue(fm.fileExists(atPath: buildFolder), "a build folder's framework belongs to the build")
        XCTAssertFalse(try SharedAppGames.remove("0100000000000B00", root: root))
    }
}
