import SwiftUI
import NXCore
import NXModel

/// The batch of games the library sent to the Builds page. Before it starts, each game can be picked to show its files in the cards
/// below (to check or change them) or taken out; the Build games button starts it from the first game. While it runs and after, each
/// game's state. Observes the queue only.
package struct QueueCard: View {
    @ObservedObject var queue: BuildQueue
    /// Shows a game's files in the Builds page's cards (the app saves the files of the game shown before).
    let onSelect: (UUID) -> Void
    @EnvironmentObject var loc: Localizer

    package init(queue: BuildQueue, onSelect: @escaping (UUID) -> Void = { _ in }) {
        self.queue = queue
        self.onSelect = onSelect
    }

    package var body: some View {
        if !queue.entries.isEmpty {
            CardGroup(title, footnote: queue.isPrepared ? loc.t("queue.prepareNote") : "") {
                ForEach(Array(queue.entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { CardDivider() }
                    CardRow(entry.name, detail: detail(entry), dot: dot(entry)) {
                        if queue.isPrepared && entry.state == .waiting {
                            if queue.selectedID != entry.id {
                                Button(loc.t("queue.showFiles")) { onSelect(entry.id) }
                            }
                            Button(loc.t("shared.remove")) { queue.remove(entry.id) }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if queue.isPrepared && entry.state == .waiting { onSelect(entry.id) } }
                    .accessibilityAddTraits(queue.selectedID == entry.id ? .isSelected : [])
                }
                if !queue.isPrepared {
                    CardDivider()
                    CardRow(queue.isActive ? loc.t("queue.running") : loc.t("queue.finished")) {
                        if queue.isActive && queue.waitingCount > 0 {
                            Button(loc.t("queue.cancel")) { queue.cancelWaiting() }
                        }
                        if !queue.isActive { Button(loc.t("queue.clear")) { queue.clearFinished() } }
                    }
                }
            }
        }
    }

    private var title: String {
        queue.isPrepared ? String(format: loc.t("queue.prepared"), queue.waitingCount)
            : String(format: loc.t("queue.section"), queue.finishedCount, queue.entries.count)
    }

    private func detail(_ entry: BuildQueue.Entry) -> String {
        let target = loc.t(entry.target == BuildTarget.mac ? "build.mac" : "build.ios")
        let state: String
        switch entry.state {
        case .waiting: state = queue.isPrepared ? (queue.selectedID == entry.id ? loc.t("queue.shown") : loc.t("queue.ready")) : loc.t("queue.waiting")
        case .building: state = loc.t("library.building")
        case .done: state = loc.t("queue.done")
        case .failed(let why): state = why.isEmpty ? loc.t("queue.failed") : why
        case .skipped(let why): state = why.isEmpty ? loc.t("queue.skipped") : why
        case .cancelled: state = loc.t("queue.cancelled")
        }
        return target + " · " + state
    }

    private func dot(_ entry: BuildQueue.Entry) -> Color? {
        if queue.isPrepared { return queue.selectedID == entry.id ? LauncherPalette.cream : nil }
        switch entry.state {
        case .waiting, .cancelled: return nil
        case .building: return LauncherPalette.building
        case .done: return LauncherPalette.ready
        case .failed, .skipped: return LauncherPalette.danger
        }
    }
}
