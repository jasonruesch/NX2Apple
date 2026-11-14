import XCTest
@testable import NXCore

/// A game's packed data found in the drive folder when it is no longer on this Mac. Small placeholder files, never game data.
final class DriveDataSourceTests: XCTestCase {
    private var drive: String!
    private let fm = FileManager.default
    private let titleID = "010093801237C000"

    override func setUpWithError() throws {
        drive = fm.temporaryDirectory.appendingPathComponent("nspb-drive-source-" + UUID().uuidString).path
        try fm.createDirectory(atPath: drive, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(atPath: drive) }

    private func image(in folder: String) throws {
        try fm.createDirectory(atPath: drive + "/" + folder, withIntermediateDirectories: true)
        try "ROMFS".write(toFile: drive + "/" + folder + "/romfs.img", atomically: true, encoding: .utf8)
    }

    func testTheNamedOrTitleIDFolderWithAnImageIsTheData() throws {
        XCTAssertNil(DriveDataSource.folder(in: drive, titleID: titleID))
        try fm.createDirectory(atPath: drive + "/Metroid Dread (\(titleID))", withIntermediateDirectories: true)
        XCTAssertNil(DriveDataSource.folder(in: drive, titleID: titleID), "a folder without romfs.img is not the data")
        try image(in: "Metroid Dread (\(titleID))")
        XCTAssertEqual(DriveDataSource.folder(in: drive, titleID: titleID.lowercased()), drive + "/Metroid Dread (\(titleID))")
        try image(in: titleID)
        XCTAssertEqual(DriveDataSource.folder(in: drive, titleID: titleID, named: false), drive + "/" + titleID)
        XCTAssertEqual(DriveDataSource.folder(in: drive, titleID: titleID, named: true), drive + "/Metroid Dread (\(titleID))")
    }

    func testOtherGamesAndAMissingDriveFindNothing() throws {
        try image(in: "Metroid Prime (01002A0012340000)")
        try image(in: "Not \(titleID) really")
        XCTAssertNil(DriveDataSource.folder(in: drive, titleID: titleID))
        XCTAssertNil(DriveDataSource.folder(in: drive + "/gone", titleID: titleID))
        XCTAssertNil(DriveDataSource.folder(in: "", titleID: titleID))
    }
}
