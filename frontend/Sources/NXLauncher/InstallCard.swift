import SwiftUI
import NXCore
import NXModel

/// Where an iPhone build goes: signed and installed on a paired device ("Install on device"), or exported as an unsigned IPA for
/// another tool to sign, with the game data sent afterwards ("Export as IPA", ExportSteps). Shown for the iPhone target only. Observes the
/// device store, and the build store for the target and whether a build runs.
package struct InstallCard: View {
    @ObservedObject var devices: DeviceStore
    @ObservedObject var build: BuildStore
    @EnvironmentObject var loc: Localizer

    let showLocked: Bool

    package init(devices: DeviceStore, build: BuildStore, showLocked: Bool = true) {
        self.showLocked = showLocked
        self.devices = devices
        self.build = build
    }

    package var body: some View {
        if build.target != BuildTarget.mac, !build.running || sending || showLocked { card.disabled(build.running && !sending) }
    }

    /// The copy of the game data runs on the build store's `running` flag too, and its own buttons must stay usable (Stop).
    private var sending: Bool {
        switch build.send { case .sending, .copying: return true; default: return false }
    }

    private var deviceOptions: [(value: String, label: String)] {
        [(value: "", label: loc.t("dev.none"))] + devices.devices.map { d in
            (value: d.id, label: d.name + (d.reachable ? "" : " (" + loc.t("dev.notConnected") + ")"))
        }
    }

    private var card: some View {
        let options = deviceOptions
        let teams = devices.teams.map { (value: $0.id, label: $0.label(personalTeam: loc.t("dev.personalTeam"))) }
        let needsCertificate = devices.teams.first { $0.id == devices.signingTeam }.map { !$0.hasCertificate } ?? false
        let footnote = devices.exportIPA ? ""
            : devices.installDevice.isEmpty ? "" : (needsCertificate ? loc.t("dev.teamNoCert") + " " : "") + loc.t("dev.note")
        return CardGroup(loc.t("dev.section"), footnote: footnote) {
            // The two ways, a switch of their own: exporting is never chosen for the player (#416)
            CardRow(loc.t("shell.modeTitle")) {
                LauncherSegmented(options: [("install", loc.t("shell.modeInstall")), ("export", loc.t("shell.modeExport"))],
                                  selection: devices.exportIPA ? "export" : "install") { devices.exportIPA = $0 == "export" }
                    .frame(width: ExportGrid.switchWidth)
            }
            CardDivider()
            if devices.exportIPA {
                // What the IPA holds: the shared app by default, one game with its data inside as the other choice (#540)
                CardRow(loc.t("shell.ipaKind"), detail: devices.exportOneGame ? loc.t("shell.ipaOneGameNote") : loc.t("shell.ipaSharedNote")) {
                    LauncherSegmented(options: [("shared", loc.t("shell.ipaShared")), ("one", loc.t("shell.ipaOneGame"))],
                                      selection: devices.exportOneGame ? "one" : "shared") { pickKind($0 == "one") }
                        .frame(width: ExportGrid.switchWidth)
                }
                CardDivider()
                if !devices.exportOneGame { ipaRows(teams: teams) }
                ExportSteps(build: build, devices: devices)
            } else {
                CardRow(loc.t("dev.target"), detail: devices.checked && devices.devices.isEmpty ? loc.t("dev.noDevices") : "") {
                    RefreshDevicesButton(devices: devices)
                    LauncherDropdown(options: options, selection: devices.installDevice, label: loc.t("dev.target")) { devices.installDevice = $0 }
                }
                if !devices.installDevice.isEmpty {
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
        }
        .onAppear { if !devices.checked { _ = devices.refresh() } }
    }

    /// The other kind of IPA: the IPA of the last export is not the one this choice makes, so step 1 starts again.
    private func pickKind(_ oneGame: Bool) {
        guard oneGame != devices.exportOneGame else { return }
        devices.exportOneGame = oneGame
        build.exportedIPAPath = ""
        build.send = .idle
    }

    /// The IPA's signing team (or unsigned, for a sideloading tool) and its bundle ID (empty: the shared app's own).
    @ViewBuilder private func ipaRows(teams: [(value: String, label: String)]) -> some View {
        let signing = [(value: "", label: loc.t("shared.ipaUnsigned"))] + teams
        CardRow(loc.t("shared.ipaSigning"), detail: loc.t(devices.ipaTeam.isEmpty ? "shared.ipaUnsignedNote" : "shared.ipaSignedNote")) {
            LauncherDropdown(options: signing, selection: devices.ipaTeam, label: loc.t("shared.ipaSigning")) { devices.ipaTeam = $0 }
        }
        CardDivider()
        let current = ShellLibrary.load(root: build.shellRoot).bundleID
        CardRow(loc.t("shared.ipaBundleID"),
                detail: devices.ipaBundleIDValid ? String(format: loc.t("shared.ipaBundleIDNote"), current) : loc.t("shared.ipaBundleIDInvalid"),
                dot: devices.ipaBundleIDValid ? nil : LauncherPalette.building) {
            TextField(current, text: $devices.ipaBundleID)
                .textFieldStyle(.roundedBorder).font(.manrope(13))
                .autocorrectionDisabled()
                .frame(width: ExportGrid.switchWidth)
                .accessibilityLabel(loc.t("shared.ipaBundleID"))
        }
        CardDivider()
        // The shaders are most of the IPA: left out, they go to the device with each game's data in step 3
        CardRow(loc.t("shared.ipaShaders"), detail: loc.t(devices.ipaWithoutShaders ? "shared.ipaShadersOutNote" : "shared.ipaShadersInNote")) {
            Toggle(loc.t("shared.ipaShaders"), isOn: $devices.ipaWithoutShaders)
                .toggleStyle(LauncherSwitchStyle()).labelsHidden()
        }
        CardDivider()
        // A signed IPA is built for the device it goes to, so Xcode registers that device with the team before the export
        if !devices.ipaTeam.isEmpty {
            CardRow(loc.t("dev.target"), detail: devices.checked && devices.devices.isEmpty ? loc.t("dev.noDevices") : loc.t("shared.ipaDeviceNote")) {
                RefreshDevicesButton(devices: devices)
                LauncherDropdown(options: deviceOptions, selection: devices.installDevice, label: loc.t("dev.target")) { devices.installDevice = $0 }
            }
            CardDivider()
        }
    }
}
