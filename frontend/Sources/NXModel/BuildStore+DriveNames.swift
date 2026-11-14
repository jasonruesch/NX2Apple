import Foundation
import NXCore

// The drive copy's named folders (DriveCopy.namedFolder): which folder a game's data goes to on the drive, and what it holds already.

extension BuildStore {
    /// The name a game's drive folder carries: the shared app's own name for it (shell.json), else the name the source gives.
    func driveName(for source: TransferSource, in library: ShellLibrary? = nil) -> String {
        (library ?? ShellLibrary.load(root: shellRoot)).games.first { $0.titleID.uppercased() == source.titleID.uppercased() }?.name ?? source.name
    }

    /// `<folder>/<title ID>`, or `<folder>/<game name> (<title ID>)` when the player chose named folders.
    func driveDestination(folder: String, source: TransferSource, in library: ShellLibrary? = nil) -> String {
        DriveCopy.destination(folder: folder, titleID: source.titleID, name: driveName(for: source, in: library), named: devices.driveNamedFolders)
    }

    /// What the drive holds of the game already: its folder, or its folder under the other naming that the copy will rename.
    func driveExistingFiles(folder: String, source: TransferSource, in library: ShellLibrary? = nil) -> [String: Int64] {
        DriveCopy.existingFiles(folder: folder, titleID: source.titleID, name: driveName(for: source, in: library), named: devices.driveNamedFolders)
    }
}
