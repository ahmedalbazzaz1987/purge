//
//  Uninstaller.swift
//  Purge
//
//  Three related jobs:
//    1. Remove another application together with everything it left behind.
//    2. Show what launches at login, and let the user disable a user agent.
//    3. Remove Purge itself, completely, leaving nothing on disk.
//

import Foundation
import AppKit

// MARK: - Removing another app

struct AppTarget {
    let bundleURL: URL
    let name: String
    let bundleID: String
    let version: String
    let icon: NSImage?
    let bundleBytes: Int64
}

final class AppUninstaller {

    private let fm = FileManager.default
    private let scanner = Scanner()

    /// Applications the user could plausibly want to remove.
    func installedApps() -> [AppTarget] {
        var roots = ["/Applications"]
        roots.append((SafetyGuard.home as NSString).appendingPathComponent("Applications"))
        // One level of subfolders, so /Applications/Utilities shows up too.
        var appPaths: [String] = []
        for root in roots {
            guard let kids = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for k in kids {
                let p = (root as NSString).appendingPathComponent(k)
                if k.hasSuffix(".app") {
                    appPaths.append(p)
                } else if (try? fm.contentsOfDirectory(atPath: p)) != nil {
                    let subs = (try? fm.contentsOfDirectory(atPath: p)) ?? []
                    appPaths.append(contentsOf: subs.filter { $0.hasSuffix(".app") }
                        .map { (p as NSString).appendingPathComponent($0) })
                }
            }
        }

        // Sizes are skipped here: measuring every bundle in /Applications would
        // take far longer than the list is worth. The chosen app is measured
        // properly when it is selected.
        return appPaths.compactMap { target(for: URL(fileURLWithPath: $0), measure: false) }
            .filter { !SafetyGuard.protectedApps.contains($0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func target(for url: URL, measure: Bool = true) -> AppTarget? {
        guard let bundle = Bundle(url: url) else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        guard let id = bundle.bundleIdentifier, !id.isEmpty else { return nil }
        return AppTarget(
            bundleURL: url,
            name: name,
            bundleID: id,
            version: (info["CFBundleShortVersionString"] as? String) ?? "—",
            icon: NSWorkspace.shared.icon(forFile: url.path),
            bundleBytes: measure ? scanner.directorySize(url.path) : 0
        )
    }

    /// Every place a Mac app conventionally leaves state, checked against one
    /// specific bundle identifier and name. Nothing is globbed blindly.
    func leftovers(for app: AppTarget) -> [CleanItem] {
        let home = SafetyGuard.home
        let id = app.bundleID
        let shortName = app.name

        // Some vendors namespace by the first two components of the bundle ID
        // (com.vendor) rather than the full identifier.
        let vendor: String = {
            let parts = id.split(separator: ".")
            return parts.count >= 2 ? parts.prefix(2).joined(separator: ".") : id
        }()

        var candidates: [String] = []

        func add(_ rel: String) {
            candidates.append((home as NSString).appendingPathComponent(rel))
        }

        for key in Set([id, vendor]) {
            add("Library/Application Support/\(key)")
            add("Library/Caches/\(key)")
            add("Library/Preferences/\(key).plist")
            add("Library/Preferences/ByHost/\(key).plist")
            add("Library/Containers/\(key)")
            add("Library/Group Containers/\(key)")
            add("Library/HTTPStorages/\(key)")
            add("Library/HTTPStorages/\(key).binarycookies")
            add("Library/WebKit/\(key)")
            add("Library/Saved Application State/\(key).savedState")
            add("Library/Logs/\(key)")
            add("Library/Cookies/\(key).binarycookies")
            add("Library/LaunchAgents/\(key).plist")
            add("Library/Application Scripts/\(key)")
        }

        add("Library/Application Support/\(shortName)")
        add("Library/Logs/\(shortName)")
        add("Library/Caches/\(shortName)")

        var seen = Set<String>()
        var items: [CleanItem] = []

        for path in candidates where !seen.contains(path) {
            seen.insert(path)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir) else { continue }
            let size = isDir.boolValue ? scanner.directorySize(path) : scanner.fileSize(path)
            items.append(CleanItem(path: path,
                                   displayName: Format.shortPath(path),
                                   bytes: size,
                                   isDirectory: isDir.boolValue,
                                   modified: (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date))
        }

        return items.sorted { $0.bytes > $1.bytes }
    }

    /// Bundle plus the leftovers the user ticked.
    func uninstall(app: AppTarget,
                   leftovers: [CleanItem],
                   includeBundle: Bool,
                   method: RemovalMethod,
                   dryRun: Bool) -> RemovalReport {

        if NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty == false {
            for running in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID) {
                running.terminate()
            }
            Thread.sleep(forTimeInterval: 1.0)
        }

        var targets = leftovers
        if includeBundle {
            targets.append(CleanItem(path: app.bundleURL.path,
                                     displayName: app.bundleURL.lastPathComponent,
                                     bytes: app.bundleBytes,
                                     isDirectory: true,
                                     modified: nil))
        }

        let allowlist = Set(targets.map(\.path))
        var report = RemovalReport()

        for item in targets {
            let verdict = SafetyGuard.approve(item.path,
                                              mode: .uninstall,
                                              uninstallAllowlist: allowlist)
            guard verdict.isAllowed else {
                report.skipped.append((item.path, verdict.reason ?? "refused"))
                ActionLog.shared.write("SKIP  \(verdict.reason ?? "refused")  \(item.path)")
                continue
            }
            if dryRun {
                report.removed += 1
                report.freed += item.bytes
                ActionLog.shared.write("DRY   would uninstall  \(item.path)")
                continue
            }
            do {
                switch method {
                case .trash:
                    var out: NSURL?
                    try fm.trashItem(at: item.url, resultingItemURL: &out)
                case .permanent:
                    try fm.removeItem(at: item.url)
                }
                report.removed += 1
                report.freed += item.bytes
                ActionLog.shared.write("UNINST \(Format.bytes(item.bytes))  \(item.path)")
            } catch {
                report.failed.append((item.path, (error as NSError).localizedDescription))
                ActionLog.shared.write("FAIL  \((error as NSError).localizedDescription)  \(item.path)")
            }
        }
        return report
    }
}

// MARK: - Startup items

struct StartupItem: Identifiable {
    let id = UUID()
    let path: String
    let label: String
    let program: String
    var displayPath: String { Format.shortPath(path) }
}

enum StartupItems {

    static func list() -> [StartupItem] {
        let dir = (SafetyGuard.home as NSString).appendingPathComponent("Library/LaunchAgents")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }

        return names.filter { $0.hasSuffix(".plist") }.compactMap { name in
            let path = (dir as NSString).appendingPathComponent(name)
            let dict = NSDictionary(contentsOfFile: path) as? [String: Any] ?? [:]
            let label = (dict["Label"] as? String) ?? (name as NSString).deletingPathExtension
            var program = (dict["Program"] as? String) ?? ""
            if program.isEmpty, let args = dict["ProgramArguments"] as? [String] {
                program = args.first ?? ""
            }
            return StartupItem(path: path,
                               label: label,
                               program: program.isEmpty ? "—" : program)
        }
        .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    /// Only ever moves the agent's plist to the Trash, so it can be restored.
    static func disable(_ item: StartupItem) -> String? {
        let verdict = SafetyGuard.approve(item.path, mode: .userSelected)
        guard verdict.isAllowed else { return verdict.reason }
        do {
            var out: NSURL?
            try FileManager.default.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: &out)
            ActionLog.shared.write("AGENT moved to Trash  \(item.path)")
            return nil
        } catch {
            return (error as NSError).localizedDescription
        }
    }
}

// MARK: - Removing Purge itself

enum SelfUninstall {

