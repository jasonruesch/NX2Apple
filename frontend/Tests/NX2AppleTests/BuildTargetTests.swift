import XCTest
@testable import NX2Apple
@testable import NXCore
@testable import NXLauncher

/// The launcher builds for this Mac or for the one shared app on an iPhone or iPad. Settings and library files written
/// when one IPA per game was a target still load, and older single-IPA builds stay in the library.
final class BuildTargetTests: IsolatedDefaultsTestCase {
    private var temporary: URL!

    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent("nxnative-target-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporary)
    }

    func testAnyStoredValueButMacIsTheIPhoneTarget() {
        XCTAssertEqual(BuildTarget.normalized(nil), BuildTarget.ios)
        XCTAssertEqual(BuildTarget.normalized("ios"), BuildTarget.ios)
        XCTAssertEqual(BuildTarget.normalized("ios-shell"), BuildTarget.ios)
        XCTAssertEqual(BuildTarget.normalized("something else"), BuildTarget.ios)
        XCTAssertEqual(BuildTarget.normalized("mac-app"), BuildTarget.mac)
    }

    func testTheSavedChoiceIsMigratedAndStoredAgain() throws {
        let defaults = TestDefaults.make("nspb-target")
        XCTAssertEqual(BuildTarget.saved(defaults), BuildTarget.ios, "nothing stored yet")
        XCTAssertNil(defaults.string(forKey: "buildTarget"))
        defaults.set("ios-shell", forKey: "buildTarget")
        XCTAssertEqual(BuildTarget.saved(defaults), "ios")
        XCTAssertEqual(defaults.string(forKey: "buildTarget"), "ios")
        defaults.set("mac-app", forKey: "buildTarget")
        XCTAssertEqual(BuildTarget.saved(defaults), "mac-app")
        XCTAssertEqual(defaults.string(forKey: "buildTarget"), "mac-app")
    }

    func testALibraryGameKeepsOnlyTheTwoTargets() throws {
        let id = UUID()
        for (stored, expected) in [("ios-shell", "ios"), ("ios", "ios"), ("mac-app", "mac-app")] {
            let json = #"{"id":"\#(id.uuidString)","titleID":"0100535012974000","name":"Hades","lastTarget":"\#(stored)"}"#
            let game = try JSONDecoder().decode(LibraryGame.self, from: Data(json.utf8))
            XCTAssertEqual(game.lastTarget, expected, stored)
        }
        let none = try JSONDecoder().decode(LibraryGame.self, from: Data(#"{"id":"\#(id.uuidString)","titleID":"1","name":"H"}"#.utf8))
        XCTAssertEqual(none.lastTarget, "ios")
    }

    private func app(named name: String, at folder: String) throws -> URL {
        let url = temporary.appendingPathComponent(folder).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("plist".utf8).write(to: url.appendingPathComponent("Info.plist"))
        return url
    }

    func testASingleIPAOrAnAppOfItsOwnIsAnOlderBuildAndTheSharedAppIsNot() throws {
        let ipa = temporary.appendingPathComponent("Hades.ipa")
        try Data([0]).write(to: ipa)
        let single = LibraryGame(titleID: "0100535012974000", name: "Hades", ipaPath: ipa.path)
        XCTAssertTrue(single.hasIOSBuild)
        XCTAssertTrue(single.isOlderIOSBuild)
        XCTAssertEqual(single.primary, .build, "Build makes the game again for the shared app")

        let own = try app(named: "DmIOS.app", at: "0100_build/xcode-derived-data/Build/Products/Release-iphoneos")
        XCTAssertTrue(LibraryGame(titleID: "1", name: "H", iosAppPath: own.path, installedDevice: "UDID").isOlderIOSBuild)

        let shared = try app(named: "DmShell.app", at: "shell/derived-data/Build/Products/Release-iphoneos")
        let current = LibraryGame(titleID: "1", name: "H", iosAppPath: shared.path, installedDevice: "UDID")
        XCTAssertFalse(current.isOlderIOSBuild)
        XCTAssertFalse(LibraryGame(titleID: "1", name: "H").isOlderIOSBuild, "nothing built for iPhone")
    }

    func testABuildForTheSharedAppReplacesTheListedIPA() throws {
        let file = temporary.appendingPathComponent("library.json")
        let ipa = temporary.appendingPathComponent("Hades.ipa")
        try Data([0]).write(to: ipa)
        let game = LibraryGame(titleID: "0100535012974000", name: "Hades", ipaPath: ipa.path)
        try JSONEncoder().encode([game]).write(to: file)
        let library = GameLibrary(file: file)
        let shared = try app(named: "DmShell.app", at: "shell/derived-data/Build/Products/Release-iphoneos")
        library.recordCompletedIOS(archive: "", app: shared.path, device: "UDID", for: game.id)
        let stored = try XCTUnwrap(GameLibrary(file: file).games.first)
        XCTAssertEqual(stored.ipaPath, "")
        XCTAssertEqual(stored.iosAppPath, shared.path)
        XCTAssertFalse(stored.isOlderIOSBuild)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ipa.path), "the old file is not deleted")
        library.recordCompletedIOS(archive: "", app: temporary.path + "/none.app", for: game.id)
        XCTAssertEqual(GameLibrary(file: file).games.first?.iosAppPath, shared.path, "a build that made no app records nothing")
    }

