import SwiftUI
import NXCore
import NXModel

/// The batch of games the library sent to the Builds page. While none of it runs (before its first run, and after each run with every
/// game's last result), each game can be shown in the cards below to check or change its files, built on its own, or taken out; the
/// Build games button builds them all from the first. While it runs, each game's state. Observes the queue only.
package struct QueueCard: View {
    @ObservedObject var queue: BuildQueue
    /// Shows a game's files in the Builds page's cards (the app saves the files of the game shown before).
    let onSelect: (UUID) -> Void
    /// Builds one game on its own, with the files shown for it.
    let onBuildOne: (UUID) -> Void
    @EnvironmentObject var loc: Localizer

    package init(queue: BuildQueue, onSelect: @escaping (UUID) -> Void = { _ in }, onBuildOne: @escaping (UUID) -> Void = { _ in }) {
        self.queue = queue
        self.onSelect = onSelect
        self.onBuildOne = onBuildOne
    }

    package var body: some View {
        if !queue.entries.isEmpty && !queue.isShown {
            CardGroup(loc.t("queue.asideSection")) {
                CardRow(String(format: loc.t("queue.aside"), queue.entries.count)) {
                    // The batch game's files replace the single game's on the page; nothing of the single game is saved into the batch
                    Button(loc.t("queue.showBatch")) {
                        if let id = queue.selectedID ?? queue.entries.first?.id { onSelect(id) }
                        queue.bringBack()
                    }
                }
            }
        } else if !queue.entries.isEmpty {
            CardGroup(title, footnote: queue.isPrepared ? loc.t("queue.prepareNote") : "") {
                ForEach(Array(queue.entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { CardDivider() }
                    CardRow(entry.name, detail: detail(entry), dot: dot(entry)) {
                        if queue.isPrepared {
                            if queue.selectedID != entry.id {
                                Button(loc.t("queue.showFiles")) { onSelect(entry.id) }
                            }
                            Button(loc.t("queue.buildOne")) { onBuildOne(entry.id) }
                            Button(loc.t("shared.remove")) { queue.remove(entry.id) }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if queue.isPrepared { onSelect(entry.id) } }
                    .accessibilityAddTraits(queue.selectedID == entry.id ? .isSelected : [])
                }
                if queue.isActive || queue.hasResults {
                    CardDivider()
                    CardRow(queue.isActive ? loc.t("queue.running") : loc.t("queue.finished")) {
                        if queue.isActive && queue.waitingCount > 0 {
                            Button(loc.t("queue.cancel")) { queue.cancelWaiting() }
                        }
                        if queue.isPrepared { Button(loc.t("queue.clear")) { queue.clear() } }
                    }
                }
            }
        }
    }

    private var title: String {
        queue.isActive ? String(format: loc.t("queue.section"), queue.finishedCount, queue.entries.count)
            : String(format: loc.t("queue.prepared"), queue.entries.count)
    }

    private func detail(_ entry: BuildQueue.Entry) -> String {
        let target = loc.t(entry.target == BuildTarget.mac ? "build.mac" : "build.ios")
        let state: String
        switch entry.state {
        case .waiting: state = queue.isPrepared ? loc.t("queue.ready") : loc.t("queue.waiting")
        case .building: state = loc.t("library.building")
        case .done: state = loc.t("queue.done")
        case .failed(let why): state = why.isEmpty ? loc.t("queue.failed") : why
        case .skipped(let why): state = why.isEmpty ? loc.t("queue.skipped") : why
        case .cancelled: state = loc.t("queue.cancelled")
        }
        let shown = queue.isPrepared && queue.selectedID == entry.id ? " · " + loc.t("queue.shown") : ""
        return target + " · " + state + shown
    }

    private func dot(_ entry: BuildQueue.Entry) -> Color? {
        if queue.isPrepared && queue.selectedID == entry.id { return LauncherPalette.cream }
        switch entry.state {
        case .waiting, .cancelled: return nil
        case .building: return LauncherPalette.building
        case .done: return LauncherPalette.ready
        case .failed, .skipped: return LauncherPalette.danger
        }
    }
}
