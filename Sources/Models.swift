//
//  Models.swift
//  Purge
//

import Foundation
import SwiftUI

// MARK: - Version

enum AppInfo {
    static let name = "Purge"
    static let version = "1.0.3"
    static let bundleID = "com.novamira.purge"
    static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    /// Every file Purge is allowed to create on this Mac. Used by the self-uninstaller.
    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Purge", isDirectory: true)
    }
}

// MARK: - Update schedule

/// How often Purge looks for a new release. Checks only ever happen while the
/// app is open — Purge installs no background agent, so nothing runs when it is
/// closed. A due check fires at launch and then on the interval.
enum UpdateFrequency: String, CaseIterable, Identifiable {
    case never
    case launch
    case daily
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never:  return "Never"
        case .launch: return "Every launch"
        case .daily:  return "Once a day"
        case .weekly: return "Once a week"
        }
    }

    var detail: String {
        switch self {
        case .never:  return "Only when you press Check yourself."
        case .launch: return "One check each time Purge starts."
        case .daily:  return "At launch, and again after 24 hours if Purge stays open."
        case .weekly: return "At launch, and again after 7 days if Purge stays open."
        }
    }

    private var interval: TimeInterval? {
        switch self {
        case .never:  return nil
        case .launch: return nil
        case .daily:  return 24 * 3600
        case .weekly: return 7 * 24 * 3600
        }
    }

    /// True when enough time has passed (or nothing has ever been checked).
    func isDue(since last: Date?) -> Bool {
        switch self {
        case .never:  return false
        case .launch: return true
        default:
            guard let interval else { return false }
            guard let last else { return true }
            return Date().timeIntervalSince(last) >= interval
        }
    }
}

// MARK: - Categories

enum ModuleKind: String, CaseIterable, Identifiable {
    case smartScan
    case systemJunk
    case browserData
    case developerJunk
    case trashBin
    case largeFiles
    case duplicates
    case uninstaller
    case startupItems
    case updates
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartScan:      return "Smart Scan"
        case .systemJunk:     return "System Junk"
        case .browserData:    return "Browser Data"
        case .developerJunk:  return "Developer Junk"
        case .trashBin:       return "Trash"
        case .largeFiles:     return "Large & Old Files"
        case .duplicates:     return "Duplicates"
        case .uninstaller:    return "Uninstaller"
        case .startupItems:   return "Startup Items"
        case .updates:        return "Updates"
        case .settings:       return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .smartScan:      return "sparkles"
        case .systemJunk:     return "internaldrive"
        case .browserData:    return "safari"
        case .developerJunk:  return "hammer"
        case .trashBin:       return "trash"
        case .largeFiles:     return "chart.pie"
        case .duplicates:     return "square.on.square"
        case .uninstaller:    return "xmark.bin"
        case .startupItems:   return "bolt"
        case .updates:        return "arrow.triangle.2.circlepath"
        case .settings:       return "gearshape"
        }
    }

    var blurb: String {
        switch self {
        case .smartScan:     return "Run every safe cleaner at once"
        case .systemJunk:    return "Caches, logs, temporary and update leftovers"
        case .browserData:   return "Cached web data — logins and bookmarks untouched"
        case .developerJunk: return "Xcode, simulators, npm, pip, Homebrew caches"
        case .trashBin:      return "Empty the Trash for good"
        case .largeFiles:    return "Find what is actually eating your disk"
        case .duplicates:    return "Identical files, kept one copy"
        case .uninstaller:   return "Remove an app and every trace of it"
        case .startupItems:  return "What launches when you log in"
        case .updates:       return "Check GitHub for a newer version"
        case .settings:      return "Behaviour, safety and removing Purge"
        }
    }

    /// Modules that participate in Smart Scan.
    static let smartScanMembers: [ModuleKind] = [.systemJunk, .browserData, .developerJunk, .trashBin]
}

/// Risk tier shown next to every group so nothing is a surprise.
enum RiskTier: Int, Comparable {
    case safe = 0        // regenerated automatically, no user-visible effect
    case mild = 1        // you may notice a slower first launch or a re-login
    case review = 2      // never pre-selected; user must opt in per item

    static func < (a: RiskTier, b: RiskTier) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .safe:   return "Safe"
        case .mild:   return "Minor effect"
        case .review: return "Review first"
        }
    }

    var color: Color {
        switch self {
        case .safe:   return Theme.green
        case .mild:   return Theme.amber
        case .review: return Theme.red
        }
    }

    var note: String {
        switch self {
        case .safe:   return "Rebuilt automatically the next time the app needs it."
        case .mild:   return "Harmless, but the first launch afterwards may be a little slower."
        case .review: return "Never selected for you. Check each item before removing it."
        }
    }
}

// MARK: - Items

/// One removable thing found on disk.
struct CleanItem: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let displayName: String
    let bytes: Int64
    let isDirectory: Bool
    let modified: Date?

    var url: URL { URL(fileURLWithPath: path) }
    var sizeText: String { Format.bytes(bytes) }

    static func == (a: CleanItem, b: CleanItem) -> Bool { a.path == b.path }
    func hash(into h: inout Hasher) { h.combine(path) }
}

/// A named bucket of items produced by one rule.
struct CleanGroup: Identifiable {
    let id = UUID()
    let ruleID: String
    let title: String
    let detail: String
    let risk: RiskTier
    let module: ModuleKind
    var items: [CleanItem]

    var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    var sizeText: String { Format.bytes(bytes) }
    var isEmpty: Bool { items.isEmpty }
}

// MARK: - Results of a removal pass

struct RemovalReport {
    var removed: Int = 0
    var freed: Int64 = 0
    var skipped: [(path: String, reason: String)] = []
    var failed: [(path: String, reason: String)] = []

    var freedText: String { Format.bytes(freed) }
}

// MARK: - Formatting

enum Format {
    private static let bcf: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return f
    }()

    static func bytes(_ v: Int64) -> String {
        if v <= 0 { return "0 KB" }
        return bcf.string(fromByteCount: v)
    }

    static func age(_ date: Date?) -> String {
        guard let date else { return "—" }
        let days = Int(Date().timeIntervalSince(date) / 86_400)
        if days < 1 { return "today" }
        if days == 1 { return "1 day ago" }
        if days < 30 { return "\(days) days ago" }
        if days < 365 { return "\(days / 30) mo ago" }
        let y = days / 365
        return y == 1 ? "1 year ago" : "\(y) years ago"
    }

    static func shortPath(_ path: String) -> String {
        let home = SafetyGuard.home
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }
}
