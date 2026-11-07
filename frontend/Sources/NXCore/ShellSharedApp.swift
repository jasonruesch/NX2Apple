import Foundation

// The shared app as a thing of its own (the iPhone app page): a game build only adds its game to shell.json, and the page makes the
// app once from every game in it, to install on a device or to export as an IPA. The pure parts (which games are newer than the
// app that was last made) are static functions with their own tests.

/// A game whose data goes over after the install: its title ID and the archive folder the build packed (romfs.img, add-on content).
package struct SharedGameData: Equatable {
    package var titleID: String
    package var archive: String

    package init(titleID: String, archive: String) { self.titleID = titleID; self.archive = archive }
}

extension ShellLibrary {
    /// Takes a game out of the shared app. Its framework stays where the build put it; the mirror's copy goes at the next sweep.
    package mutating func remove(titleID: String) {
        games.removeAll { $0.titleID.caseInsensitiveCompare(titleID) == .orderedSame }
    }
}

/// What the iPhone app page shows: the games in shell.json, when each was built, and whether each is newer than the shared app
/// that was last made (installed on a device, or exported as an IPA).
package struct SharedAppState: Equatable {
    package struct Game: Equatable, Identifiable {
        package var titleID: String
        package var name: String
        package var framework: String
        /// When the game's framework was written (its build), nil when the folder is gone.
        package var builtAt: Date?
        package var id: String { titleID }
    }

    package var games: [Game]
    /// The last install on a device and the last export, nil when there was none.
    package var installedAt: Date?
    package var exportedAt: Date?

    package init(games: [Game], installedAt: Date?, exportedAt: Date?) {
        self.games = games; self.installedAt = installedAt; self.exportedAt = exportedAt
    }

    /// Reads the shell folder: shell.json, each framework's date, the install receipt and the IPA.
    package static func read(root: String) -> SharedAppState {
        let fm = FileManager.default
        func date(_ path: String) -> Date? { (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date }
        let games = ShellLibrary.load(root: root).games.map {
            Game(titleID: $0.titleID, name: $0.name, framework: $0.framework, builtAt: date($0.framework))
        }
        return SharedAppState(games: games, installedAt: ShellLibrary.installedAt(root: root), exportedAt: date(ShellInstall.ipaPath(root: root)))
    }

    /// When the app the player makes next was last made: the install for a device, the IPA for an export.
    package func lastMade(export: Bool) -> Date? { export ? exportedAt : installedAt }

    /// A game built after the app was last made (or any game, when it never was) is not in that app yet.
    package func isNew(_ game: Game, export: Bool) -> Bool {
        guard let made = lastMade(export: export) else { return true }
        guard let built = game.builtAt else { return false }
        return built > made
    }

    /// The games the app made last does not hold yet.
    package func newGames(export: Bool) -> [Game] { games.filter { isNew($0, export: export) } }
}

extension ShellInstaller {
    package static let addStageID = 1014

    /// A game build for the shared app ends here: the game joins shell.json (its framework mirrored, its banner placed). Nothing is
    /// built, signed, installed or exported: the iPhone app page makes the shared app.
    package func addToSharedApp(framework: String, titleID: String, name: String) -> Outcome {
        guard FileManager.default.fileExists(atPath: framework) else { return missingFramework(framework, name: name) }
        let stageName = t("shared.addStage")
        begin(Self.addStageID, stageName)
        let updated = updateLibrary(adding: .init(titleID: titleID, name: name, framework: framework))
        guard updated.library != nil else {
            let why = updated.failure ?? ""
            end(Self.addStageID, stageName, ok: false, detail: why)
            return Outcome(ok: false, message: fmt("shell.projectFailed", why))
        }
        end(Self.addStageID, stageName, ok: true)
        return Outcome(ok: true, message: ([fmt("shared.added", name)] + updated.notes).joined(separator: "\n"))
    }

    /// The games the shared app holds, made and installed on the device, then their game data (the iPhone app page).
    package func installShared(data: [SharedGameData]) -> Outcome { install(adding: nil, data: data) }
}
