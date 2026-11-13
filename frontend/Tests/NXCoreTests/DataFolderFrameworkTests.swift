import XCTest
@testable import NXCore

/// The game's framework signed for the shared IPA's team and sent with its game data: made from the mirror without shaders, kept
/// until the game is built again, listed with the data files, and written again where a drive holds another signing. A stand-in
/// signs (it writes the seal codesign would), so no test needs a certificate.
final class DataFolderFrameworkTests: XCTestCase {
    private var root: String!
    private let fm = FileManager.default
    private let titleID = "0100535012974000"
    private let team = "TEAM123456"

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("nspb-data-fw-" + UUID().uuidString).path
        try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(atPath: root) }

    private func write(_ file: String, _ text: String) throws {
        try fm.createDirectory(atPath: (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try text.write(toFile: file, atomically: true, encoding: .utf8)
    }

    /// The mirror's framework with its executable, manifest and a small shader set; `loader` FH loads from outside the app.
    @discardableResult
    private func mirror(executable: String = "game-bin", loader: String = "FH") throws -> String {
        let fw = ShellInstall.mirroredFramework(root: root, titleID: titleID)
        try write(fw + "/DmGame\(titleID)", executable)
        try write(fw + "/game.manifest.json", #"{"loader":"\#(loader)","framework_executable":"DmGame\#(titleID)","title_id":"\#(titleID)"}"#)
        try write(fw + "/msl/b-chain/shaders.img", String(repeating: "S", count: 300))
        try write(fw + "/msl-\(UUID().uuidString).aar", "old archive")
        return fw
    }

    /// Stands in for xattr and codesign: codesign writes a seal naming the signing, as a real signature would change it.
    private final class Signer {
        var commands: [[String]] = []
        var seal = "seal-1"
        var status: Int32 = 0
        func run(_ command: [String]) -> Int32 {
            commands.append(command)
            if command.first?.hasSuffix("codesign") == true, status == 0, let target = command.last {
                try? FileManager.default.createDirectory(atPath: target + "/_CodeSignature", withIntermediateDirectories: true)
                try? seal.write(toFile: target + "/_CodeSignature/CodeResources", atomically: true, encoding: .utf8)
            }
            return status
        }
    }

    func testTheSignedCopyLeavesItsShadersBesideItAndIsMadeOnce() throws {
        let source = try mirror()
        let signer = Signer()
        XCTAssertNil(DataFolderFramework.prepare(root: root, titleID: titleID, team: team, identity: "Apple Development: X", sign: signer.run))
        let copy = DataFolderFramework.signedCopy(root: root, titleID: titleID)
        XCTAssertFalse(fm.fileExists(atPath: copy + "/msl"))
        XCTAssertFalse((try fm.contentsOfDirectory(atPath: copy)).contains { $0.hasSuffix(".aar") })
        let marker = try XCTUnwrap(fm.contents(atPath: copy + "/external-msl.json"))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: marker) as? [String: Int], ["schema": 1, "files": 1, "bytes": 300])
        XCTAssertTrue(signer.commands.contains { $0.first == "/usr/bin/codesign" && $0.contains("Apple Development: X") }, "\(signer.commands)")
        XCTAssertTrue(fm.fileExists(atPath: source + "/msl/b-chain/shaders.img"), "the mirror keeps its shaders")
        XCTAssertTrue(DataFolderFramework.isCurrent(root: root, titleID: titleID, team: team))

        // Unchanged: nothing is signed again. Another team or a new build: it is.
        signer.commands = []
        XCTAssertNil(DataFolderFramework.prepare(root: root, titleID: titleID, team: team, identity: "Apple Development: X", sign: signer.run))
        XCTAssertTrue(signer.commands.isEmpty)
        XCTAssertFalse(DataFolderFramework.isCurrent(root: root, titleID: titleID, team: "OTHERTEAM1"))
        try mirror(executable: "game-bin-built-again")
        XCTAssertFalse(DataFolderFramework.isCurrent(root: root, titleID: titleID, team: team))
    }

    func testAFailedSigningKeepsThePreviousCopy() throws {
        try mirror()
        let signer = Signer()
        XCTAssertNil(DataFolderFramework.prepare(root: root, titleID: titleID, team: team, identity: "id", sign: signer.run))
        try mirror(executable: "game-bin-built-again")
        signer.status = 1
        XCTAssertNotNil(DataFolderFramework.prepare(root: root, titleID: titleID, team: team, identity: "id", sign: signer.run))
        let copy = DataFolderFramework.signedCopy(root: root, titleID: titleID)
        XCTAssertEqual(try String(contentsOfFile: copy + "/DmGame\(titleID)", encoding: .utf8), "game-bin")
        XCTAssertFalse(DataFolderFramework.isCurrent(root: root, titleID: titleID, team: team))
        XCTAssertTrue(((try? fm.contentsOfDirectory(atPath: DataFolderFramework.folder(root: root))) ?? []).allSatisfy { !$0.hasPrefix(".work-") })
    }

    func testAFrameworkWithoutItsOwnHostIsNotSigned() throws {
        try mirror(loader: "FR")
        let signer = Signer()
        XCTAssertNotNil(DataFolderFramework.prepare(root: root, titleID: titleID, team: team, identity: "id", sign: signer.run))
        XCTAssertTrue(signer.commands.isEmpty)
    }

    func testTheGameDataListsTheCurrentCopyAndItsShaders() throws {
        let source = try mirror()
        let archive = root + "/games/\(titleID)"
        try write(archive + "/romfs.img", "ROMFS")
        let name = "DmGame\(titleID).framework"

        // No signed copy yet: only the archive (this game's shaders were not moved out of an IPA)
        var transfer = ShellInstall.transferSources(archive: archive, shellRoot: root, titleID: titleID, includeExternalMSL: true)
        XCTAssertEqual(Set(transfer.sizes.keys), ["romfs.img"])

        XCTAssertNil(DataFolderFramework.prepare(root: root, titleID: titleID, team: team, identity: "id", sign: Signer().run))
        transfer = ShellInstall.transferSources(archive: archive, shellRoot: root, titleID: titleID, includeExternalMSL: true)
        XCTAssertEqual(transfer.origins["\(name)/DmGame\(titleID)"], DataFolderFramework.signedCopy(root: root, titleID: titleID) + "/DmGame\(titleID)")
        XCTAssertNotNil(transfer.sizes["\(name)/_CodeSignature/CodeResources"])
        XCTAssertNotNil(transfer.sizes["\(name)/external-msl.json"])
        XCTAssertNil(transfer.sizes["\(name)/msl/b-chain/shaders.img"])
        XCTAssertEqual(transfer.origins["msl/b-chain/shaders.img"], source + "/msl/b-chain/shaders.img")

        // The install of the launcher's own app embeds the framework: nothing extra goes with its data
        let direct = ShellInstall.transferSources(archive: archive, shellRoot: root, titleID: titleID, includeExternalMSL: false)
        XCTAssertEqual(Set(direct.sizes.keys), ["romfs.img"])

        // Built again but not signed yet: the out-of-date copy does not go
        try mirror(executable: "game-bin-built-again")
        transfer = ShellInstall.transferSources(archive: archive, shellRoot: root, titleID: titleID, includeExternalMSL: true)
        XCTAssertNil(transfer.sizes["\(name)/DmGame\(titleID)"])
    }

    func testADriveWithAnotherSigningGetsTheFrameworkAgain() throws {
        try mirror()
        let signer = Signer()
        XCTAssertNil(DataFolderFramework.prepare(root: root, titleID: titleID, team: team, identity: "id", sign: signer.run))
        let archive = root + "/games/\(titleID)"
        try write(archive + "/romfs.img", "ROMFS")
        let drive = root + "/T7/\(titleID)"
        var transfer = ShellInstall.transferSources(archive: archive, shellRoot: root, titleID: titleID, includeExternalMSL: true)
        try DriveCopy.copy(archive: archive, files: transfer.sizes, origins: transfer.origins, to: drive, progress: { _, _ in })
        let name = "DmGame\(titleID).framework"
        var have = ShellInstall.localFiles(in: drive)
        XCTAssertEqual(DataFolderFramework.forgetChangedCopy(in: have, gameFolders: [drive], root: root, titleID: titleID), have)

        // Signed again with a seal of the same size: every size matches, the signature does not
        try mirror(executable: "game-bin-built-again")
        signer.seal = "seal-2"
        XCTAssertNil(DataFolderFramework.prepare(root: root, titleID: titleID, team: team, identity: "id", sign: signer.run))
        transfer = ShellInstall.transferSources(archive: archive, shellRoot: root, titleID: titleID, includeExternalMSL: true)
        have = ShellInstall.localFiles(in: drive)
        let forgotten = DataFolderFramework.forgetChangedCopy(in: have, gameFolders: [drive], root: root, titleID: titleID)
        XCTAssertFalse(forgotten.keys.contains { $0.hasPrefix(name) })
        XCTAssertEqual(forgotten["romfs.img"], have["romfs.img"])

        DataFolderFramework.removeChangedCopy(in: drive, root: root, titleID: titleID)
        try DriveCopy.copy(archive: archive, files: transfer.sizes, origins: transfer.origins, to: drive, progress: { _, _ in })
        XCTAssertEqual(try String(contentsOfFile: drive + "/\(name)/_CodeSignature/CodeResources", encoding: .utf8), "seal-2")
        XCTAssertEqual(try String(contentsOfFile: drive + "/\(name)/DmGame\(titleID)", encoding: .utf8), "game-bin-built-again")
    }

    func testNothingIsSignedWithoutATeamOrACertificate() throws {
        try mirror()
        var lines: [String] = []
        DataFolderFramework.prepareAll(titleIDs: [titleID], root: root, team: "", runner: FakeProcessRunner(), identity: { _, _ in "id" }) { lines.append($0) }
        XCTAssertTrue(lines.isEmpty)
        DataFolderFramework.prepareAll(titleIDs: [titleID], root: root, team: team, runner: FakeProcessRunner(), identity: { _, _ in nil }) { lines.append($0) }
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("no development certificate"), lines[0])
        XCTAssertFalse(fm.fileExists(atPath: DataFolderFramework.signedCopy(root: root, titleID: titleID)))
    }
}
