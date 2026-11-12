import Foundation
import NXCore

// The export card's game list as a place to manage the shared app (SharedAppGames): exclude a game from the IPA, or remove it.

extension BuildStore {
    /// The built games the IPA export packs: the built ones the player did not exclude.
    package func exportableShellGames() -> [ShellLibrary.Game] {
        let excluded = SharedAppGames.excluded(root: shellRoot)
        return builtShellGames().filter { !excluded.contains($0.titleID.uppercased()) }
    }

    /// Changing the games is refused while something runs: a build or an export reads shell.json and the frameworks.
    package var canManageShellGames: Bool { !running }

    /// Excludes a game from the next IPA, or includes it again. The game stays built and stays in the install on a device.
    package func setExcludedFromIPA(_ titleID: String, _ excluded: Bool) {
        guard canManageShellGames else { return }
        do {
            try SharedAppGames.setExcluded(titleID, excluded, root: shellRoot)
        } catch {
            say(String(format: t("shell.ipaGameChangeFailed"), error.localizedDescription))
        }
        objectWillChange.send()
    }

    /// Takes a game out of the shared app for good: shell.json and its framework copy. Building it again brings it back.
    package func removeFromSharedApp(_ titleID: String) {
        guard canManageShellGames else { return }
        do {
            try SharedAppGames.remove(titleID, root: shellRoot)
        } catch {
            say(String(format: t("shell.ipaGameChangeFailed"), error.localizedDescription))
        }
        objectWillChange.send()
    }
}
