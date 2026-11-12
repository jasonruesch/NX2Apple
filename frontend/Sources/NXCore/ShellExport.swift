import Foundation
import CryptoKit

// The shared app as an unsigned IPA (LNPANDY/NX2Apple#416): no device and no signing team. The same project as the install
// (build_shell.sh --prepare-xcode), built by xcodebuild with signing off, the executable signed ad-hoc to carry its entitlements
// (as build_ipa.sh does for the one-game IPA), then zipped as Payload/<app>.app. A sideloading tool signs the result. The game data
// stays out: the player copies romfs.img into the app's Documents/games/<title ID>/ after installing it.

extension ShellInstall {
    /// The IPA's file name.
    package static let ipaName = "NX2Apple.ipa"

    /// Everything the export writes lives in this folder of the shell root, apart from the project.
    package static func exportFolder(root: String) -> String { root + "/export" }
    package static func ipaPath(root: String) -> String { exportFolder(root: root) + "/" + ipaName }
    /// Its own derived data: the unsigned build must not replace the signed app that an install, a reinstall and a re-sign use.
    package static func exportDerivedData(root: String) -> String { exportFolder(root: root) + "/derived-data" }
    package static func exportAppPath(root: String) -> String { exportDerivedData(root: root) + "/Build/Products/Release-iphoneos/" + appName }
    /// The folder the app is copied into as `Payload/<app>.app` before it is zipped.
    package static func exportStage(root: String) -> String { exportFolder(root: root) + "/stage" }

    /// The shell project (prepared by the install's own script call) built for iOS, as build_shell.sh --build does. Without a team,
    /// signing is off. With one, Xcode signs it for that team and makes a development profile for the devices registered to it.
    /// Xcode registers a device with the team only when it builds for that device, so a signed build is for `device` when one is
    /// chosen: the profile then holds it too, and the app still runs on the team's other devices. `bundleID` is the one shell.json
    /// holds unless the player chose another for the IPA.
    package static func exportBuildCommand(xcrun: String, root: String, bundleID: String, team: String = "", device: String = "") -> [String] {
        let destination = !team.isEmpty && !device.isEmpty ? "id=\(device)" : "generic/platform=iOS"
        let signing = team.isEmpty ? ["CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY="]
            : ["DEVELOPMENT_TEAM=\(team)"]
        return [xcrun, "xcodebuild", "-project", projectFolder(root: root) + "/" + projectName, "-scheme", scheme,
                "-configuration", "Release", "-destination", destination, "-derivedDataPath", exportDerivedData(root: root)]
            + (team.isEmpty ? [] : ["-allowProvisioningUpdates"])
            + ["PRODUCT_BUNDLE_IDENTIFIER=\(bundleID)"] + signing + ["build"]
    }

    /// xcodebuild's words when the device it was asked to build for is not connected.
    package static func destinationMissing(_ output: String) -> Bool {
        output.contains("Unable to find a destination matching") || output.contains("Unable to find a device matching")
    }

    /// A bundle ID Xcode accepts: two or more parts of letters, digits and hyphens, separated by dots.
    package static func isValidBundleID(_ id: String) -> Bool {
        id.range(of: "^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$", options: .regularExpression) != nil
    }

