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
}
