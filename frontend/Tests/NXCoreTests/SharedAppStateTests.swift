import XCTest
@testable import NXCore

/// The iPhone app page reads which games the shared app it made last holds: a game built after that install or export is new.
final class SharedAppStateTests: XCTestCase {
    private let early = Date(timeIntervalSince1970: 1_000), late = Date(timeIntervalSince1970: 2_000)

    private func game(_ tid: String, built: Date?) -> SharedAppState.Game {
        .init(titleID: tid, name: tid, framework: "/f/" + tid, builtAt: built)
    }

    func testEveryGameIsNewBeforeTheAppWasEverMade() {
        let state = SharedAppState(games: [game("A", built: early)], installedAt: nil, exportedAt: nil)
        XCTAssertNil(state.lastMade(export: true))
        XCTAssertEqual(state.newGames(export: true).map(\.titleID), ["A"])
        XCTAssertEqual(state.newGames(export: false).map(\.titleID), ["A"])
    }

    func testAGameBuiltAfterTheLastInstallOrExportIsNew() {
        let middle = Date(timeIntervalSince1970: 1_500)
        let state = SharedAppState(games: [game("A", built: early), game("B", built: late), game("C", built: nil)],
                                   installedAt: middle, exportedAt: late.addingTimeInterval(1))
        XCTAssertEqual(state.newGames(export: false).map(\.titleID), ["B"], "B was built after the install; C's files are gone")
        XCTAssertTrue(state.newGames(export: true).isEmpty, "the export came after every build")
    }

    func testReadingAShellFolderAndRemovingAGame() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shared-state-" + UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: root) }
        let framework = root + "/frameworks/DmGameA.framework"
        try FileManager.default.createDirectory(atPath: framework, withIntermediateDirectories: true)
        var library = ShellLibrary(games: [.init(titleID: "0100A", name: "A", framework: framework),
                                           .init(titleID: "0100B", name: "B", framework: root + "/gone")])
        try library.save(root: root)
        let state = SharedAppState.read(root: root)
        XCTAssertEqual(state.games.map(\.titleID), ["0100A", "0100B"])
        XCTAssertNotNil(state.games[0].builtAt)
        XCTAssertNil(state.games[1].builtAt)
        XCTAssertNil(state.installedAt)
        XCTAssertNil(state.exportedAt)
        library.remove(titleID: "0100a")
        XCTAssertEqual(library.games.map(\.titleID), ["0100B"], "the title ID matches in any case")
    }
}