    /// An export installs nothing, so the build used to record nothing and the game stayed "Not built yet".
    func testAnExportedSharedAppIsListedForEveryGameInIt() throws {
        let file = temporary.appendingPathComponent("library.json")
        let root = temporary.appendingPathComponent("shell").path
        let ipa = ShellInstall.ipaPath(root: root)
        try FileManager.default.createDirectory(atPath: (ipa as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data([0]).write(to: URL(fileURLWithPath: ipa))
        var shell = ShellLibrary()
        for tid in ["0100535012974000", "01006F8002326000"] {
            let framework = try app(named: "DmGame\(tid).framework", at: "frameworks")
            shell.add(.init(titleID: tid, name: tid, framework: framework.path))
        }
        try shell.save(root: root)
        let built = LibraryGame(titleID: "0100535012974000", name: "Hades")
        let other = LibraryGame(titleID: "01006F8002326000", name: "Animal Crossing")
        let installed = try app(named: "DmShell.app", at: "other/derived-data/Build/Products/Release-iphoneos")
        let onDevice = LibraryGame(titleID: "01006F8002326001", name: "On device", iosAppPath: installed.path, installedDevice: "UDID")
        let outside = LibraryGame(titleID: "0100000000010000", name: "Not in the shared app")
        try JSONEncoder().encode([built, other, onDevice, outside]).write(to: file)
        XCTAssertEqual(built.statusKey, "library.notBuilt")

        GameLibrary(file: file).recordExportedIPA(ipa, kind: .shared, archive: "/games/Hades/archive", shellRoot: root, commit: "abc", for: built.id)
        let games = Dictionary(uniqueKeysWithValues: GameLibrary(file: file).games.map { ($0.titleID, $0) })
        let stored = try XCTUnwrap(games[built.titleID])
        XCTAssertEqual(stored.ipaPath, ipa)
        XCTAssertEqual(stored.archivePath, "/games/Hades/archive")
        XCTAssertEqual(stored.toolsCommit, "abc")
        XCTAssertEqual(stored.statusKey, "library.exportedIPA")
        XCTAssertFalse(stored.isOlderIOSBuild, "an export is not a build from before the shared app")
        XCTAssertTrue(LibraryFilter.built.includes(stored), "the Built filter shows it")
        XCTAssertEqual(games[other.titleID]?.statusKey, "library.exportedIPA", "the shared IPA holds every game in shell.json")
        XCTAssertEqual(games[onDevice.titleID]?.statusKey, "library.readyIOS", "an installed shared app stays the status")
        XCTAssertEqual(games[outside.titleID]?.statusKey, "library.notBuilt")
    }

    func testAnExportedOneGameIPAIsNotAnOlderBuild() throws {
        let file = temporary.appendingPathComponent("library.json")
        let ipa = OneGameIPA.path(folder: temporary.path, titleID: "0100535012974000")
        try Data([0]).write(to: URL(fileURLWithPath: ipa))
        let game = LibraryGame(titleID: "0100535012974000", name: "Hades")
        try JSONEncoder().encode([game]).write(to: file)
        let library = GameLibrary(file: file)
        library.recordExportedIPA(ipa, kind: .oneGame, for: game.id)
        let stored = try XCTUnwrap(GameLibrary(file: file).games.first)
        XCTAssertEqual(stored.ipaKind, IPAKind.oneGame.rawValue)
        XCTAssertEqual(stored.statusKey, "library.exportedIPA")
        library.recordExportedIPA(temporary.path + "/none.ipa", kind: .oneGame, for: game.id)
        XCTAssertEqual(GameLibrary(file: file).games.first?.ipaPath, ipa, "an export that made no IPA records nothing")

        // An install of the shared app afterwards takes over, as it does for an older IPA
        let shared = try app(named: "DmShell.app", at: "shell/derived-data/Build/Products/Release-iphoneos")
        library.recordCompletedIOS(archive: "", app: shared.path, device: "UDID", for: game.id)
        let installed = try XCTUnwrap(GameLibrary(file: file).games.first)
        XCTAssertEqual(installed.ipaKind, "")
        XCTAssertEqual(installed.statusKey, "library.readyIOS")
    }

    /// An export made before the launcher recorded exports: the games in shell.json show it at start, when the IPA is newer than the list.
    func testAnExportFromBeforeTheFixIsFoundAtStart() throws {
        let file = temporary.appendingPathComponent("library.json")
        let root = temporary.appendingPathComponent("shell").path
        var shell = ShellLibrary()
        for tid in ["0100535012974000", "01006F8002326000"] {
            let framework = try app(named: "DmGame\(tid).framework", at: "frameworks")
            shell.add(.init(titleID: tid, name: tid, framework: framework.path))
        }
        try shell.save(root: root)
        let ipa = ShellInstall.ipaPath(root: root)
        try FileManager.default.createDirectory(atPath: (ipa as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data([0]).write(to: URL(fileURLWithPath: ipa))
        let own = OneGameIPA.path(folder: temporary.path, titleID: "01006F8002326000")
        try Data([0]).write(to: URL(fileURLWithPath: own))
        let hades = LibraryGame(titleID: "0100535012974000", name: "Hades")
        let crossing = LibraryGame(titleID: "01006F8002326000", name: "Animal Crossing", ipaPath: own, ipaKind: IPAKind.oneGame.rawValue)
        try JSONEncoder().encode([hades, crossing]).write(to: file)

        // shell.json written after the IPA (an install, or a game added since): the IPA does not hold this list
        let later = Date().addingTimeInterval(60)
        try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: ShellLibrary.stateFile(root: root))
        GameLibrary(file: file).syncExportedIPA(root: root)
        XCTAssertEqual(GameLibrary(file: file).games.first { $0.titleID == hades.titleID }?.statusKey, "library.notBuilt")

        try FileManager.default.setAttributes([.modificationDate: later.addingTimeInterval(60)], ofItemAtPath: ipa)
        GameLibrary(file: file).syncExportedIPA(root: root)
        let games = Dictionary(uniqueKeysWithValues: GameLibrary(file: file).games.map { ($0.titleID, $0) })
        XCTAssertEqual(games[hades.titleID]?.ipaPath, ipa)
        XCTAssertEqual(games[hades.titleID]?.statusKey, "library.exportedIPA")
        XCTAssertEqual(games[crossing.titleID]?.ipaPath, own, "a game's own IPA stays")
        GameLibrary(file: file).syncExportedIPA(root: temporary.appendingPathComponent("no-shell").path)   // no shell folder: nothing happens
    }

    /// A game build adds the game to the shared app; the page's install or export then lists it there, and removing it forgets both.
    func testAGameAddedToTheSharedAppWaitsUntilThePageMakesIt() throws {
        let file = temporary.appendingPathComponent("library.json")
        let root = temporary.appendingPathComponent("shell").path
        var shell = ShellLibrary()
        let framework = try app(named: "DmGame0100535012974000.framework", at: "frameworks")
        shell.add(.init(titleID: "0100535012974000", name: "Hades", framework: framework.path))
        try shell.save(root: root)
        let game = LibraryGame(titleID: "0100535012974000", name: "Hades")
        try JSONEncoder().encode([game]).write(to: file)
        let library = GameLibrary(file: file)

        library.recordAddedToSharedApp(archive: "/games/Hades/0100535012974000", commit: "abc", for: game.id)
        var stored = try XCTUnwrap(GameLibrary(file: file).games.first)
        XCTAssertTrue(stored.addedToSharedApp)
        XCTAssertEqual(stored.statusKey, "library.inSharedApp")
        XCTAssertEqual(stored.archivePath, "/games/Hades/0100535012974000")
        XCTAssertTrue(LibraryFilter.built.includes(stored))
        XCTAssertFalse(stored.isOlderIOSBuild)

        let ipa = ShellInstall.ipaPath(root: root)
        try FileManager.default.createDirectory(atPath: (ipa as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data([0]).write(to: URL(fileURLWithPath: ipa))
        library.recordSharedExport(ipa, shellRoot: root)
        stored = try XCTUnwrap(GameLibrary(file: file).games.first)
        XCTAssertFalse(stored.addedToSharedApp)
        XCTAssertEqual(stored.statusKey, "library.exportedIPA")

        library.recordRemovedFromSharedApp(titleID: "0100535012974000")
        stored = try XCTUnwrap(GameLibrary(file: file).games.first)
        XCTAssertEqual(stored.ipaPath, "")
        XCTAssertEqual(stored.statusKey, "library.notBuilt")
    }

    func testEveryLanguageNamesAnExportedIPA() {
        for lang in Lang.all { XCTAssertNotNil(L10n.catalogs[lang.code]?["library.exportedIPA"], lang.code) }
        XCTAssertEqual(L10n.string("library.exportedIPA", .en), "Exported as IPA")
    }

    func testEveryLanguageTellsAnOlderBuildAndTheTwoTargets() {
        for key in ["library.olderIOS", "dev.resignOlder", "build.ios", "build.iosNote"] {
            XCTAssertNotNil(L10n.table[key], key)
            XCTAssertNotNil(L10n.de[key], key)
        }
        for key in ["library.olderIOS", "build.iosNote"] { XCTAssertNotNil(L10n.sv[key], key) }
        XCTAssertEqual(L10n.string("build.ios", .en), "iPhone / iPad")
        XCTAssertEqual(L10n.string("build.iosNote", .de), "Eine App auf deinem iPhone oder iPad für alle deine Spiele.")
    }
}
