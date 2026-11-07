import XCTest
import Combine
@testable import NX2Apple
@testable import NXCore
@testable import NXModel

/// The iPhone app page copies one game's data onto a drive or folder after an export, into `<folder>/<title ID>/`.
final class SharedDriveCopyTests: IsolatedDefaultsTestCase {
    private var temporary: URL!
    private let titleID = "0100535012974000"

    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent("shared-drive-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: temporary) }

    @MainActor func testAGamesDataGoesIntoItsOwnFolderOnTheDrive() throws {
        let fm = FileManager.default
        let root = temporary.appendingPathComponent("shell").path
        testDefaults.set(root, forKey: "shellRoot")
        let stores = LauncherStores(defaults: testDefaults); let model = stores.build
        let archive = temporary.appendingPathComponent("out/\(titleID)").path
        try fm.createDirectory(atPath: archive + "/aoc", withIntermediateDirectories: true)
        try Data("image".utf8).write(to: URL(fileURLWithPath: archive + "/romfs.img"))
        try Data("dlc".utf8).write(to: URL(fileURLWithPath: archive + "/aoc/1.img"))
        let drive = temporary.appendingPathComponent("drive").path
        try fm.createDirectory(atPath: drive, withIntermediateDirectories: true)
        stores.deviceStore.driveFolder = drive

        model.copySharedDataToDrive(titleID: titleID, archive: archive)
        XCTAssertFalse(model.running, "no IPA yet: nothing to copy for")

        let ipa = ShellInstall.ipaPath(root: root)
        try fm.createDirectory(atPath: (ipa as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data([0]).write(to: URL(fileURLWithPath: ipa))
        let copied = expectation(description: "Copied")
        let token = model.$send.filter { if case .copied = $0 { return true } else { return false } }.prefix(1).sink { _ in copied.fulfill() }
        model.copySharedDataToDrive(titleID: titleID, archive: archive)
        XCTAssertEqual(model.sharedJob, .send)
        wait(for: [copied], timeout: 20)
        withExtendedLifetime(token) {}
        XCTAssertEqual(model.send, .copied(folder: DriveCopy.destination(folder: drive, titleID: titleID)))
        XCTAssertEqual(try String(contentsOfFile: drive + "/\(titleID)/romfs.img"), "image")
        XCTAssertEqual(try String(contentsOfFile: drive + "/\(titleID)/aoc/1.img"), "dlc")
    }

    @MainActor func testAFolderThatIsGoneSaysSoInsteadOfCopying() throws {
        let root = temporary.appendingPathComponent("shell").path
        testDefaults.set(root, forKey: "shellRoot")
        let stores = LauncherStores(defaults: testDefaults); let model = stores.build
        let archive = temporary.appendingPathComponent("out/\(titleID)").path
        try FileManager.default.createDirectory(atPath: archive, withIntermediateDirectories: true)
        try Data("image".utf8).write(to: URL(fileURLWithPath: archive + "/romfs.img"))
        let ipa = ShellInstall.ipaPath(root: root)
        try FileManager.default.createDirectory(atPath: (ipa as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data([0]).write(to: URL(fileURLWithPath: ipa))
        stores.deviceStore.driveFolder = "/Volumes/NoSuchDrive-\(UUID().uuidString)"
        model.copySharedDataToDrive(titleID: titleID, archive: archive)
        XCTAssertFalse(model.running)
        guard case .failed = model.send else { return XCTFail("expected a refusal, got \(model.send)") }
    }
}
