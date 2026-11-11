import SwiftUI
import NXCore
import NXModel

/// The games the shared app's IPA holds, under step 1 of the export: each with when it was built and where it stands against the
/// last IPA, so the player sees what "Export IPA" and "Build and export" pack before choosing one. Read from shell.json and the
/// frameworks on disk (`IPAContents`), as the export reads them.
struct IPAGamesList: View {
    let contents: IPAContents
    @EnvironmentObject var loc: Localizer
    @State private var expanded = false

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
    }

    private func row(_ game: IPAContents.Game) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ExportGrid.gap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(game.name).font(.manrope(13)).foregroundStyle(game.tag == .missing ? .secondary : .primary).lineLimit(1)
                if let built = game.built {
                    Text(String(format: loc.t("shell.ipaGameBuilt"), built.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(locale))))
                        .font(.manrope(11.5)).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: ExportGrid.gap)
            tag(game.tag)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func tag(_ tag: IPAContents.Tag) -> some View {
        let (key, color): (String, Color) = {
            switch tag {
            case .inLastIPA: return ("shell.ipaTagInLast", .secondary)
            case .newSinceIPA: return ("shell.ipaTagNew", LauncherPalette.ready)
            case .addedByBuild: return ("shell.ipaTagAdded", LauncherPalette.building)
            case .rebuiltByBuild: return ("shell.ipaTagRebuilt", LauncherPalette.building)
            case .missing: return ("shell.ipaTagMissing", .red)
            }
        }()
        return Text(loc.t(key)).font(.manrope(11.5, .semibold)).foregroundStyle(color).lineLimit(1).fixedSize()
    }

    /// "18 in the last IPA · 2 new · 1 left out", the groups that are not empty.
    private var summary: String {
        let count = { (tags: [IPAContents.Tag]) in contents.games.filter { tags.contains($0.tag) }.count }
        let parts: [(String, Int)] = [("shell.ipaSummaryInLast", count([.inLastIPA])), ("shell.ipaSummaryNew", count([.newSinceIPA, .rebuiltByBuild])),
                                      ("shell.ipaSummaryAdded", count([.addedByBuild])), ("shell.ipaSummaryMissing", count([.missing]))]
        return parts.filter { $0.1 > 0 }.map { String(format: loc.t($0.0), $0.1) }.joined(separator: " · ")
    }

    private var locale: Locale { Locale(identifier: loc.lang.locales.first ?? loc.lang.code) }
}
