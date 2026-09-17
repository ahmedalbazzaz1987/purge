//
//  SafetyGuard.swift
//  Purge
//
//  The single chokepoint every deletion must pass through.
//  Nothing in this app removes a file without SafetyGuard.approve() returning .allowed.
//
//  Design rules:
//   1. Purge never runs as root and never asks for an admin password.
//   2. Purge only ever touches paths inside the current user's home directory,
//      plus the per-user temporary directory that macOS itself assigns us.
//   3. Everything is whitelist-first (see Rules.swift) and denylist-verified (here).
//   4. Symlinks are never followed and never deleted.
//   5. A rule's own root directory is never deleted -- only its children.
//

import Foundation

enum RemovalMode {
    /// Automatic sweep driven by a built-in rule. Strictest checks.
    case automatic
    /// User hand-picked this exact file in a browser-style list (Large Files, Duplicates).
    case userSelected
    /// Removing an application bundle and its leftovers.
    case uninstall
}

enum GuardVerdict: Equatable {
    case allowed
    case blocked(String)

    var isAllowed: Bool { if case .allowed = self { return true }; return false }
    var reason: String? { if case .blocked(let r) = self { return r }; return nil }
}

enum SafetyGuard {

    // MARK: - Anchors

    /// Real path of the user's home, symlinks resolved. Computed once.
    static let home: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
    }()

    /// The per-user confinement directory macOS hands us, e.g.
    /// /private/var/folders/xy/……/T . Its parent holds the "C" (cache) and "T" (temp) dirs.
    static let userTempRoot: String? = {
        let t = URL(fileURLWithPath: NSTemporaryDirectory())
            .resolvingSymlinksInPath().standardizedFileURL
        // NSTemporaryDirectory() is …/T/ -- step up to the confinement root.
        let root = t.deletingLastPathComponent().path
        guard root.hasPrefix("/private/var/folders/") || root.hasPrefix("/var/folders/") else {
            return nil
        }
        return root
    }()

    /// Volume identifier of the home directory. Anything on another volume is refused,
    /// so an external drive or a network share can never be swept by a rule.
    private static let homeVolumeID: NSCopying? = {
        let url = URL(fileURLWithPath: home)
        return (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier
    }()

    // MARK: - Denylists

    /// Never touched, in any mode, for any reason. Paths are home-relative.
    /// These hold credentials, irreplaceable user data, or state that macOS
    /// cannot rebuild on its own.
    static let neverTouch: [String] = [
        "Library/Keychains",
        "Library/Preferences",
        "Library/Mobile Documents",           // iCloud Drive
        "Library/CloudStorage",               // Dropbox / OneDrive / Google Drive mounts
        "Library/Messages",
        "Library/Mail",                       // exception carved out below for Mail Downloads
        "Library/Photos",
        "Library/Calendars",
        "Library/Accounts",
        "Library/IdentityServices",
        "Library/Sharing",
        "Library/Autosave Information",
        "Library/Application Support/MobileSync",     // iOS device backups
        "Library/Application Support/AddressBook",
        "Library/Application Support/com.apple.sharedfilelist",
        "Library/Application Support/Knowledge",
        "Library/Group Containers",
        "Library/Services",
        "Library/Fonts",
        "Library/Input Methods",
        "Library/PreferencePanes",
        "Library/Screen Savers",
        "Library/Sounds",
        "Documents",
        "Desktop",
        "Movies",
        "Music",
        "Pictures",
        "Public",
        ".ssh",
        ".gnupg",
        ".aws",
        ".kube",
        ".docker",
        ".config",
        ".local/share",
        ".password-store",
    ]

    /// Narrow exceptions that win over `neverTouch`. Home-relative.
    /// Only safe, regenerable sub-trees of an otherwise protected area.
    static let carveOuts: [String] = [
        "Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
    ]

    /// Additionally off-limits to automatic rules, but reachable when the user
    /// hand-picks an individual file in Large Files / Duplicates.
    static let manualOnly: [String] = [
        "Downloads",
        ".Trash",
    ]

    /// Directory names that must never be deleted wholesale even when a rule's
    /// glob happens to land on them.
    static let structuralNames: Set<String> = [
        "Library", "Caches", "Containers", "Application Support", "Logs",
        "Developer", "Xcode", "Preferences", "Safari", "Mail", "Home",
    ]

    /// Absolute minimum number of path components below "/" before a delete is
    /// even considered. /Users/<you>/.Trash/file -> 4 components, which is the
    /// shallowest thing any rule legitimately reaches. Everything at depth 3
    /// is a top-level folder in your home directory and is refused outright
    /// by the separate check further down.
    private static let minimumComponents = 4

    // MARK: - The chokepoint

    /// Applications Purge refuses to uninstall, whatever the user clicks.
    static let protectedApps: Set<String> = [
        "Finder", "Safari", "Mail", "Messages", "Photos", "Music", "TV",
        "System Settings", "System Preferences", "App Store", "Xcode",
        "Terminal", "Utilities", "Purge",
    ]

    /// Decide whether `path` may be removed. This is deliberately paranoid:
    /// when anything is ambiguous the answer is `.blocked`.
    ///
    /// - Parameter uninstallAllowlist: in `.uninstall` mode only, the exact set
    ///   of paths the uninstaller computed for one specific application. A path
    ///   inside an otherwise protected area is permitted only if it appears here
    ///   verbatim, so the exception can never widen by accident.
    static func approve(_ path: String,
                        mode: RemovalMode,
                        ruleRoot: String? = nil,
                        uninstallAllowlist: Set<String> = []) -> GuardVerdict {

        // --- 0. Shape of the path itself ------------------------------------
        guard path.hasPrefix("/") else {
            return .blocked("not an absolute path")
        }
        if path.contains("..") {
            return .blocked("path contains a parent reference")
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let clean = url.path
        if clean != path.trimmingTrailingSlash() {
            return .blocked("path is not in canonical form")
        }
        if clean == "/" || clean.isEmpty {
            return .blocked("refuses to act on the volume root")
        }

        // --- 1. Must exist, and we look at it without following symlinks ------
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: clean, isDirectory: &isDir) else {
            return .blocked("no longer exists")
        }
        if isSymlink(clean) {
            return .blocked("is a symbolic link")
        }
        // A parent that is a symlink could redirect us outside home.
        if parentChainContainsSymlink(clean) {
            return .blocked("reached through a symbolic link")
        }

        // --- 2. Containment: home, or our own temp confinement ---------------
        let inHome = clean == home ? false : clean.hasPrefix(home + "/")
        let inTemp: Bool = {
            guard let t = userTempRoot else { return false }
            return clean.hasPrefix(t + "/")
        }()

        if clean == home {
            return .blocked("is the home directory itself")
        }

        // The one sanctioned way out of the home directory: an application
        // bundle sitting directly in /Applications, during an uninstall the
        // user explicitly asked for.
        let isUninstallTargetApp: Bool = {
            guard mode == .uninstall, clean.hasSuffix(".app"), isDir.boolValue else { return false }
            guard uninstallAllowlist.contains(clean) else { return false }
            let parent = (clean as NSString).deletingLastPathComponent
            let userApps = (home as NSString).appendingPathComponent("Applications")
            guard parent == "/Applications" || parent == userApps else { return false }
            let appName = (clean as NSString).lastPathComponent
                .replacingOccurrences(of: ".app", with: "")
            if protectedApps.contains(appName) { return false }
            // Anything Apple ships lives in /System/Applications and is
            // unreachable anyway, but refuse it explicitly too.
            if clean.hasPrefix("/System/") { return false }
            return true
        }()

        if !inHome && !inTemp && !isUninstallTargetApp {
            return .blocked("is outside your home directory")
        }
        if inTemp, let t = userTempRoot, clean == t {
            return .blocked("is the temporary directory root")
        }

        // --- 3. Same volume as home ------------------------------------------
        if inHome, let expected = homeVolumeID {
            let vid = (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier
            if let vid, !vid.isEqual(expected) {
                return .blocked("lives on a different volume")
            }
        }

        // --- 4. Depth ---------------------------------------------------------
        let components = clean.split(separator: "/").map(String.init)
        if inHome && components.count < minimumComponents {
            return .blocked("is too close to the top of your home folder")
        }

        // --- 5. Structural directories ----------------------------------------
        if isDir.boolValue, let last = components.last, structuralNames.contains(last) {
            // Deleting e.g. ~/Library/Caches itself is never right; its children are.
            if inHome {
                return .blocked("is a structural system folder")
            }
        }

        // --- 6. A rule may never delete its own root ---------------------------
        if let root = ruleRoot {
            let r = URL(fileURLWithPath: root).standardizedFileURL.path
            if clean == r {
                return .blocked("is the rule's own root folder")
            }
            if !clean.hasPrefix(r + "/") {
                return .blocked("escaped the rule's root folder")
            }
        }

        // --- 7. Denylists -------------------------------------------------------
        if inHome {
            let rel = String(clean.dropFirst(home.count + 1))

            // Carve-outs are checked first and win.
            var carved = carveOuts.contains { rel == $0 || rel.hasPrefix($0 + "/") }

            // An uninstall may reach a leftover in a protected area, but only
            // if the uninstaller listed that exact path for this one app.
            if mode == .uninstall && uninstallAllowlist.contains(clean) {
                carved = true
            }

            if !carved {
                for p in neverTouch where rel == p || rel.hasPrefix(p + "/") {
                    return .blocked("is inside a protected area (\(p))")
                }
            }

            if mode == .automatic {
                for p in manualOnly where rel == p || rel.hasPrefix(p + "/") {
                    return .blocked("only removable by hand-picking it (\(p))")
                }
            }

            // Never remove a whole top-level home folder.
            if !rel.contains("/") {
                return .blocked("is a top-level folder in your home directory")
            }
        }

        // --- 8. Application bundles --------------------------------------------
        if clean.hasSuffix(".app") && mode != .uninstall {
            return .blocked("is an application bundle -- use the Uninstaller")
        }

        // --- 9. Currently running executable ------------------------------------
        if isInsideOurOwnBundle(clean) && mode != .uninstall {
            return .blocked("is part of Purge itself")
        }

        return .allowed
    }

    // MARK: - Helpers

    static func isSymlink(_ path: String) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return false }
        return (attrs[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    /// Walks up from `path` to `/` and reports whether any intermediate
    /// directory is a symlink. Cheap enough at the depths we work at.
    private static func parentChainContainsSymlink(_ path: String) -> Bool {
        var current = URL(fileURLWithPath: path).deletingLastPathComponent()
        var guardCount = 0
        while current.path != "/" && guardCount < 40 {
            if isSymlink(current.path) { return true }
            current = current.deletingLastPathComponent()
            guardCount += 1
        }
        return false
    }

    private static let ownBundlePath: String = Bundle.main.bundlePath

    private static func isInsideOurOwnBundle(_ path: String) -> Bool {
        guard !ownBundlePath.isEmpty, ownBundlePath != "/" else { return false }
        return path == ownBundlePath || path.hasPrefix(ownBundlePath + "/")
    }

    /// True when the app can read a path that normally needs Full Disk Access.
    /// Used purely to show a hint in the UI; nothing is deleted based on this.
    static func hasFullDiskAccess() -> Bool {
        let probe = (home as NSString)
            .appendingPathComponent("Library/Application Support/com.apple.TCC")
        return FileManager.default.isReadableFile(atPath: probe)
            || (try? FileManager.default.contentsOfDirectory(atPath: probe)) != nil
    }
}

private extension String {
    func trimmingTrailingSlash() -> String {
        var s = self
        while s.count > 1 && s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
