import Foundation

/// What the shared app's IPA will hold, for the export card's list: the games of shell.json, each with when its framework was built
/// and how it stands against the last IPA. Names are shown without a dump's tags (`DriveCopy.displayName`). It reads the same file and the same framework check as the export itself
/// (`ShellInstaller.export`: shell.json, the game it is handed added, `dropMissing`), so the list cannot disagree with the IPA.
package struct IPAContents: Equatable {
    package enum Tag: Equatable {
        /// Built before the current NX2Apple.ipa was made, so it is in it.
        case inLastIPA
        /// Built after the current IPA, or there is no IPA yet: only the next export holds it.
        case newSinceIPA
        /// The build form's game, not in the shared app yet: "Build and export" builds it and adds it.
        case addedByBuild
        /// The build form's game, already in the shared app: "Build and export" builds it again.
        case rebuiltByBuild
        /// In shell.json, but its framework is gone, so the export leaves it out.
        case missing
    }

    package struct Game: Equatable, Identifiable {
        package var titleID: String
        package var name: String
        /// When its framework was last written, nil when it is missing or not built yet.
        package var built: Date?
        package var tag: Tag
        package var id: String { titleID }

        package init(titleID: String, name: String, built: Date?, tag: Tag) {
            self.titleID = titleID; self.name = name; self.built = built; self.tag = tag
        }
    }

    package var games: [Game]

    /// The games "Export IPA" packs: every game whose framework is there. The build form's game counts only if it is built already.
    package var exportCount: Int { games.filter { $0.tag == .inLastIPA || $0.tag == .newSinceIPA || $0.tag == .rebuiltByBuild }.count }
    /// The games "Build and export" packs: the same, and the build form's game when it is new.
    package var buildCount: Int { exportCount + games.filter { $0.tag == .addedByBuild }.count }

    package init(games: [Game]) { self.games = games }

    /// The shared app at `root`, against its last IPA. `building` is the build form's game, which "Build and export" builds first.
    package static func read(root: String, building: (titleID: String, name: String)? = nil, fm: FileManager = .default) -> IPAContents {
        let library = ShellLibrary.load(root: root)
        let ipa = modified(ShellInstall.ipaPath(root: root), fm)
        func shown(_ name: String, _ titleID: String) -> String { let n = DriveCopy.displayName(name); return n.isEmpty ? titleID : n }
        var games: [Game] = library.games.map { game in
            let name = shown(game.name, game.titleID)
            guard fm.fileExists(atPath: game.framework) else { return Game(titleID: game.titleID, name: name, built: nil, tag: .missing) }
            let built = modified(game.framework, fm)
            let inIPA = ipa.map { ipaDate in built.map { $0 <= ipaDate } ?? false } ?? false
            var tag: Tag = inIPA ? .inLastIPA : .newSinceIPA
            if game.titleID.uppercased() == building?.titleID.uppercased() { tag = .rebuiltByBuild }
            return Game(titleID: game.titleID, name: name, built: built, tag: tag)
        }
        if let building, !games.contains(where: { $0.titleID.uppercased() == building.titleID.uppercased() }) {
            games.append(Game(titleID: building.titleID, name: shown(building.name, building.titleID), built: nil, tag: .addedByBuild))
        }
        return IPAContents(games: games)
    }

    private static func modified(_ path: String, _ fm: FileManager) -> Date? {
        (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}
