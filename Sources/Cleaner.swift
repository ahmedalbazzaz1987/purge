//
//  Cleaner.swift
//  Purge
//
//  The only code in the app that removes anything. Every path is re-validated
//  by SafetyGuard immediately before removal — the scan result is treated as a
//  suggestion, never as permission.
//

import Foundation
import AppKit

enum RemovalMethod: String, CaseIterable, Identifiable {
    case trash
    case permanent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trash:     return "Move to Trash"
        case .permanent: return "Delete permanently"
        }
    }

    var explanation: String {
        switch self {
        case .trash:
            return "Reversible. Nothing is really gone until you empty the Trash — which also means the space is not free until then."
        case .permanent:
            return "Frees the space immediately. There is no undo, so Purge shows you every file first."
        }
    }
}

final class Cleaner {

    private let fm = FileManager.default

    /// Removes the given items. `dryRun` walks the whole path without touching disk.
    ///
    /// - Parameter userSelectedPaths: items the user ticked by hand in a place
    ///   an automatic rule is not allowed to sweep (the Trash, for instance).
    ///   They are judged as `.userSelected` even when the rest of the pass is
    ///   automatic, so one clean never silently upgrades the whole batch.
    func remove(_ items: [CleanItem],
                mode: RemovalMode,
                method: RemovalMethod,
                dryRun: Bool,
                userSelectedPaths: Set<String> = [],
                progress: ((Double, String) -> Void)? = nil) -> RemovalReport {

        var report = RemovalReport()
        let total = max(items.count, 1)

        for (i, item) in items.enumerated() {
            progress?(Double(i) / Double(total), item.displayName)

            // Re-ask. Disk state may have changed since the scan.
            let itemMode: RemovalMode = userSelectedPaths.contains(item.path) ? .userSelected : mode
            let verdict = SafetyGuard.approve(item.path, mode: itemMode)
            guard verdict.isAllowed else {
                report.skipped.append((item.path, verdict.reason ?? "refused"))
                ActionLog.shared.write("SKIP  \(verdict.reason ?? "refused")  \(item.path)")
                continue
            }

            if dryRun {
                report.removed += 1
                report.freed += item.bytes
                ActionLog.shared.write("DRY   would remove \(Format.bytes(item.bytes))  \(item.path)")
                continue
            }

            do {
                switch method {
                case .trash:
                    var resulting: NSURL?
                    try fm.trashItem(at: item.url, resultingItemURL: &resulting)
                case .permanent:
                    try fm.removeItem(at: item.url)
                }
                report.removed += 1
                report.freed += item.bytes
                ActionLog.shared.write("\(method == .trash ? "TRASH" : "DELETE") \(Format.bytes(item.bytes))  \(item.path)")
            } catch {
                let reason = (error as NSError).localizedDescription
                report.failed.append((item.path, reason))
                ActionLog.shared.write("FAIL  \(reason)  \(item.path)")
            }
        }

        progress?(1.0, "")
        ActionLog.shared.write("---   pass finished: \(report.removed) removed, \(report.freedText) freed, \(report.failed.count) failed, \(report.skipped.count) skipped")
        return report
    }
}

// MARK: - Action log
//
// A plain-text record of everything Purge has ever removed, kept in the one
// folder the self-uninstaller deletes.

final class ActionLog {

    static let shared = ActionLog()
    private let queue = DispatchQueue(label: "purge.log")
    private let url: URL

    private init() {
        url = AppInfo.supportDirectory.appendingPathComponent("purge.log")
    }

    var fileURL: URL { url }

    func write(_ line: String) {
        queue.async {
            let stamp = ISO8601DateFormatter().string(from: Date())
            let text = "[\(stamp)] \(line)\n"
            do {
                try FileManager.default.createDirectory(at: AppInfo.supportDirectory,
                                                        withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: self.url.path),
                   let handle = try? FileHandle(forWritingTo: self.url) {
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    if let d = text.data(using: .utf8) { try handle.write(contentsOf: d) }
                } else {
                    try text.write(to: self.url, atomically: true, encoding: .utf8)
                }
            } catch {
                // Logging must never break a clean.
            }
        }
    }

    func read(limit: Int = 500) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Nothing removed yet."
        }
        let lines = text.split(separator: "\n").suffix(limit)
        return lines.joined(separator: "\n")
    }

    func clear() {
        queue.async { try? FileManager.default.removeItem(at: self.url) }
    }
}
