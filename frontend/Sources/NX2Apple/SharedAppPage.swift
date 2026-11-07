import SwiftUI
import Combine
import NXCore
import NXLauncher
import NXModel

// The iPhone app page: the one shared app on its own. Game builds for iPhone or iPad add their game to it (BuildStore+SharedApp.swift);
// this page lists the games in it, says which are not in the app that was last made, and makes the app once: installed on a device,
// or exported as an IPA whose game data goes over afterwards. It stays here (not in NXLauncher) because it reads the library for each
// game's game data.

struct SharedAppPage: View {
    @ObservedObject var build: BuildStore
    @ObservedObject var devices: DeviceStore
    @ObservedObject var library: GameLibrary
    var onNewBuild: () -> Void = {}
    var onViewGame: () -> Void = {}
    @State private var state = SharedAppState(games: [], installedAt: nil, exportedAt: nil)
    @State private var logOpen = false
    @State private var removing: SharedAppState.Game?
    @EnvironmentObject var loc: Localizer

    private var export: Bool { devices.exportIPA }
    /// The page's own job runs (not a game build, not a send).
    private var making: Bool { build.running && (build.sharedJob == .install || build.sharedJob == .export) }
    private var gameBuilding: Bool { build.running && build.sharedJob == nil }

    var body: some View {
        LauncherPageScroll {
            CardPageHeading(loc.t("shared.heading"), note: loc.t("shared.intro"))
            if gameBuilding {
                CardGroup(loc.t("shared.makeSection")) {
                    CardRow(loc.t("shared.busy"), dot: LauncherPalette.building) { EmptyView() }
                }
            }
            if state.games.isEmpty {
                emptyCard
            } else {
                gamesCard
                SharedAppTargetCard(devices: devices, build: build)
                makeCard
                if build.sharedJob == .install || build.sharedJob == .export {
                    Group {
                        ProgressCard(build: build)
                        ShellCopyCard(devices: devices)
                        BuildFailureCard(m: build)
                        OutcomeCard(build: build, devices: devices, onViewGame: onViewGame)
                    }
                }
                if export, let ipa = exportedIPA {
                    ipaCard(ipa)
                    SharedDataCard(build: build, devices: devices, games: entries)
                }
                if build.sharedJob != nil {
                    LogCard(log: build.log, devices: devices, isOpen: $logOpen, showRequests: Empty<Bool, Never>().eraseToAnyPublisher(), didShow: {})
                }
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: build.running) { _ in refresh() }
        .onChange(of: build.shellRoot) { _ in refresh() }
        .confirmationDialog(removing.map { String(format: loc.t("shared.removeTitle"), $0.name) } ?? "",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button(loc.t("shared.remove"), role: .destructive) { if let game = removing { remove(game) } }
            Button(loc.t("shared.cancel"), role: .cancel) { removing = nil }
        } message: {
            Text(loc.t("shared.removeNote"))
        }
    }

    // MARK: Cards

    private var emptyCard: some View {
        CardGroup(loc.t("shared.games")) {
            CardRow(loc.t("shared.emptyTitle"), detail: loc.t("shared.empty")) {
                Button(loc.t("library.newBuild"), action: onNewBuild)
            }
        }
    }

    private var gamesCard: some View {
        CardGroup(String(format: loc.t("shared.gamesCount"), state.games.count)) {
            ForEach(Array(state.games.enumerated()), id: \.element.id) { index, game in
                if index > 0 { CardDivider() }
                let new = state.isNew(game, export: export)
                CardRow(game.name.isEmpty ? game.titleID : game.name, detail: gameDetail(game, new: new),
                        dot: new ? LauncherPalette.building : LauncherPalette.ready, help: game.framework) {
                    Button(loc.t("shared.remove")) { removing = game }
                        .disabled(build.running)
                }
            }
        }
    }

    private var makeCard: some View {
        CardGroup(loc.t("shared.makeSection")) {
            CardRow(summary, detail: makeNote, dot: state.newGames(export: export).isEmpty ? LauncherPalette.ready : LauncherPalette.building) {
                Button {
                    making ? build.stop() : build.makeSharedApp(data: entries.filter { !$0.archive.isEmpty }
                        .map { SharedGameData(titleID: $0.titleID, archive: $0.archive) })
                } label: {
                    Label(making ? loc.t(build.stopping ? "library.stopping" : "btn.stop") : loc.t(export ? "shared.makeExport" : "shared.makeInstall"),
                          systemImage: making ? "stop.fill" : (export ? "square.and.arrow.up" : "iphone.and.arrow.forward"))
                        .font(.manrope(14, .semibold)).padding(.horizontal, 18).padding(.vertical, 9)
                        .foregroundStyle(.black).background(making ? LauncherPalette.building : LauncherPalette.cream, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(build.stopping || (!making && !build.canMakeSharedApp))
                .opacity(build.stopping || (!making && !build.canMakeSharedApp) ? 0.4 : 1)
            }
        }
    }

    private func ipaCard(_ ipa: String) -> some View {
        CardGroup(loc.t("shared.ipaSection")) {
            CardRow((ipa as NSString).lastPathComponent, detail: ipaDetail(ipa), dot: LauncherPalette.ready, help: ipa) {
                Button(loc.t("install.reveal")) { revealInFinder(ipa) }
            }
        }
    }

    // MARK: Text

    /// Where the app stands against its games: never made, games it lacks, or every game in it.
    private var summary: String {
        if state.lastMade(export: export) == nil { return loc.t(export ? "shared.neverExported" : "shared.neverInstalled") }
        let new = state.newGames(export: export).count
        return new > 0 ? String(format: loc.t(new == 1 ? "shared.newOne" : "shared.newCount"), new) : loc.t("shared.upToDate")
    }

    private var makeNote: String {
        if export { return String(format: loc.t("shared.makeExportNote"), state.games.count) }
        guard build.installsDirectly else { return loc.t("shell.needsDevice") }
        return String(format: loc.t("shared.makeInstallNote"), state.games.count, devices.deviceName(devices.installDevice))
    }

    private func gameDetail(_ game: SharedAppState.Game, new: Bool) -> String {
        let built = game.builtAt.map { String(format: loc.t("shared.builtAt"), dateText($0)) } ?? loc.t("shared.frameworkGone")
        let where_ = new ? loc.t(export ? "shared.notInIPA" : "shared.notOnDevice") : loc.t(export ? "shared.inIPA" : "shared.onDevice")
        return built + " · " + where_
    }

    private func ipaDetail(_ ipa: String) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: ipa)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let made = (attributes?[.modificationDate] as? Date).map(dateText) ?? ""
        return [ShellInstall.sizeText(size), made].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: loc.lang.code)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: Data

    /// The shared app's IPA when there is one.
    private var exportedIPA: String? {
        let ipa = ShellInstall.ipaPath(root: build.shellRoot)
        return FileManager.default.fileExists(atPath: ipa) ? ipa : nil
    }

    /// Each game of the shared app with the game data its last build packed (the library remembers it).
    private var entries: [SharedDataCard.Entry] {
        state.games.map { game in
            let archive = library.games.first { $0.titleID.caseInsensitiveCompare(game.titleID) == .orderedSame }?.archivePath ?? ""
            let present = !archive.isEmpty && FileManager.default.fileExists(atPath: archive)
            return SharedDataCard.Entry(titleID: game.titleID, name: game.name.isEmpty ? game.titleID : game.name, archive: present ? archive : "")
        }
    }

    private func refresh() { state = build.sharedApp }

    private func remove(_ game: SharedAppState.Game) {
        removing = nil
        build.removeFromSharedApp(titleID: game.titleID)
        library.recordRemovedFromSharedApp(titleID: game.titleID)
        refresh()
    }
}