    /// The bundle ID of the app the last export built, nil before the first export. The data send looks for it on the device.
    package static func exportedBundleID(root: String) -> String? {
        let info = NSDictionary(contentsOfFile: exportAppPath(root: root) + "/Info.plist")
        return (info?["CFBundleIdentifier"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    // ---- the team-signed export: shader packing changes the app after Xcode signed it, so it is signed again the same way ----

    /// Writes the signing certificates of `app` as `<prefix>0`, `<prefix>1`…; the first is the one it was signed with.
    package static func certificatesCommand(codesign: String, app: String, prefix: String) -> [String] {
        [codesign, "-d", "--extract-certificates=\(prefix)", app]
    }

    /// Writes the entitlements `app` was signed with (Xcode's, from the provisioning profile) to `file` as XML.
    package static func entitlementsDumpCommand(codesign: String, app: String, file: String) -> [String] {
        [codesign, "-d", "--entitlements", file, "--xml", app]
    }

    /// Signs `path` with the identity whose certificate has the SHA-1 `identity`, with `entitlements` for the app itself.
    package static func teamSignCommand(codesign: String, identity: String, entitlements: String?, path: String) -> [String] {
        [codesign, "--force", "--sign", identity, "--timestamp=none"]
            + (entitlements.map { ["--entitlements", $0, "--generate-entitlement-der"] } ?? []) + [path]
    }

    /// codesign names an identity by its certificate's SHA-1, in hex.
    package static func identityHash(certificate: Data) -> String {
        Insecure.SHA1.hash(data: certificate).map { String(format: "%02X", $0) }.joined()
    }

    /// The entitlements file `build_shell.sh --prepare-xcode` writes into the project (the Increased Memory Limit request).
    package static func entitlementsPath(root: String) -> String { projectFolder(root: root) + "/Gen/DmShell.entitlements" }

    /// An unsigned app has no signature to carry the entitlements, so a sideloader would lose the request. The executable gets an
    /// ad-hoc signature that holds them, which the sideloader replaces and keeps the entitlements of (build_ipa.sh does the same).
    package static func entitlementsCommand(app: String, entitlements: String) -> [String] {
        ["/usr/bin/codesign", "--force", "--sign", "-", "--entitlements", entitlements, app + "/" + scheme]
    }

    /// codesign refuses a file with a resource fork or Finder information.
    package static func cleanAttributesCommand(app: String) -> [String] { ["/usr/bin/xattr", "-cr", app + "/" + scheme] }

    /// The IPA: the stage folder holds `Payload/<app>.app`, and ditto writes it with Payload as the root (see `BuildCommands.ipaCommand`).
    package static func zipCommand(root: String) -> [String] {
        BuildCommands.ipaCommand(payload: exportStage(root: root) + "/Payload", ipa: ipaPath(root: root))
    }

    /// The symlink inside `project/` that points to the current `frontend-ios` package, so `DmShell.xcodeproj` stays valid
    /// after a Gatekeeper AppTranslocation mount is unmounted or the launcher is moved to another folder.
    package static func linkedShellPackage(root: String) -> String { projectFolder(root: root) + "/frontend-ios" }

    /// Point `<root>/project/frontend-ios` (and any dangling engine symlinks in `<root>/project/`) at the running launcher's
    /// paths, and rewrite `DmShell.xcodeproj/project.pbxproj` to reference `frontend-ios` inside `<root>/project/`.
    package static func refreshProjectLinks(root: String, resources: String? = Bundle.main.resourceURL?.path, repo: String,
                                            fm: FileManager = .default) {
        let proj = projectFolder(root: root)
        guard fm.fileExists(atPath: proj) else { return }
        let link = linkedShellPackage(root: root)
        if let pkg = shellPackage(resources: resources, repo: repo, fm: fm), pkg != link {
            let attrs = try? fm.attributesOfItem(atPath: link)
            let isSymlink = (attrs?[.type] as? FileAttributeType) == .typeSymbolicLink
            if isSymlink || attrs == nil, (try? fm.destinationOfSymbolicLink(atPath: link)) != pkg {
                if isSymlink { try? fm.removeItem(atPath: link) }
                try? fm.createSymbolicLink(atPath: link, withDestinationPath: pkg)
            }
        }
        let engine = EngineLayout.root(repo)
        for item in ["Sources", "Shell", "tools"] {
            let itemLink = proj + "/" + item, target = engine + "/dm/ios/" + item
            guard !fm.fileExists(atPath: itemLink), fm.fileExists(atPath: target) else { continue }
            let attrs = try? fm.attributesOfItem(atPath: itemLink)
            let isSymlink = (attrs?[.type] as? FileAttributeType) == .typeSymbolicLink
            if isSymlink || attrs == nil {
                if isSymlink { try? fm.removeItem(atPath: itemLink) }
                try? fm.createSymbolicLink(atPath: itemLink, withDestinationPath: target)
            }
        }
        let pbxPath = proj + "/" + projectName + "/project.pbxproj"
        guard fm.fileExists(atPath: link + "/Package.swift"),
              let pbx = try? String(contentsOfFile: pbxPath, encoding: .utf8),
              let re = try? NSRegularExpression(pattern: #"(path|relativePath) = "?(?:[^";\n]*/)?frontend-ios"?;"#) else { return }
        let updated = re.stringByReplacingMatches(in: pbx, range: NSRange(pbx.startIndex..., in: pbx),
                                                  withTemplate: #"$1 = "frontend-ios";"#)
        if updated != pbx {
            try? updated.write(toFile: pbxPath, atomically: true, encoding: .utf8)
        }
    }
}

extension ShellInstaller {
    package static let exportBuildStageID = 1012, exportPackStageID = 1013

    /// Steps 3 and 4 of the install, which the export shares: the library with this game, and the shell's project.
    /// Exactly one of `failure` and (`library`, `env`) is set. `notes` name the games left out because their framework is incomplete.
    /// `leaveOut`: the export's excluded games (SharedAppGames), which stay in shell.json but not in the project. The install leaves none out.
    func prepareShell(framework: String, titleID: String, name: String, leaveOut: Set<String> = [])
        -> (library: ShellLibrary?, env: [String: String]?, failure: Outcome?, notes: [String]) {
        // 3: the library
        ShellInstall.sweepDiscarded(in: ShellInstall.frameworksMirror(root: root))
        // shell.json and the mirrors it points to as they were, put back when the project step refuses: a framework build_shell.sh
        // rejects (an older build, a game of another profile) must not stay in the library, nor in place of the mirror of a game that
        // worked, or every later install of any game fails on it
        let fm = FileManager.default
        let stateFile = ShellLibrary.stateFile(root: root)
        let before = fm.contents(atPath: stateFile)
        var replaced: [(mirror: String, previous: String)] = []
        func restoreLibrary() {
            do {
                if let before { try before.write(to: URL(fileURLWithPath: stateFile), options: .atomic) }
                else if fm.fileExists(atPath: stateFile) { try fm.removeItem(atPath: stateFile) }
            } catch {
                log("library: shell.json could not be put back as it was at \(stateFile): \(error.localizedDescription)\n")
            }
            for (mirror, previous) in replaced {
                guard ShellInstall.discard(mirror) else {
                    log("library: the refused framework at \(mirror) could not be moved away, the previous one stays at \(previous)\n")
                    continue
                }
                do { try fm.moveItem(atPath: previous, toPath: mirror) } catch {
                    log("library: the previous framework could not be put back at \(mirror) from \(previous): \(error.localizedDescription)\n")
                }
            }
        }
        var library = ShellLibrary.load(root: root)
        if !team.isEmpty { library.team = team }   // the export has no team: keep the one an install stored
        library.add(.init(titleID: titleID, name: name, framework: framework))
        replaced = mirrorFrameworks(&library)
        library.dropMissing()
        let checked = leaveOutIncomplete(&library, titleID: titleID, name: name)   // ShellFrameworks.swift
        if let why = checked.failure {
            let projectName = t("shell.projectStage")
            begin(Self.projectStageID, projectName)
            end(Self.projectStageID, projectName, ok: false, detail: why)
            restoreLibrary()
            return (nil, nil, Outcome(ok: false, message: fmt("shell.projectFailed", why)), [])
        }
        // The 16:9 banner of the shell's library for every game in it (ShellHost reads <framework>/banner.<ext>, the square
        // icon.png is the fallback): a game rebuilt since its last install gets its banner back too
        for game in library.games {
            let picked = game.titleID == titleID ? pickedArtwork : nil
            if let banner = ShellInstall.placeBanner(titleID: game.titleID, framework: game.framework, banners: banners, picked: picked) {
                log("banner: \(game.titleID) \(banner)\n")
            }
        }
        do { try library.save(root: root) } catch {
            restoreLibrary()
            return (nil, nil, Outcome(ok: false, message: fmt("shell.projectFailed", error.localizedDescription)), [])
        }

        let saved = library   // every game, as shell.json holds them: Xcode's earlier builds keep those
        library = SharedAppGames.forExport(library, leavingOut: leaveOut, keeping: titleID)

        // 4: the project
        guard let package = ShellInstall.shellPackage(resources: resources, repo: repo) else {
            let looked = ([resources, repo].compactMap { $0 }.filter { !$0.isEmpty }).map { $0 + "/frontend-ios" }.joined(separator: ", ")
            restoreLibrary()
            return (nil, nil, Outcome(ok: false, message: fmt("shell.projectFailed", "no frontend-ios Swift package (Package.swift) in " + looked)), [])
        }
        var env = ShellInstall.projectEnvironment(root: root, frameworks: library.games.map(\.framework), bundleID: library.bundleID,
                                                  team: team, python: python, path: toolPath, home: NSHomeDirectory(), user: NSUserName(),
                                                  tmp: NSTemporaryDirectory(), package: package)
        env.merge(BundledTools.environment(for: python)) { $1 }
        let projectName = t("shell.projectStage")
        begin(Self.projectStageID, projectName)
        let project = run(ShellInstall.projectCommand(repo: repo), env: env, label: projectName, step: { _ in nil })
        if project.status != 0 {
            let why = ShellInstall.scriptFailure(project.output) ?? fmt("msg.exitCode", project.status)
            end(Self.projectStageID, projectName, ok: false, detail: why)
            restoreLibrary()
            return (nil, nil, Outcome(ok: false, message: fmt("shell.projectFailed", why)), [])
        }
        for (_, previous) in replaced { ShellInstall.discard(previous) }   // the script took the new frameworks
        ShellInstall.refreshProjectLinks(root: root, resources: resources, repo: repo)
        ShellInstall.writeProjectFrameworks(root: root, games: library.games)
        ShellInstall.pruneEmbeddedFrameworks(root: root, keeping: saved.games)
        end(Self.projectStageID, projectName, ok: true)
        return (library, env, nil, checked.notes)
    }

    /// The export: the library and the project, the unsigned build, the entitlements, the IPA. Needs no device and no team.
    package func export(framework: String, titleID: String, name: String) -> Outcome {
        let fm = FileManager.default
        guard fm.fileExists(atPath: framework) else { return missingFramework(framework, name: name) }
        // A game the player excluded and then built and exported is wanted again
        if SharedAppGames.isExcluded(titleID, root: root) { try? SharedAppGames.setExcluded(titleID, false, root: root) }
        let prepared = prepareShell(framework: framework, titleID: titleID, name: name, leaveOut: SharedAppGames.excluded(root: root))
        guard let library = prepared.library else { return prepared.failure! }

        // The build, in the export's own derived data: unsigned, or signed for the export's team
        let signed = !exportTeam.isEmpty
        let buildName = t(signed ? "shell.exportSignedBuildStage" : "shell.exportBuildStage")
        begin(Self.exportBuildStageID, buildName)
        var target = signed ? device : ""
        func build(_ bundleID: String) -> ToolResult {
            run(ShellInstall.exportBuildCommand(xcrun: xcrun, root: root, bundleID: bundleID, team: exportTeam, device: target), env: nil,
                label: buildName, stageID: Self.exportBuildStageID, step: BuildProgress.xcodeStep)
        }
        var bundleID = exportBundleID.isEmpty ? library.bundleID : exportBundleID
        var built = build(bundleID)
        // A chosen device that is not connected: build for any device, with the profile of the devices the team already has
        if !target.isEmpty, built.status != 0, ShellInstall.destinationMissing(built.output) {
            log("signing: \(deviceName) is not connected, so it cannot be registered with the team; building for the team's registered devices\n")
            target = ""
            built = build(bundleID)
        }
        // The same two retries as the install's signing: the team's own identifier when the default one belongs to another team
        // (not for an identifier the player chose), and no Increased Memory Limit for a team whose profiles cannot carry it
        let variant = ShellLibrary.teamVariant(team: exportTeam)
        if signed, built.status != 0, exportBundleID.isEmpty, bundleID != variant, BuildFailureClassifier.signingTeamTaken(built.output) {
            log("signing: \(bundleID) is registered to another team, retrying as \(variant)\n")
            bundleID = variant
            built = build(bundleID)
        }
        if signed, built.status != 0, ShellInstall.memoryCapabilityMissing(built.output), var plain = prepared.env {
            log("signing: the team's provisioning profile cannot carry the Increased Memory Limit capability; signing without it (a large game may run out of memory)\n")
            plain["DM_ENTITLEMENTS"] = ""
            let again = run(ShellInstall.projectCommand(repo: repo), env: plain, label: t("shell.projectStage"), step: { _ in nil })
            if again.status == 0 { built = build(bundleID) }
        }
        if built.status != 0 {
            let why = built.lastError ?? fmt("msg.exitCode", built.status)
            end(Self.exportBuildStageID, buildName, ok: false, detail: why)
            return Outcome(ok: false, message: fmt("shell.exportFailed", why))
        }
        let app = ShellInstall.exportAppPath(root: root)
        guard fm.fileExists(atPath: app) else {
            end(Self.exportBuildStageID, buildName, ok: false, detail: app)
            return Outcome(ok: false, message: fmt("dev.noProject", app))
        }
        end(Self.exportBuildStageID, buildName, ok: true)
        return packExport(app: URL(fileURLWithPath: app), library: library, notes: prepared.notes, bundleID: bundleID, teamSigned: signed)
    }

    /// Stage and zip Payload/<app>.app. Signing can add _CodeSignature/ and CodeResources, so reserve two ZIP32 entries.
    /// `teamSigned`: Xcode signed `app` for a team, and the staged copy is signed again with the same identity and entitlements.
    func packExport(app: URL, library: ShellLibrary, notes: [String] = [], bundleID: String? = nil, teamSigned: Bool = false,
                    entryLimit: Int = ShellExport.entryLimit, hardLimit: Int = ShellExport.entryLimit) -> Outcome {
        let fm = FileManager.default
        let packName = t("shell.exportPackStage")
        begin(Self.exportPackStageID, packName)
        let stage = ShellInstall.exportStage(root: root), ipa = ShellInstall.ipaPath(root: root)
        let stagedApp = URL(fileURLWithPath: stage + "/Payload/" + ShellInstall.appName)
        var packed: [URL] = []
        do {
            try? fm.removeItem(atPath: stage)
            try? fm.removeItem(atPath: ipa)
            try fm.createDirectory(atPath: stage + "/Payload", withIntermediateDirectories: true)
            try fm.copyItem(at: app, to: stagedApp)
            ShellExport.leaveOutOtherGames(in: stagedApp, library: library)
            let payload = stagedApp.deletingLastPathComponent()
            if exportWithoutShaders {
                packed = try ShellExport.stripShaders(in: stagedApp, frameworkNames: library.games.map { URL(fileURLWithPath: $0.framework).lastPathComponent })
            }
            if try ShellExport.exceedsEntryLimit(in: payload, limit: entryLimit) {
                packed += try packShaderLibraries(in: stagedApp, games: library.games, label: packName)
                if try ShellExport.exceedsEntryLimit(in: payload, limit: hardLimit) {
                    throw ShellExport.entryLimitExceededError(limit: hardLimit)
                }
            }
        } catch {
            try? fm.removeItem(atPath: stage)
            end(Self.exportPackStageID, packName, ok: false, detail: error.localizedDescription)
            return Outcome(ok: false, message: fmt("shell.exportFailed", error.localizedDescription))
        }
        if teamSigned {
            if let why = signForTeam(built: app.path, staged: stagedApp.path, frameworks: packed.map(\.path), label: packName) {
                try? fm.removeItem(atPath: stage)
                end(Self.exportPackStageID, packName, ok: false, detail: why)
                return Outcome(ok: false, message: fmt("shell.exportFailed", why))
            }
        } else {
            // Signing the executable also seals its bundle resources. Sign the staged app after packing the shaders.
            // Failure only costs the Increased Memory Limit request, so it does not stop the export.
            let entitlements = ShellInstall.entitlementsPath(root: root)
            if fm.fileExists(atPath: entitlements) {
                _ = run(ShellInstall.cleanAttributesCommand(app: stagedApp.path), env: nil, label: packName, step: { _ in nil })
                let signed = run(ShellInstall.entitlementsCommand(app: stagedApp.path, entitlements: entitlements), env: nil, label: packName, step: { _ in nil })
                if signed.status != 0 { log("export: the entitlements could not be added to the app (a large game may run out of memory): \(signed.output)\n") }
            } else {
                log("export: no entitlements file at \(entitlements), the app asks for no Increased Memory Limit\n")
            }
        }
        let zipped = run(ShellInstall.zipCommand(root: root), env: nil, label: packName, step: { _ in nil })
        try? fm.removeItem(atPath: stage)
        guard zipped.status == 0, fm.fileExists(atPath: ipa) else {
            try? fm.removeItem(atPath: ipa)
            let why = zipped.lastError ?? fmt("msg.exitCode", zipped.status)
            end(Self.exportPackStageID, packName, ok: false, detail: why)
            return Outcome(ok: false, message: fmt("shell.exportFailed", why))
        }
        end(Self.exportPackStageID, packName, ok: true)
        var outcome = Outcome(ok: true, message: ([fmt("shell.exportDone", ipa)] + notes).joined(separator: "\n"), bundleID: bundleID ?? library.bundleID)
        outcome.ipaPath = ipa
        return outcome
    }

    /// Keep a large IPA within the sideloader's 16-bit entry count. Only the games in the shell library
    /// know how to unpack an archive. Leave other frameworks' resources in their original layout.
    /// Returns the frameworks it changed.
    private func packShaderLibraries(in stagedApp: URL, games: [ShellLibrary.Game], label: String) throws -> [URL] {
        let names = games.map { URL(fileURLWithPath: $0.framework).lastPathComponent }
        return try ShellExport.packShaderLibraries(
            in: stagedApp,
            frameworkNames: names,
            runArchive: { command in
                let result = run(command, env: nil, label: label, step: { _ in nil })
                return (result.status, result.output, result.lastError)
            },
            exitCodeMessage: { fmt("msg.exitCode", $0) }
        )
    }

    /// Signs the staged app again as Xcode signed `built`: the same identity (found by its certificate) and the same entitlements,
    /// the changed `frameworks` first. Returns why it failed, nil when it worked. Unlike the unsigned export's ad-hoc signature, a
    /// failure stops the export: a team-signed IPA whose signature is broken does not install.
    private func signForTeam(built: String, staged: String, frameworks: [String], label: String) -> String? {
        let fm = FileManager.default
        let work = ShellInstall.exportFolder(root: root) + "/signing"
        try? fm.removeItem(atPath: work)
        defer { try? fm.removeItem(atPath: work) }
        do { try fm.createDirectory(atPath: work, withIntermediateDirectories: true) } catch { return error.localizedDescription }
        let certificates = run(ShellInstall.certificatesCommand(codesign: codesign, app: built, prefix: work + "/cert"), env: nil, label: label, step: { _ in nil })
        guard certificates.status == 0, let leaf = fm.contents(atPath: work + "/cert0") else {
            return certificates.lastError ?? t("shell.exportNoIdentity")
        }
        let identity = ShellInstall.identityHash(certificate: leaf), entitlements = work + "/entitlements.plist"
        let dumped = run(ShellInstall.entitlementsDumpCommand(codesign: codesign, app: built, file: entitlements), env: nil, label: label, step: { _ in nil })
        guard dumped.status == 0, fm.fileExists(atPath: entitlements) else { return dumped.lastError ?? fmt("msg.exitCode", dumped.status) }
        _ = run(["/usr/bin/xattr", "-cr", staged], env: nil, label: label, step: { _ in nil })
        for path in frameworks + [staged] {
            let signed = run(ShellInstall.teamSignCommand(codesign: codesign, identity: identity, entitlements: path == staged ? entitlements : nil, path: path),
                             env: nil, label: label, step: { _ in nil })
            if signed.status != 0 { return signed.lastError ?? fmt("msg.exitCode", signed.status) }
        }
        log("export: signed again for the team with identity \(identity)\n")
        return nil
    }

    /// The game data into the shared app that is installed already and signed by another tool (LNPANDY/NX2Apple#416). The app is found
    /// on the device by its bundle ID prefix (a sideloading tool may add a team ID): none is `.appNotFound`, several come back in
    /// `apps` for the player to choose from (`bundleID` then names the one). The copy is the install's own data step (listing, diff,
    /// free space, the wired-or-Wi-Fi question, the copy). A copy that fails comes back as `.refused` with devicectl's words in `detail`.
    /// We believe devicectl writes into an app container only for an app signed for development (get-task-allow). That is not verified on
    /// a device, so the launcher says only that the device refused, and offers the Finder way (#491).
    package func sendData(titleID: String, archive: String, bundleID: String? = nil) -> Outcome {
        if let refused = pairingRefusal() { return refused }
        var chosen = bundleID, name = ""
        if chosen == nil {
            let json = NSTemporaryDirectory() + "nspb-shell-apps-\(UUID().uuidString.prefix(8)).json"
            defer { try? FileManager.default.removeItem(atPath: json) }
            let listed = run([xcrun, "devicectl"] + InstalledApps.listArguments(device: device, json: json), env: nil, label: t("shell.sendStage"), step: { _ in nil })
            guard listed.status == 0, let apps = InstalledApps.parse(FileManager.default.contents(atPath: json) ?? Data()) else {
                var unread = Outcome(ok: false, message: fmt("shell.sendListFailed", deviceName))
                unread.detail = listed.lastError ?? fmt("msg.exitCode", listed.status)
                unread.dataFailure = .noAppList
                return unread
            }
            let found = ShellInstall.shellApps(in: apps, exported: ShellInstall.exportedBundleID(root: root))
            guard let first = found.first else {
                var none = Outcome(ok: false, message: t("shell.sendNoApp"))
                none.dataFailure = .appNotFound
                return none
            }
            if found.count > 1 {
                var several = Outcome(ok: false, message: t("shell.sendSeveral"))
                several.apps = found
                return several
            }
            chosen = first.bundle; name = first.name
        }
        var outcome = copyGameData(titleID: titleID, archive: archive, app: "", bundleID: chosen!,
                                   outcome: Outcome(ok: true, message: "", bundleID: chosen!))
        outcome.appName = name
        if outcome.ok, !outcome.copySkipped {
            outcome.message = t("shell.sendDone")
        }
        if !outcome.ok, outcome.failure == .shellDataIncomplete {
            // The device listed the app, so a copy that fails is a refusal, whatever devicectl's words are (#491). Its words stay in `detail`.
            outcome.dataFailure = .refused
            outcome.message = t("shell.sendRefused")
            outcome.failure = nil   // the install's Retry card does not fit: nothing of the install ran
        }
        return outcome
    }
}

/// Shared IPA staging helpers used by both unsigned exports (`ShellInstaller.packExport`) and signed app exports (`BuildStore.saveIPA`).
package enum ShellExport {
    /// Signing can add `_CodeSignature/` and `CodeResources`, so reserve two entries below the 16-bit ZIP32 ceiling.
    package static let entryLimit = Int(UInt16.max) - 2

    package static func exceedsEntryLimit(in payload: URL, limit: Int = entryLimit) throws -> Bool {
        var failure: Error?
        guard let entries = FileManager.default.enumerator(at: payload, includingPropertiesForKeys: [], errorHandler: { _, error in
            failure = error
            return false
        }) else {
            throw failure ?? CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: payload.path])
        }
        var count = 1   // ditto --keepParent writes Payload/ itself, then DmShell.app/ and its descendants.
        while count <= limit, entries.nextObject() != nil { count += 1 }
        if let failure { throw failure }
        return count > limit
    }

    package static func entryLimitExceededError(limit: Int) -> Error {
        CocoaError(.fileWriteUnknown, userInfo: [
            NSLocalizedDescriptionKey: "IPA bundle exceeds the \(limit)-entry ZIP32 archive limit"
        ])
    }

    /// Names the embedded `DmGame<titleID>.framework` bundles whose `msl/` trees `ShellHost` knows how to unpack from `.aar`.
    package static func gameFrameworkNames(forApp appPath: String, stagedApp: URL, fm: FileManager = .default) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        func append(_ name: String) {
            if !name.isEmpty, seen.insert(name).inserted {
                names.append(name)
            }
        }
        if let shell = ShellInstall.paths(ofApp: appPath) {
            for game in ShellLibrary.load(root: shell.root).games {
                append(URL(fileURLWithPath: game.framework).lastPathComponent)
            }
        }
        let frameworksDir = stagedApp.appendingPathComponent("Frameworks")
        for item in (try? fm.contentsOfDirectory(atPath: frameworksDir.path))?.sorted() ?? []
            where !ShellInstall.titleID(ofFramework: item).isEmpty {
            append(item)
        }
        return names
    }

    /// The staged app holds only the library's games: Xcode's earlier build can still embed a game the export now leaves out.
    package static func leaveOutOtherGames(in stagedApp: URL, library: ShellLibrary, fm: FileManager = .default) {
        let keep = Set(library.games.map { URL(fileURLWithPath: $0.framework).lastPathComponent })
        let folder = stagedApp.appendingPathComponent("Frameworks")
        for item in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        where item.hasPrefix("DmGame") && item.hasSuffix(".framework") && !keep.contains(item) {
            try? fm.removeItem(at: folder.appendingPathComponent(item))
        }
    }

    /// Leaves the shaders of the named game frameworks out of the staged app (GameShaders.strip). Returns the frameworks it changed.
    package static func stripShaders(in stagedApp: URL, frameworkNames: [String]) throws -> [URL] {
        let frameworks = stagedApp.appendingPathComponent("Frameworks")
        return try Set(frameworkNames).sorted().compactMap { name in
            let framework = frameworks.appendingPathComponent(name)
            return try GameShaders.strip(framework: framework) ? framework : nil
        }
    }

    /// Packs loose `msl/` directories inside the named game frameworks into `msl-<UUID>.aar` archives so the IPA stays within ZIP32 limits.
    @discardableResult
    package static func packShaderLibraries(
        in stagedApp: URL,
        frameworkNames: [String],
        runArchive: ([String]) -> (status: Int32, output: String, lastError: String?),
        exitCodeMessage: (Int32) -> String
    ) throws -> [URL] {
        let fm = FileManager.default
        let frameworks = stagedApp.appendingPathComponent("Frameworks")
        var packed = Set<String>()
        var changed: [URL] = []
        for name in frameworkNames where packed.insert(name).inserted {
            let framework = frameworks.appendingPathComponent(name)
            let shaders = framework.appendingPathComponent("msl")
            var directory: ObjCBool = false
            guard fm.fileExists(atPath: shaders.path, isDirectory: &directory), directory.boolValue else { continue }
            for old in try fm.contentsOfDirectory(at: framework, includingPropertiesForKeys: nil) where old.pathExtension == "aar" {
                let stem = old.deletingPathExtension().lastPathComponent
                if stem.hasPrefix("msl-"), UUID(uuidString: String(stem.dropFirst(4))) != nil {
                    try fm.removeItem(at: old)
                }
            }
            let archive = framework.appendingPathComponent("msl-\(UUID().uuidString).aar")
            let result = runArchive(["/usr/bin/aa", "archive", "-d", shaders.path, "-o", archive.path, "-a", "lzfse"])
            guard result.status == 0, fm.fileExists(atPath: archive.path) else {
                let reason = result.lastError ?? ShellInstall.scriptFailure(result.output) ?? exitCodeMessage(result.status)
                throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: reason])
            }
            try fm.removeItem(at: shaders)
            changed.append(framework)
        }
        return changed
    }
}
