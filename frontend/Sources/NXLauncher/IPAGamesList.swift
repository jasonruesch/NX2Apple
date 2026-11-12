import SwiftUI
import NXCore
import NXModel

/// The games the shared app's IPA holds, under step 1 of the export: each with when it was built and where it stands against the
/// last IPA, so the player sees what "Export IPA" and "Build and export" pack before choosing one. Read from shell.json and the
/// frameworks on disk (`IPAContents`), as the export reads them. It is also where the player manages the shared app's games: a switch
/// per game leaves it out of the next IPA (or puts it back), and Remove takes it out of the shared app for good (SharedAppGames).
struct IPAGamesList: View {
    let contents: IPAContents
    /// Excluding, including and removing are refused while a build or an export runs.
    var canChange = false
    var setIncluded: (String, Bool) -> Void = { _, _ in }
    var remove: (String) -> Void = { _ in }
    @EnvironmentObject var loc: Localizer
    @State private var expanded = false
    @State private var removing: IPAContents.Game?

    /// A short list stays open; a long one opens on the player's click, its summary says what it holds.
    static let openUpTo = 6
    private var open: Bool { expanded || contents.games.count <= Self.openUpTo }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: ExportGrid.tight) {
                Text(String(format: loc.t("shell.ipaGamesTitle"), contents.exportCount))
                    .font(.manrope(12.5, .semibold)).foregroundStyle(.secondary)
                Text(summary).font(.manrope(12.5)).foregroundStyle(.tertiary).lineLimit(1)
                Spacer(minLength: ExportGrid.gap)
                if contents.games.count > Self.openUpTo {
                    Button(loc.t(expanded ? "shell.ipaGamesHide" : "shell.ipaGamesShow")) { expanded.toggle() }
                        .buttonStyle(.plain).font(.manrope(12.5, .semibold)).foregroundStyle(.secondary)
                }
            }
            if contents.games.isEmpty {
                Text(loc.t("shell.ipaGamesNone")).font(.manrope(12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if open {
                VStack(spacing: 0) {
                    ForEach(Array(contents.games.enumerated()), id: \.element.id) { index, game in
                        if index > 0 { Divider().opacity(0.5) }
                        row(game)
                    }
                }
                .background(ExportGrid.well, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(LauncherPalette.ink(0.08)))
            }
        }
        .confirmationDialog(String(format: loc.t("shell.ipaGameRemoveTitle"), removing?.name ?? ""),
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { game in
            Button(loc.t("shell.ipaGameRemoveConfirm"), role: .destructive) { remove(game.titleID) }
            Button(loc.t("shell.ipaGameRemoveKeep"), role: .cancel) {}
        } message: { _ in
            Text(loc.t("shell.ipaGameRemoveNote"))
        }
    }

    private func row(_ game: IPAContents.Game) -> some View {
        HStack(alignment: .center, spacing: ExportGrid.gap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(game.name).font(.manrope(13)).foregroundStyle(game.tag == .missing || game.tag == .excluded ? .secondary : .primary).lineLimit(1)
                // Where it stands, after when it was built: the right side is the switch's own
                HStack(spacing: 0) {
                    if let built = game.built {
                        Text(String(format: loc.t("shell.ipaGameBuilt"), built.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(locale))) + " · ")
                            .foregroundStyle(.tertiary)
                    }
                    tag(game.tag)
                }
                .font(.manrope(11.5)).lineLimit(1)
            }
            Spacer(minLength: ExportGrid.gap)
            if game.tag != .addedByBuild {   // a game the build form would add is not in the shared app yet
                controls(game)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }

    /// The game's switch (in the next IPA or not) and its menu with Remove. A game whose framework is gone has nothing to include.
    private func controls(_ game: IPAContents.Game) -> some View {
        HStack(spacing: ExportGrid.tight) {
            // What the switch does, beside it; a game with nothing to include keeps the room, so the rows line up
            Text(loc.t("shell.ipaGameIncludeLabel")).font(.manrope(12, .semibold)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                .opacity(game.tag == .missing ? 0 : 1).accessibilityHidden(true)
            if game.tag != .missing {
                Toggle(String(format: loc.t("shell.ipaGameInclude"), game.name),
                       isOn: Binding(get: { game.tag != .excluded }, set: { setIncluded(game.titleID, $0) }))
                    .toggleStyle(LauncherSwitchStyle()).labelsHidden()
                    .disabled(!canChange || game.tag == .rebuiltByBuild)
                    .help(loc.t(game.tag == .excluded ? "shell.ipaGameExcludedNote" : "shell.ipaGameIncludedNote"))
            } else {   // the switch's room, so every row's menu lines up
                Toggle("", isOn: .constant(false)).toggleStyle(LauncherSwitchStyle()).labelsHidden().hidden().accessibilityHidden(true)
            }
            Menu {
                Button(loc.t("shell.ipaGameRemove")) { removing = game }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    .frame(width: 24, height: 22).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .disabled(!canChange)
            .accessibilityLabel(String(format: loc.t("shell.ipaGameMore"), game.name))
        }
    }

    private func tag(_ tag: IPAContents.Tag) -> some View {
        let (key, color): (String, Color) = {
            switch tag {
            case .inLastIPA: return ("shell.ipaTagInLast", .secondary)
            case .newSinceIPA: return ("shell.ipaTagNew", LauncherPalette.ready)
            case .addedByBuild: return ("shell.ipaTagAdded", LauncherPalette.building)
            case .rebuiltByBuild: return ("shell.ipaTagRebuilt", LauncherPalette.building)
            case .missing: return ("shell.ipaTagMissing", .red)
            case .excluded: return ("shell.ipaTagExcluded", .secondary)
            }
        }()
        return Text(loc.t(key)).fontWeight(.semibold).foregroundStyle(color).lineLimit(1).fixedSize()
    }

    /// "18 in the last IPA · 2 new · 1 left out", the groups that are not empty.
    private var summary: String {
        let count = { (tags: [IPAContents.Tag]) in contents.games.filter { tags.contains($0.tag) }.count }
        let parts: [(String, Int)] = [("shell.ipaSummaryInLast", count([.inLastIPA])), ("shell.ipaSummaryNew", count([.newSinceIPA, .rebuiltByBuild])),
                                      ("shell.ipaSummaryAdded", count([.addedByBuild])), ("shell.ipaSummaryMissing", count([.missing])),
                                      ("shell.ipaSummaryExcluded", count([.excluded]))]
        return parts.filter { $0.1 > 0 }.map { String(format: loc.t($0.0), $0.1) }.joined(separator: " · ")
    }

    private var locale: Locale { Locale(identifier: loc.lang.locales.first ?? loc.lang.code) }
}
