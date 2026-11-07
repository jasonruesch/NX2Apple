import Foundation
import Combine
import NXCore

// The shared app on a page of its own. A game build for iPhone or iPad ends by adding its game to shell.json (`addToSharedApp`). The
// iPhone app page makes the shared app once from every game in it: installed on a device with the game data the device lacks, or
// exported as an unsigned IPA (#416) whose game data the page sends afterwards, one game at a time. The steps are ShellInstaller's
// (NXCore, ShellSharedApp.swift); this runs them off the main actor with the build's stages, log and Stop.

/// What the iPhone app page runs.
package enum SharedJob: Equatable {
    case install, export, send
}

extension BuildStore {
    /// The end of a game build for the shared app: the game joins shell.json, and nothing else is made.
    func addToSharedApp(framework: String, titleID: String, name: String) {
        running = true
        let installer = makeInstaller()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = installer.addToSharedApp(framework: framework, titleID: titleID, name: name)
            hop {
                if self.stopping {
                    self.stopping = false; self.running = false
                    self.resetProgress(); self.doneNote = self.t("msg.stopped"); self.cleanupStaging()
                    return
                }
                guard result.ok else { self.finishInstall(result.message); return }
                self.addedToSharedApp = true
                self.finishInstall(nil, note: result.message)
            }
        }
    }

    /// The games in the shared app, when each was built, and when the app was last installed or exported.
    package var sharedApp: SharedAppState { SharedAppState.read(root: shellRoot) }

    /// The page's action can run: nothing else runs, and an install has a device and a team.
    package var canMakeSharedApp: Bool { !running && (devices.exportIPA || installsDirectly) }

    /// Makes the shared app from the games in shell.json: installed on the chosen device (then the game data of `data` the device
    /// lacks), or exported as an IPA, as the page's switch says.
    package func makeSharedApp(data: [SharedGameData]) {
        guard canMakeSharedApp else { return }
        let export = devices.exportIPA
        startSharedJob(export ? .export : .install)
        if let why = shellRootProblem() { fail(why); return }
        let installer = makeInstaller()
        let target = devices, device = devices.installDevice
        DispatchQueue.global(qos: .userInitiated).async {
            let result = export ? installer.exportShared() : installer.installShared(data: data)
            hop {
                target.copyEnded()
                if self.stopping {
                    self.stopping = false; self.running = false
                    self.resetProgress(); self.doneNote = self.t("msg.stopped"); self.cleanupStaging()
                    return
                }
                guard result.ok else {
                    self.finishInstall(result.message)
                    if let kind = result.failure { self.failure = BuildFailure(kind: kind, gameName: nil) }
                    else if let step = result.step { self.noteInstallFailure(step, error: result.message) }
                    return
                }
                if export { self.exportedIPAPath = result.ipaPath } else { self.installedOn = device; self.installedAppPath = result.appPath }
                self.finishInstall(nil, note: result.message)
            }
        }
    }

    /// The game data of one game into the exported shared app on the device (step 3 of the export, for any game the app holds).
    package func sendSharedData(titleID: String, archive: String, bundle: String? = nil) {
        guard !running, !archive.isEmpty else { return }
        let ipa = ShellInstall.ipaPath(root: shellRoot)
        guard FileManager.default.fileExists(atPath: ipa) else { return }
        sharedJob = .send
        archivePath = archive
        exportedIPAPath = ipa
        sendGameData(bundle: bundle)
    }

    /// Takes a game out of the shared app. Its build stays on this Mac; the next install or export leaves it out.
    package func removeFromSharedApp(titleID: String) {
        guard !running else { return }
        var library = ShellLibrary.load(root: shellRoot)
        library.remove(titleID: titleID)
        try? library.save(root: shellRoot)
        objectWillChange.send()
    }

    private func startSharedJob(_ job: SharedJob) {
        stopping = false
        running = true; done = false; doneNote = ""; failure = nil; stages = []
        log.clear()
        installedOn = ""; installedAppPath = ""; exportedIPAPath = ""; send = .idle; addedToSharedApp = false
        sharedJob = job
    }
}
