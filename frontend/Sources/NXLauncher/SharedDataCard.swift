import SwiftUI
import NXCore
import NXModel

/// Step 3 of an export from the iPhone app page: each game's data into the shared app another tool installed, one game at a time,
/// over the install's own copy step. A copy the device refuses offers the Finder way. Observes the build store (the send) and the
/// device store (the device the data goes to).
package struct SharedDataCard: View {
    package struct Entry: Identifiable, Equatable {
        package var titleID: String
        package var name: String
        package var archive: String
        package var id: String { titleID }

        package init(titleID: String, name: String, archive: String) { self.titleID = titleID; self.name = name; self.archive = archive }
    }

    @ObservedObject var build: BuildStore
    @ObservedObject var devices: DeviceStore
    let games: [Entry]
    @EnvironmentObject var loc: Localizer

    package init(build: BuildStore, devices: DeviceStore, games: [Entry]) {
        self.build = build
        self.devices = devices
        self.games = games
    }

    package var body: some View {
        CardGroup(loc.t("shared.sendSection"), footnote: footnote) {
            ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                if index > 0 { CardDivider() }
                CardRow(game.name, detail: detail(game), dot: dot(game), help: game.archive) {
                    if game.archive.isEmpty {
                        EmptyView()
                    } else if toDrive {
                        if isCurrent(game), case .copying = build.send {
                            Button(loc.t("btn.stop")) { build.stopDriveCopy() }
                        } else {
                            Button(loc.t("shell.driveCopy")) { build.copySharedDataToDrive(titleID: game.titleID, archive: game.archive) }
                                .disabled(build.running || devices.driveFolder.isEmpty)
                        }
                    } else {
                        Button(loc.t("shell.sendButton")) { build.sendSharedData(titleID: game.titleID, archive: game.archive) }
                            .disabled(build.running || devices.installDevice.isEmpty)
                    }
                }
            }
            if case .chooseApp(let apps) = build.send {
                CardDivider()
                CardRow(loc.t("shell.sendSeveral")) {
                    ForEach(apps, id: \.bundle) { app in
                        Button(app.name.isEmpty ? app.bundle : app.name) {
                            build.sendSharedData(titleID: build.packedTitleID, archive: build.archivePath, bundle: app.bundle)
                        }
                    }
                }
            }
            if build.send.offersFinder {
                CardDivider()
                CardRow(loc.t("shell.sendFinder"), detail: String(format: loc.t("shell.sendFinderStep2"), build.packedTitleID)) {
                    Button(loc.t("install.reveal")) { build.copyWithFinder(oneGame: false) }
                }
            }
        }
    }

    private var toDrive: Bool { devices.sendWhere == SendWhere.drive }

    /// What the card's foot says: where the data goes, and what is still to choose.
    private var footnote: String {
        if toDrive {
            return devices.driveFolder.isEmpty ? loc.t("shared.driveNeedsFolder")
                : String(format: loc.t("shared.driveNote"), L10n.string("ios.ui.gameData", loc.lang))
        }
        return loc.t(devices.installDevice.isEmpty ? "shared.sendNeedsDevice" : "shared.sendNote")
    }

    /// The game whose data the last send was for.
    private func isCurrent(_ game: Entry) -> Bool {
        !build.archivePath.isEmpty && build.archivePath == game.archive
    }

    private func detail(_ game: Entry) -> String {
        guard !game.archive.isEmpty else { return loc.t("shared.noData") }
        guard isCurrent(game) else { return build.shortPath(game.archive) }
        switch build.send {
        case .sending(let done, let total, let note):
            return String(format: loc.t("shell.sendProgress"), game.name, ShellInstall.sizeText(done), ShellInstall.sizeText(total))
                + (note.isEmpty ? "" : " " + note)
        case .sent: return loc.t("shell.sendDone")
        case .appNotFound: return loc.t("shell.sendNoApp")
        case .refused: return loc.t("shell.sendRefused")
        case .failed(let why): return why
        case .chooseApp: return loc.t("shell.sendSeveral")
        case .copying(let done, let total):
            return String(format: loc.t("shell.driveProgress"), game.name, ShellInstall.sizeText(done), ShellInstall.sizeText(total))
        case .copied(let folder): return String(format: loc.t("shared.driveCopied"), build.shortPath(folder))
        default: return build.shortPath(game.archive)
        }
    }

    private func dot(_ game: Entry) -> Color? {
        guard isCurrent(game) else { return nil }
        switch build.send {
        case .sent: return LauncherPalette.ready
        case .sending, .copying: return LauncherPalette.building
        case .copied: return LauncherPalette.ready
        case .idle: return nil
        default: return LauncherPalette.building
        }
    }
}
