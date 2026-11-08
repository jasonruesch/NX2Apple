import SwiftUI
import NXCore
import NXModel

/// The page's conclusion, at the end of its column: what is still missing, and the build button. While a batch waits to start, the
/// button builds all its games from the first one (`onStartQueue`), whichever game's files the page shows.
/// Observes the build store, the batch, and the dependency and repository stores for the status text.
package struct ActionCard: View {
    @ObservedObject var build: BuildStore
    @ObservedObject var dependencies: DependencyStore
    @ObservedObject var repo: RepoStore
    @ObservedObject var queue: BuildQueue
    let onStartQueue: () -> Void
    @EnvironmentObject var loc: Localizer

    /// Without a batch (the cards of tests and captures that have none).
    @MainActor package init(build: BuildStore, dependencies: DependencyStore, repo: RepoStore) {
        self.init(build: build, dependencies: dependencies, repo: repo, queue: BuildQueue())
    }

    package init(build: BuildStore, dependencies: DependencyStore, repo: RepoStore, queue: BuildQueue, onStartQueue: @escaping () -> Void = {}) {
        self.build = build
        self.dependencies = dependencies
        self.repo = repo
        self.queue = queue
        self.onStartQueue = onStartQueue
    }

    private var batch: Bool { queue.isPrepared && queue.isShown && !build.running }
    private var enabled: Bool { batch ? dependencies.allPresent && repo.isRepo : (build.running || build.canBuild) }

    package var body: some View {
        HStack(spacing: 18) {
            statusText
            Spacer(minLength: 12)
            Button {
                if batch { onStartQueue() } else if build.running { build.stop() } else { build.startBuild() }
            } label: {
                Label(batch ? String(format: loc.t(queue.hasResults ? "queue.rebuildAll" : "queue.buildAll"), queue.entries.count)
                        : build.running ? loc.t(build.stopping ? "library.stopping" : "btn.stop") : (build.done ? loc.t("btn.rebuild") : loc.t("build.startGame")),
                      systemImage: build.running ? "stop.fill" : (batch ? "square.stack.3d.up.fill" : "hammer.fill"))
                    .font(.manrope(15, .semibold)).padding(.horizontal, 24).padding(.vertical, 13)
                    .foregroundStyle(.black).background(build.running ? LauncherPalette.building : LauncherPalette.cream, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(build.stopping || !enabled)
            .opacity(build.stopping || !enabled ? 0.4 : 1)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.top, 2)
        .staleFrameworksPrompt(build)
    }

    @ViewBuilder private var statusText: some View {
        if batch {
            Text(loc.t("queue.statusPrepared")).font(.manrope(13)).foregroundStyle(.secondary).lineLimit(3)
        } else if !build.doneNote.isEmpty {
            Text(build.doneNote).font(.manrope(13))
                .foregroundStyle(build.done ? LauncherPalette.ready : LauncherPalette.building).lineLimit(3)
        } else if !dependencies.checked {
            Text(loc.t("status.checkingDeps")).font(.manrope(13)).foregroundStyle(.secondary)
        } else if !dependencies.allPresent {
            Text(loc.t("status.installFirst")).font(.manrope(13)).foregroundStyle(LauncherPalette.building)
        } else if !repo.isRepo {
            Text(loc.t("status.chooseRepo")).font(.manrope(13)).foregroundStyle(LauncherPalette.building)
        } else if build.gameFolderRefused {
            Text(loc.t("status.fixFolder")).font(.manrope(13)).foregroundStyle(.secondary)
        } else if !build.inputsReady {
            Text(loc.t("status.needInputs")).font(.manrope(13)).foregroundStyle(.secondary)
        } else {
            Text(String(format: loc.t("status.output"), build.shortPath(build.outDir.isEmpty ? build.inputFolder : build.outDir)))
                .font(.manrope(13)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
        }
    }
}
