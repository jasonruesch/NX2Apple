import Foundation
import Testing
@testable import ShellHost

/// Game frameworks beside the game data: found, checked for the app's team, staged once, and listed by the catalogue.
@Suite struct DataFolderFrameworksTests {
    private let team = "TEAM123456"
    private let newID = "01007EF00011E000"

    /// A framework like the launcher's signed copy: manifest, launcher list, executable and, optionally, the seal and the
    /// external shaders marker. Only small placeholder files, never game data.
    @discardableResult
    private func writeFramework(in parent: URL, titleID: String = Fixtures.orbit, executable: String = "macho-placeholder",
                                seal: String? = "seal-1", externalShaders: Bool = true) throws -> URL {
        let folder = "DmGame\(titleID).framework"
        let fw = parent.appendingPathComponent(folder, isDirectory: true)
        let source = Fixtures.gamesURL.appendingPathComponent(Fixtures.orbit)
        let exeName = "DmGame\(titleID)"
        let manifest = try String(contentsOf: source.appendingPathComponent("game.manifest.json"), encoding: .utf8)
            .replacingOccurrences(of: Fixtures.orbit, with: titleID)
            .replacingOccurrences(of: "\"DmGame.framework\"", with: "\"\(folder)\"")
            .replacingOccurrences(of: "\"DmGame\"", with: "\"\(exeName)\"")
            .replacingOccurrences(of: "\"FR\"", with: "\"FH\"")
        let launcher = try String(contentsOf: source.appendingPathComponent("launcher.json"), encoding: .utf8)
            .replacingOccurrences(of: Fixtures.orbit, with: titleID)
        let fm = FileManager.default
        try fm.createDirectory(at: fw.appendingPathComponent("dm", isDirectory: true), withIntermediateDirectories: true)
        try Data(manifest.utf8).write(to: fw.appendingPathComponent("game.manifest.json"))
        try Data(launcher.utf8).write(to: fw.appendingPathComponent("dm/launcher.json"))
        try Data(executable.utf8).write(to: fw.appendingPathComponent(exeName))
        if let seal {
            try fm.createDirectory(at: fw.appendingPathComponent("_CodeSignature", isDirectory: true), withIntermediateDirectories: true)
            try Data(seal.utf8).write(to: fw.appendingPathComponent("_CodeSignature/CodeResources"))
        }
        if externalShaders {
            try Data(#"{"bytes":1,"files":1,"schema":1}"#.utf8).write(to: fw.appendingPathComponent(ExternalShaders.markerFile))
        }
        return fw
    }

    private func signedBy(_ team: String?) -> (URL) -> String? { { _ in team } }

    @Test func aNewGameBesideItsDataJoinsTheLibrary() throws {
        let box = try FrameworkBox()
        let hotRoot = box.documents.appendingPathComponent("Frameworks", isDirectory: true)
        let drive = box.root.appendingPathComponent("T7", isDirectory: true)
        let gameFolder = drive.appendingPathComponent("Games/Zelda (\(newID))", isDirectory: true)
        try writeFramework(in: gameFolder, titleID: newID)
        try Data("metadata".utf8).write(to: gameFolder.appendingPathComponent("DmGame\(newID).framework/._DmGame\(newID)"))

        #expect(DataFolderFrameworks.candidates(in: drive).map(\.lastPathComponent) == ["DmGame\(newID).framework"])
        let staged = DataFolderFrameworks.importAll(from: [drive], hotRoot: hotRoot, gamesRoot: box.frameworks,
                                                    hostTeam: team, teamOf: signedBy(team))
        #expect(staged == [newID])

        let entries = GameCatalogue.scan(root: box.frameworks, hotRoot: hotRoot)
        let entry = try #require(entries.first { $0.id == newID })
        #expect(entry.problem == nil)
        #expect(entry.requiresExternalShaders)
        #expect(entry.directory.deletingLastPathComponent().standardizedFileURL == hotRoot.standardizedFileURL)
        // macOS answers for `._<name>` itself when a file has extended attributes, so the folder listing is what counts
        #expect(!(FileManager.default.subpaths(atPath: entry.directory.path) ?? []).contains { $0.hasPrefix("._") })

        // The same framework is not copied in again at the next start
        #expect(DataFolderFrameworks.importAll(from: [drive], hotRoot: hotRoot, gamesRoot: box.frameworks,
                                               hostTeam: team, teamOf: signedBy(team)).isEmpty)
    }

    @Test func onlyAFrameworkSignedForTheAppsTeamIsCopied() throws {
        let box = try FrameworkBox()
        let hotRoot = box.documents.appendingPathComponent("Frameworks", isDirectory: true)
        let data = box.documents.appendingPathComponent("games", isDirectory: true)
        try writeFramework(in: data.appendingPathComponent(newID, isDirectory: true), titleID: newID)

        #expect(DataFolderFrameworks.importAll(from: [data], hotRoot: hotRoot, gamesRoot: box.frameworks,
                                               hostTeam: team, teamOf: signedBy("OTHERTEAM1")).isEmpty)
        #expect(DataFolderFrameworks.importAll(from: [data], hotRoot: hotRoot, gamesRoot: box.frameworks,
                                               hostTeam: team, teamOf: signedBy(nil)).isEmpty)
        // An app with no team (not signed for development) loads nothing from outside its bundle
        #expect(DataFolderFrameworks.importAll(from: [data], hotRoot: hotRoot, gamesRoot: box.frameworks,
                                               hostTeam: nil, teamOf: signedBy(team)).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: hotRoot.appendingPathComponent("DmGame\(newID).framework").path))
    }

    @Test func theBuildTheAppAlreadyHasIsNotCopiedButANewerOneIs() throws {
        let box = try FrameworkBox()
        let hotRoot = box.documents.appendingPathComponent("Frameworks", isDirectory: true)
        let data = box.root.appendingPathComponent("Data", isDirectory: true)
        try writeFramework(in: box.frameworks, titleID: Fixtures.orbit, seal: "seal-from-the-ipa", externalShaders: false)
        try writeFramework(in: data.appendingPathComponent(Fixtures.orbit, isDirectory: true), titleID: Fixtures.orbit)

        #expect(DataFolderFrameworks.importAll(from: [data], hotRoot: hotRoot, gamesRoot: box.frameworks,
                                               hostTeam: team, teamOf: signedBy(team)).isEmpty)

        // The game built again: another executable and another seal
        let rebuilt = data.appendingPathComponent(Fixtures.orbit, isDirectory: true)
        try FileManager.default.removeItem(at: rebuilt)
        try writeFramework(in: rebuilt, titleID: Fixtures.orbit, executable: "macho-placeholder-rebuilt", seal: "seal-2")
        #expect(DataFolderFrameworks.importAll(from: [data], hotRoot: hotRoot, gamesRoot: box.frameworks,
                                               hostTeam: team, teamOf: signedBy(team)) == [Fixtures.orbit])
        let entry = try #require(GameCatalogue.scan(root: box.frameworks, hotRoot: hotRoot).first { $0.id == Fixtures.orbit })
        #expect(entry.directory.deletingLastPathComponent().standardizedFileURL == hotRoot.standardizedFileURL)
    }

    @Test func theFirstFolderThatHoldsAGameWins() throws {
        let box = try FrameworkBox()
        let hotRoot = box.documents.appendingPathComponent("Frameworks", isDirectory: true)
        let drive = box.root.appendingPathComponent("Drive", isDirectory: true)
        let app = box.documents.appendingPathComponent("games", isDirectory: true)
        try writeFramework(in: drive.appendingPathComponent(newID, isDirectory: true), titleID: newID, executable: "from-the-drive")
        try writeFramework(in: app.appendingPathComponent(newID, isDirectory: true), titleID: newID, executable: "from-the-app-folder")

        #expect(DataFolderFrameworks.importAll(from: [drive, app], hotRoot: hotRoot, gamesRoot: box.frameworks,
                                               hostTeam: team, teamOf: signedBy(team)) == [newID])
        _ = GameCatalogue.scan(root: box.frameworks, hotRoot: hotRoot)
        let exe = hotRoot.appendingPathComponent("DmGame\(newID).framework/DmGame\(newID)")
        #expect(try String(contentsOf: exe, encoding: .utf8) == "from-the-drive")
    }
}
