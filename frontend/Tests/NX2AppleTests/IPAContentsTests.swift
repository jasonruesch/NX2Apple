import XCTest
@testable import NXCore

/// The export card's list of the IPA's games: shell.json's games against the last IPA, the build form's game, and a missing framework.
final class IPAContentsTests: IsolatedDefaultsTestCase {
    private let fm = FileManager.default
    private var root: String!

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("nspb-ipa-contents-" + UUID().uuidString).path
        try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try fm.removeItem(atPath: root) }

    /// A framework folder written at `date`, and its game in shell.json.
    private func game(_ titleID: String, _ name: String, built date: Date?, in library: inout ShellLibrary) throws {
        let framework = root + "/frameworks/\(titleID).framework"
        if let date {
            try fm.createDirectory(atPath: framework, withIntermediateDirectories: true)
            try fm.setAttributes([.modificationDate: date], ofItemAtPath: framework)
        }
        library.add(.init(titleID: titleID, name: name, framework: framework))
    }

    private func writeIPA(at date: Date) throws {
        let ipa = ShellInstall.ipaPath(root: root)
        try fm.createDirectory(atPath: (ipa as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        fm.createFile(atPath: ipa, contents: Data("ipa".utf8))
        try fm.setAttributes([.modificationDate: date], ofItemAtPath: ipa)
    }

    private let day = Date(timeIntervalSince1970: 1_800_000_000)

    func testWithoutAnIPAEveryBuiltGameIsNewAndAMissingOneIsLeftOut() throws {
        var library = ShellLibrary()
        try game("0100000000000A00", "Alpha", built: day, in: &library)
        try game("0100000000000B00", "Beta", built: nil, in: &library)
        try library.save(root: root)
        let contents = IPAContents.read(root: root)
        XCTAssertEqual(contents.games.map(\.tag), [.newSinceIPA, .missing])
        XCTAssertEqual(contents.games.first?.built, day)
        XCTAssertNil(contents.games.last?.built)
        XCTAssertEqual(contents.exportCount, 1, "the export drops a game whose framework is gone")
    }

    func testAGameBuiltBeforeTheIPAIsInItAndOneBuiltAfterIsNew() throws {
        var library = ShellLibrary()
        try game("0100000000000A00", "Alpha", built: day, in: &library)
        try game("0100000000000B00", "Beta", built: day.addingTimeInterval(7200), in: &library)
        try library.save(root: root)
        try writeIPA(at: day.addingTimeInterval(3600))
        let contents = IPAContents.read(root: root)
        XCTAssertEqual(contents.games.map(\.tag), [.inLastIPA, .newSinceIPA])
        XCTAssertEqual(contents.exportCount, 2)
        XCTAssertEqual(contents.buildCount, 2)
    }

    func testTheBuildFormsGameIsAddedOrRebuiltByBuildAndExportOnly() throws {
        var library = ShellLibrary()
        try game("0100000000000A00", "Alpha", built: day, in: &library)
        try library.save(root: root)
        try writeIPA(at: day.addingTimeInterval(3600))
        let added = IPAContents.read(root: root, building: (titleID: "0100000000000c00", name: "Gamma"))
        XCTAssertEqual(added.games.map(\.tag), [.inLastIPA, .addedByBuild])
        XCTAssertEqual(added.games.last?.name, "Gamma")
        XCTAssertEqual(added.exportCount, 1, "Export IPA does not build the form's game")
        XCTAssertEqual(added.buildCount, 2)
        let rebuilt = IPAContents.read(root: root, building: (titleID: "0100000000000a00", name: "Alpha"))
        XCTAssertEqual(rebuilt.games.map(\.tag), [.rebuiltByBuild], "the title ID matches in any case")
        XCTAssertEqual(rebuilt.exportCount, 1)
        XCTAssertEqual(rebuilt.buildCount, 1)
    }

    func testNamesAreShownWithoutADumpsTags() throws {
        var library = ShellLibrary()
        try game("010093801237C000", "Metroid Dread [010093801237C000][v0][Base]", built: day, in: &library)
        try game("01006A800016E000", "Super Smash Bros. Ultimate [01006A800016E000]+[v13.0.0+99DLC]", built: day, in: &library)
        try game("0100000000000C00", "[0100000000000C00]", built: day, in: &library)
        try library.save(root: root)
        XCTAssertEqual(IPAContents.read(root: root).games.map(\.name), ["Metroid Dread", "Super Smash Bros. Ultimate", "0100000000000C00"])
    }

    func testAnEmptySharedAppHasNoGames() {
        XCTAssertEqual(IPAContents.read(root: root).games, [])
        XCTAssertEqual(IPAContents.read(root: root, building: (titleID: "0100000000000A00", name: "Alpha")).buildCount, 1)
    }
}
