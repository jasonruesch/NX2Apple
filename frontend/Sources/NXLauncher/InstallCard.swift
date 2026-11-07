import SwiftUI
import NXCore
import NXModel

/// What an iPhone game build makes: the game for the shared app (the iPhone app page installs or exports the app), or the game's
/// own IPA with its data inside ("One game, all inside", ExportSteps). Shown for the iPhone target only. Observes the device store
/// (the choice is kept there), and the build store for the target and whether a build runs.
package struct InstallCard: View {
    @ObservedObject var devices: DeviceStore
    @ObservedObject var build: BuildStore
    @EnvironmentObject var loc: Localizer

    let showLocked: Bool
    let onOpenSharedApp: () -> Void

    package init(devices: DeviceStore, build: BuildStore, showLocked: Bool = true, onOpenSharedApp: @escaping () -> Void = {}) {
        self.showLocked = showLocked
        self.devices = devices
        self.build = build
        self.onOpenSharedApp = onOpenSharedApp
    }

    package var body: some View {
        if build.target != BuildTarget.mac, build.sharedJob == nil, !build.running || sending || showLocked { card.disabled(build.running && !sending) }
    }

    /// The copy of the game data runs on the build store's `running` flag too, and its own buttons must stay usable (Stop).
    private var sending: Bool {
        switch build.send { case .sending, .copying: return true; default: return false }
    }

    private var card: some View {
        CardGroup(loc.t("build.ios")) {
            CardRow(loc.t("shared.buildKind"), detail: devices.exportOneGame ? loc.t("shell.ipaOneGameNote") : loc.t("shared.addNote")) {
                LauncherSegmented(options: [("shared", loc.t("shared.addOption")), ("one", loc.t("shell.ipaOneGame"))],
                                  selection: devices.exportOneGame ? "one" : "shared") { pickKind($0 == "one") }
                    .frame(width: ExportGrid.switchWidth)
            }
            CardDivider()
            if devices.exportOneGame {
                ExportSteps(build: build, devices: devices)
            } else {
                CardRow(loc.t("shared.pageHint")) {
                    Button(loc.t("shared.open"), action: onOpenSharedApp)
                }
            }
        }
    }

    /// The other kind: the IPA of the last export is not the one this choice makes, so step 1 starts again.
    private func pickKind(_ oneGame: Bool) {
        guard oneGame != devices.exportOneGame else { return }
        devices.exportOneGame = oneGame
        build.exportedIPAPath = ""
        build.send = .idle
    }
}

/// Where the shared app goes from the iPhone app page: signed and installed on a paired device, or exported as an unsigned IPA for
/// another tool to sign. The device rows show for an install and for sending the game data after an export.
package struct SharedAppTargetCard: View {
    @ObservedObject var devices: DeviceStore
    @ObservedObject var build: BuildStore
    @EnvironmentObject var loc: Localizer

    package init(devices: DeviceStore, build: BuildStore) {
        self.devices = devices
        self.build = build
    }

    package var body: some View {
        let options = [(value: "", label: loc.t("dev.none"))] + devices.devices.map { d in
            (value: d.id, label: d.name + (d.reachable ? "" : " (" + loc.t("dev.notConnected") + ")"))
        }
        let teams = devices.teams.map { (value: $0.id, label: $0.label(personalTeam: loc.t("dev.personalTeam"))) }
        let needsCertificate = devices.teams.first { $0.id == devices.signingTeam }.map { !$0.hasCertificate } ?? false
        let footnote = devices.exportIPA ? loc.t("shared.exportFootnote")
            : devices.installDevice.isEmpty ? "" : (needsCertificate ? loc.t("dev.teamNoCert") + " " : "") + loc.t("dev.note")
        return CardGroup(loc.t("dev.section"), footnote: footnote) {
            CardRow(loc.t("shell.modeTitle")) {
                LauncherSegmented(options: [("install", loc.t("shell.modeInstall")), ("export", loc.t("shell.modeExport"))],
                                  selection: devices.exportIPA ? "export" : "install") { devices.exportIPA = $0 == "export" }
                    .frame(width: ExportGrid.switchWidth)
            }
            CardDivider()
            CardRow(loc.t(devices.exportIPA ? "shared.sendTo" : "dev.target"), detail: devices.checked && devices.devices.isEmpty ? loc.t("dev.noDevices") : "") {
                RefreshDevicesButton(devices: devices)
                LauncherDropdown(options: options, selection: devices.installDevice, label: loc.t("dev.target")) { devices.installDevice = $0 }
            }
            if !devices.exportIPA, !devices.installDevice.isEmpty {
                CardDivider()
                if teams.isEmpty {
                    CardRow(loc.t("dev.team"), detail: loc.t("dev.noTeam"), dot: LauncherPalette.building) { EmptyView() }
                } else {
                    CardRow(loc.t("dev.team")) {
                        LauncherDropdown(options: teams, selection: devices.signingTeam, label: loc.t("dev.team")) { devices.signingTeam = $0 }
                    }
                }
            }
        }
        .disabled(build.running)
        .onAppear { if !devices.checked { _ = devices.refresh() } }
    }
}
