import XCTest
@testable import NX2Apple
import NXCore
import NXModel

/// The drive copy's folder names: `<title ID>` by default, `<game name> (<title ID>)` when the player turns it on, and the game's
/// folder under the other naming taken over instead of copied a second time.
@MainActor final class DriveFolderNamesTests: IsolatedDefaultsTestCase {
    private let fm = FileManager.default
    private let titleID = "010093801237C000"
    private var temporary: URL!

    override func setUpWithError() throws {
        temporary = fm.temporaryDirectory.appendingPathComponent("nspb-drive-names-" + UUID().uuidString)
        try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
        // The store reads the shared app's library for the game's name and shaders: never this Mac's own
        testDefaults.set(path("shell"), forKey: "shellRoot")
    }

    override func tearDownWithError() throws { try fm.removeItem(at: temporary) }

    private func path(_ parts: String...) -> String { parts.reduce(temporary.path) { $0 + "/" + $1 } }

    private func write(_ file: String, _ text: String) throws {
        try fm.createDirectory(atPath: (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try text.write(toFile: file, atomically: true, encoding: .utf8)
    }

    func testTheNamedFolderIsTheGameNameAndTheTitleIDCleanedForAnyDrive() {
        XCTAssertEqual(DriveCopy.namedFolder(titleID: titleID, name: "Metroid Dread"), "Metroid Dread (010093801237C000)")
        // characters FAT32, exFAT and NTFS refuse become spaces, runs of spaces one
        XCTAssertEqual(DriveCopy.namedFolder(titleID: titleID, name: "Zelda: Tears / of \"the\" Kingdom?"),
                       "Zelda Tears of the Kingdom (010093801237C000)")
        // no leading or trailing space or dot (FAT and Windows drop a trailing dot)
        XCTAssertEqual(DriveCopy.namedFolder(titleID: titleID, name: "  ...Game.  "), "Game (010093801237C000)")
        XCTAssertEqual(DriveCopy.namedFolder(titleID: titleID, name: "Pokémon™ Violet"), "Pokémon™ Violet (010093801237C000)")
        // a dump's file name: its tags go, the folder names the title ID once
        XCTAssertEqual(DriveCopy.namedFolder(titleID: titleID, name: "Metroid Dread [010093801237C000][v0]"), "Metroid Dread (010093801237C000)")
        XCTAssertEqual(DriveCopy.namedFolder(titleID: titleID, name: "Metroid Dread (010093801237C000)"), "Metroid Dread (010093801237C000)")
        XCTAssertEqual(DriveCopy.namedFolder(titleID: titleID, name: "Splatoon 3 (Demo)"), "Splatoon 3 (Demo) (010093801237C000)")
        // a site's tag and the separator left before it go, a "+" inside the name stays
        XCTAssertEqual(DriveCopy.namedFolder(titleID: titleID, name: "Super Smash Bros. Ultimate + (nsw2u.xyz)"),
                       "Super Smash Bros. Ultimate (010093801237C000)")
        XCTAssertEqual(DriveCopy.namedFolder(titleID: titleID, name: "Super Mario 3D World + Bowser's Fury"),
                       "Super Mario 3D World + Bowser's Fury (010093801237C000)")
        // nothing left of the name: the title ID alone
        XCTAssertEqual(DriveCopy.namedFolder(titleID: titleID, name: "???"), titleID)
        XCTAssertEqual(DriveCopy.namedFolder(titleID: titleID, name: ""), titleID)
        let long = DriveCopy.namedFolder(titleID: titleID, name: String(repeating: "a", count: 400))
        XCTAssertEqual(long.count, DriveCopy.maxNameLength + " (010093801237C000)".count)
    }

    func testTheDestinationKeepsTheTitleIDUnlessTheFoldersAreNamed() {
        XCTAssertEqual(DriveCopy.destination(folder: "/Volumes/D", titleID: titleID, name: "Metroid Dread", named: false), "/Volumes/D/" + titleID)
        XCTAssertEqual(DriveCopy.destination(folder: "/Volumes/D", titleID: titleID, name: "Metroid Dread", named: true),
                       "/Volumes/D/Metroid Dread (010093801237C000)")
    }

    func testAFolderUnderTheOtherNamingIsRenamedInsteadOfCopiedAgain() throws {
        let drive = path("drive")
        try write(drive + "/" + titleID + "/romfs.img", "0123456789")
        let named = drive + "/Metroid Dread (010093801237C000)"
        // what the copy will find already there counts before the rename
        XCTAssertEqual(DriveCopy.existingFiles(folder: drive, titleID: titleID, name: "Metroid Dread", named: true), ["romfs.img": 10])
        XCTAssertEqual(try DriveCopy.prepareDestination(folder: drive, titleID: titleID, name: "Metroid Dread", named: true), named)
        XCTAssertFalse(fm.fileExists(atPath: drive + "/" + titleID))
        XCTAssertEqual(try String(contentsOfFile: named + "/romfs.img"), "0123456789")
        // and back to the title ID when the player turns the names off
        XCTAssertEqual(try DriveCopy.prepareDestination(folder: drive, titleID: titleID, name: "Metroid Dread", named: false), drive + "/" + titleID)
        XCTAssertFalse(fm.fileExists(atPath: named))
        XCTAssertEqual(try String(contentsOfFile: drive + "/" + titleID + "/romfs.img"), "0123456789")
    }

    func testAFolderThatIsAlreadyThereUnderTheChosenNameIsLeftAsItIs() throws {
        let drive = path("drive")
        try write(drive + "/" + titleID + "/romfs.img", "old")
        try write(drive + "/Metroid Dread (010093801237C000)/romfs.img", "new")
        XCTAssertNil(DriveCopy.otherFolder(folder: drive, titleID: titleID, name: "Metroid Dread", named: true))
        _ = try DriveCopy.prepareDestination(folder: drive, titleID: titleID, name: "Metroid Dread", named: true)
        XCTAssertEqual(try String(contentsOfFile: drive + "/" + titleID + "/romfs.img"), "old", "the other one is not touched")
        XCTAssertEqual(try String(contentsOfFile: drive + "/Metroid Dread (010093801237C000)/romfs.img"), "new")
    }

    func testTheNamedFoldersSettingIsOffUntilTurnedOnAndRemembered() {
        let devices = LauncherStores(defaults: testDefaults).deviceStore
        XCTAssertFalse(devices.driveNamedFolders)
        devices.driveNamedFolders = true
        XCTAssertTrue(LauncherStores(defaults: testDefaults).deviceStore.driveNamedFolders)
    }

    func testTheStoreCopiesIntoTheNamedFolderAndTakesOverTheTitleIDFolder() throws {
        let archive = path("out/games", titleID)
        try write(archive + "/romfs.img", "0123456789")
        try write(archive + "/aoc/1.img", "abcd")
        let drive = path("drive")
        try write(drive + "/" + titleID + "/romfs.img", "0123456789")   // a copy from before, under the title ID
        try ShellLibrary(games: [ShellLibrary.Game(titleID: titleID, name: "Metroid Dread", framework: path("shell/frameworks/DmGame\(titleID).framework"))])
            .save(root: path("shell"))
        let stores = LauncherStores(defaults: testDefaults); let model = stores.build
        model.archivePath = archive
        model.exportedIPAPath = path("export/NX2Apple.ipa")
        stores.deviceStore.driveFolder = drive
        stores.deviceStore.driveNamedFolders = true
        let name = model.driveGameName
        model.refreshDrive()
        XCTAssertEqual(model.drive?.needed, 4, "only the add-on content is missing: romfs.img is there under the title ID")
        let copied = expectation(description: "Copied")
        let token = model.$send.sink { if case .copied = $0 { copied.fulfill() } }
        model.copyToDrive()
        wait(for: [copied], timeout: 30)
        withExtendedLifetime(token) {}
        let named = drive + "/" + DriveCopy.namedFolder(titleID: titleID, name: name)
        XCTAssertEqual(try String(contentsOfFile: named + "/romfs.img"), "0123456789")
        XCTAssertEqual(try String(contentsOfFile: named + "/aoc/1.img"), "abcd")
        XCTAssertFalse(fm.fileExists(atPath: drive + "/" + titleID))
        if case .copied(let folder) = model.send { XCTAssertEqual(folder, named) } else { XCTFail("not copied") }
    }

    func testTheDriveCopyTakesTheGamesShadersAlongAndDropsAnOlderChain() throws {
        let archive = path("out/games", titleID), shell = path("shell"), framework = shell + "/frameworks/DmGame\(titleID).framework"
        try write(archive + "/romfs.img", "0123456789")
        try write(framework + "/msl/b-new.img", "library")
        try ShellLibrary(games: [ShellLibrary.Game(titleID: titleID, name: "Metroid Dread", framework: framework)]).save(root: shell)
        let drive = path("drive")
        try write(drive + "/" + titleID + "/msl/b-old.img", "an older chain")
        let stores = LauncherStores(defaults: testDefaults); let model = stores.build
        model.archivePath = archive
        model.exportedIPAPath = path("export/NX2Apple.ipa")
        stores.deviceStore.driveFolder = drive
        model.refreshDrive()
        XCTAssertEqual(model.drive?.needed, 10, "an IPA that holds the shaders: the copy leaves them out")
        stores.deviceStore.ipaWithoutShaders = true
        model.refreshDrive()
        XCTAssertEqual(model.drive?.needed, 17, "the space check counts the shaders before they are placed")
        let copied = expectation(description: "Copied")
        let token = model.$send.sink { if case .copied = $0 { copied.fulfill() } }
        model.copyToDrive()
        wait(for: [copied], timeout: 30)
        withExtendedLifetime(token) {}
        XCTAssertEqual(try String(contentsOfFile: archive + "/msl/b-new.img"), "library", "the game data folder holds them for the next copy too")
        XCTAssertEqual(try String(contentsOfFile: drive + "/" + titleID + "/msl/b-new.img"), "library")
        XCTAssertFalse(fm.fileExists(atPath: drive + "/" + titleID + "/msl/b-old.img"))
    }

    func testLeavingTheShadersOutIsOffUntilTurnedOnAndRemembered() {
        let devices = LauncherStores(defaults: testDefaults).deviceStore
        XCTAssertFalse(devices.ipaWithoutShaders)
        devices.ipaWithoutShaders = true
        XCTAssertTrue(LauncherStores(defaults: testDefaults).deviceStore.ipaWithoutShaders)
    }

    func testCopyAllSendsEveryGameWithPackedDataIntoItsOwnFolder() throws {
        let other = "0100000000010000"
        let first = path("out/games", titleID), second = path("out/games", other), shell = path("shell")
        try write(first + "/romfs.img", "0123456789")
        try write(second + "/romfs.img", "abcdef")
        try write(second + "/aoc/1.img", "dlc")
        let framework = shell + "/frameworks/DmGame\(other).framework"
        try write(framework + "/msl/b-new.img", "library")
        try ShellLibrary(games: [ShellLibrary.Game(titleID: titleID, name: "Metroid Dread", framework: shell + "/frameworks/DmGame\(titleID).framework"),
                                 ShellLibrary.Game(titleID: other, name: "Super Mario Odyssey", framework: framework)]).save(root: shell)
        let drive = path("drive")
        try write(drive + "/Metroid Dread (\(titleID))/romfs.img", "0123456789")   // already there: not copied again
        let stores = LauncherStores(defaults: testDefaults); let model = stores.build
        model.sharedAppDataSources = { [TransferSource(titleID: self.titleID, name: "Metroid Dread", archive: first),
                                        TransferSource(titleID: other, name: "Super Mario Odyssey", archive: second)] }
        XCTAssertFalse(model.canCopyAllToDrive, "no folder yet")
        stores.deviceStore.driveFolder = drive
        stores.deviceStore.driveNamedFolders = true
        stores.deviceStore.ipaWithoutShaders = true
        XCTAssertTrue(model.canCopyAllToDrive, "no build is needed")
        var totals: [Int64] = []
        let copied = expectation(description: "Copied")
        let token = model.$send.sink {
            if case .copying(_, let total) = $0, total > 0 { totals.append(total) }
            if case .copied = $0 { copied.fulfill() }
        }
        model.copyAllToDrive()
        wait(for: [copied], timeout: 30)
        withExtendedLifetime(token) {}
        XCTAssertEqual(Set(totals), [16], "one total for every game: what is missing, the shaders included")
        let odyssey = drive + "/Super Mario Odyssey (\(other))"
        XCTAssertEqual(try String(contentsOfFile: odyssey + "/romfs.img"), "abcdef")
        XCTAssertEqual(try String(contentsOfFile: odyssey + "/aoc/1.img"), "dlc")
        XCTAssertEqual(try String(contentsOfFile: odyssey + "/msl/b-new.img"), "library")
        XCTAssertFalse(fm.fileExists(atPath: drive + "/Metroid Dread (\(titleID))/msl"), "a framework without shaders sends none")
        XCTAssertFalse(model.running)
        XCTAssertEqual(model.driveCopyName, "")
    }

    func testCopyAllStopsBeforeWritingWhenTheDriveIsTooSmall() throws {
        let archive = path("out/games", titleID)
        try write(archive + "/romfs.img", "0123456789")
        let stores = LauncherStores(defaults: testDefaults); let model = stores.build
        model.sharedAppDataSources = { [TransferSource(titleID: self.titleID, name: "Metroid Dread", archive: archive)] }
        stores.deviceStore.driveFolder = "/dev"   // devfs: no free space and no room for a folder
        let checked = expectation(description: "Checked")
        let token = model.$running.dropFirst(2).sink { if !$0 { checked.fulfill() } }
        model.copyAllToDrive()
        wait(for: [checked], timeout: 30)
        withExtendedLifetime(token) {}
        XCTAssertEqual(model.send, .idle)
        XCTAssertNotNil(model.drive?.problem)
        XCTAssertFalse(fm.fileExists(atPath: "/dev/" + titleID))
    }
}
