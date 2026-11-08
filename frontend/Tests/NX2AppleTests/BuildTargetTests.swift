import XCTest
import Combine
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
    // ---- The iPhone statuses are read from the shell folder and the game data on disk, not recorded ----

    private let hades = "0100535012974000", crossing = "01006F8002326000"

    /// A shell folder with these games' frameworks in shell.json, each framework dated `built`.
    private func shell(_ titles: [String], built: Date) throws -> String {
        let root = temporary.appendingPathComponent("shell").path
        var library = ShellLibrary()
        for tid in titles {
            let framework = root + "/frameworks/DmGame\(tid).framework"
            try FileManager.default.createDirectory(atPath: framework, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.modificationDate: built], ofItemAtPath: framework)
            library.add(.init(titleID: tid, name: tid, framework: framework))
        }
        try library.save(root: root)
        return root
    }

    /// The packed game data where the archive step writes it: <output>/games/<title ID>/romfs.img.
    @discardableResult private func packed(_ titleID: String) throws -> String {
        let folder = temporary.appendingPathComponent("games/" + titleID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("image".utf8).write(to: folder.appendingPathComponent("romfs.img"))
        return folder.path
    }

    func testTheSharedAppStatusesAreReadFromTheShellFolder() throws {
        let hour = Date().addingTimeInterval(-3600)
        let root = try shell([hades, crossing], built: hour)
        try packed(hades)
        let built = LibraryGame(titleID: hades, name: "Hades", outputDirectory: temporary.path)
        let noData = LibraryGame(titleID: crossing, name: "Animal Crossing", outputDirectory: temporary.path)
        let outside = LibraryGame(titleID: "0100000000010000", name: "Not in it", outputDirectory: temporary.path)

        var state = SharedAppState.read(root: root)
        XCTAssertEqual(built.statusKey(state), "library.inSharedApp", "in shell.json, nothing made yet")
        XCTAssertEqual(noData.statusKey(state), "library.needsGameData", "its build folder is gone: nothing to play")
        XCTAssertEqual(outside.statusKey(state), "library.notBuilt")
        XCTAssertTrue(LibraryFilter.built.includes(built, shared: state))
        XCTAssertFalse(LibraryFilter.built.includes(outside, shared: state))

        let ipa = ShellInstall.ipaPath(root: root)
        try FileManager.default.createDirectory(atPath: (ipa as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data([0]).write(to: URL(fileURLWithPath: ipa))
        state = SharedAppState.read(root: root)
        XCTAssertEqual(built.statusKey(state), "library.exportedIPA", "the IPA is newer than its framework")
        XCTAssertEqual(noData.statusKey(state), "library.needsGameData", "in the IPA, but no data to send")

        // The game built again after the export: its new build is not in that IPA
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)],
                                              ofItemAtPath: state.game(hades)!.framework)
        XCTAssertEqual(built.statusKey(SharedAppState.read(root: root)), "library.inSharedApp")

        // Taken out of the shared app (the page's Remove): no record to clear, it is simply not there
        var library = ShellLibrary.load(root: root)
        library.remove(titleID: hades)
        try library.save(root: root)
        XCTAssertEqual(built.statusKey(SharedAppState.read(root: root)), "library.notBuilt")
    }

    /// An install is read from its receipt; the device it went to is the one thing the library keeps.
    func testAnInstallIsReadFromTheReceiptAndTheDeviceFromTheRecord() throws {
        let root = try shell([hades], built: Date().addingTimeInterval(-3600))
        try packed(hades)
        let app = try self.app(named: "DmShell.app", at: "shell/derived-data/Build/Products/Release-iphoneos")
        let game = LibraryGame(titleID: hades, name: "Hades", outputDirectory: temporary.path, iosAppPath: app.path, installedDevice: "UDID")
        XCTAssertEqual(game.statusKey(SharedAppState.read(root: root)), "library.inSharedApp", "no install receipt yet")
        _ = ShellLibrary.recordInstalled(root: root)
        let state = SharedAppState.read(root: root)
        XCTAssertTrue(state.isInstalled(hades))
        XCTAssertEqual(game.statusKey(state), "library.readyIOS")
        try FileManager.default.removeItem(at: temporary.appendingPathComponent("games/" + hades))
        XCTAssertEqual(game.statusKey(state), "library.readyIOS", "its data went over with the install: nothing is missing")
    }

    /// One game's own IPA is found where a one-game export writes it; another single IPA is an older build.
    func testAOneGameIPAIsReadFromItsFile() throws {
        let game = LibraryGame(titleID: hades, name: "Hades", outputDirectory: temporary.path)
        XCTAssertEqual(game.statusKey(.empty), "library.notBuilt")
        try Data([0]).write(to: URL(fileURLWithPath: OneGameIPA.path(folder: temporary.path, titleID: hades)))
        XCTAssertTrue(game.hasOneGameIPA)
        XCTAssertEqual(game.statusKey(.empty), "library.exportedIPA")
        XCTAssertFalse(game.isOlderIOSBuild)

        let older = temporary.appendingPathComponent("Hades.ipa")
        try Data([0]).write(to: older)
        let single = LibraryGame(titleID: crossing, name: "Animal Crossing", ipaPath: older.path, outputDirectory: temporary.path)
        XCTAssertEqual(single.statusKey(.empty), "library.olderIOS")
    }

    func testGameDataIsFoundWhereTheArchiveStepPacksItOrWhereItWasRecorded() throws {
        let game = LibraryGame(titleID: hades, name: "Hades", outputDirectory: temporary.path)
        XCTAssertEqual(game.gameDataPath, temporary.path + "/games/" + hades)
        XCTAssertFalse(game.hasGameData)
        try packed(hades)
        XCTAssertTrue(game.hasGameData)
        let elsewhere = temporary.appendingPathComponent("moved")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try Data("image".utf8).write(to: elsewhere.appendingPathComponent("romfs.img"))
        XCTAssertTrue(LibraryGame(titleID: crossing, name: "C", archivePath: elsewhere.path, outputDirectory: temporary.path).hasGameData)
        let onDrive = LibraryGame(titleID: crossing, name: "C", archivePath: "/Volumes/NoSuchDrive-\(UUID().uuidString)/games/x")
        XCTAssertTrue(onDrive.hasGameData, "a drive that is not connected may come back")
    }

    func testTheLibraryRefreshesItsSharedStateOnlyWhenItChanged() throws {
        let root = try shell([hades], built: Date().addingTimeInterval(-3600))
        let library = GameLibrary(file: temporary.appendingPathComponent("library.json"))
        var published = 0
        let token = library.$shared.dropFirst().sink { _ in published += 1 }
        library.refreshShared(root: root)
        library.refreshShared(root: root)
        withExtendedLifetime(token) {}
        XCTAssertEqual(published, 1, "the second read found nothing new")
        XCTAssertNotNil(library.shared.game(hades))
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