    /// The complete list of everything Purge is capable of creating on this Mac.
    /// If this list is wrong, the promise of a clean removal is broken — so the
    /// app deliberately writes nowhere else.
    static func footprint() -> [String] {
        let home = SafetyGuard.home
        let rels = [
            "Library/Application Support/Purge",
            "Library/Preferences/\(AppInfo.bundleID).plist",
            "Library/Caches/\(AppInfo.bundleID)",
            "Library/Saved Application State/\(AppInfo.bundleID).savedState",
            "Library/HTTPStorages/\(AppInfo.bundleID)",
            "Library/WebKit/\(AppInfo.bundleID)",
        ]
        return rels
            .map { (home as NSString).appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    static func footprintItems() -> [CleanItem] {
        let scanner = Scanner()
        var items = footprint().map { path -> CleanItem in
            var isDir: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            return CleanItem(path: path,
                             displayName: Format.shortPath(path),
                             bytes: isDir.boolValue ? scanner.directorySize(path) : scanner.fileSize(path),
                             isDirectory: isDir.boolValue,
                             modified: nil)
        }
        let bundle = Bundle.main.bundlePath
        if !bundle.isEmpty, bundle.hasSuffix(".app") {
            items.append(CleanItem(path: bundle,
                                   displayName: Format.shortPath(bundle),
                                   bytes: scanner.directorySize(bundle),
                                   isDirectory: true,
                                   modified: nil))
        }
        return items
    }

    /// Removes the support files immediately, then hands the app bundle to a
    /// detached shell so the bundle can go while the process is already gone.
    static func perform(alsoRemoveBundle: Bool) {
        let fm = FileManager.default

        // Captured once: the list shrinks as items are removed, and the
        // allowlist has to stay the same for every path in the pass.
        let paths = footprint()
        let allowlist = Set(paths)

        for path in paths {
            guard SafetyGuard.approve(path,
                                      mode: .uninstall,
                                      uninstallAllowlist: allowlist).isAllowed else { continue }
            var out: NSURL?
            try? fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &out)
        }

        // Preferences the app may have written through UserDefaults but not
        // yet flushed to disk.
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
            UserDefaults.standard.synchronize()
        }

        guard alsoRemoveBundle else {
            NSApp.terminate(nil)
            return
        }

        let bundle = Bundle.main.bundlePath
        guard bundle.hasSuffix(".app") else { NSApp.terminate(nil); return }

        // A tiny detached script: wait for us to exit, then move the bundle to
        // the Trash and delete itself.
        let script = """
        #!/bin/sh
        sleep 1
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.3; done
        if ! /usr/bin/osascript -e 'tell application "Finder" to delete POSIX file "\(bundle)"' >/dev/null 2>&1; then
          /bin/rm -rf "\(bundle)"
        fi
        /bin/rm -f "$0"
        """

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("purge-farewell.sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = [scriptURL.path]
            try task.run()
        } catch {
            // If the handoff fails the user still has the bundle and can drag
            // it to the Trash; everything else is already gone.
        }

        NSApp.terminate(nil)
    }
}
