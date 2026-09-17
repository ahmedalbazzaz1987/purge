//
//  Scanner.swift
//  Purge
//
//  Turns rules into concrete, sized items. Read-only: the scanner never
//  deletes anything and never follows a symbolic link.
//

import Foundation

final class Scanner {

    private let fm = FileManager.default
    private var cancelled = false

    func cancel() { cancelled = true }
    func reset() { cancelled = false }

    // MARK: - Pattern expansion

    /// Expands `~`, `$TMP` and `*` components into real, existing paths.
    func expand(_ pattern: String) -> [String] {
        var p = pattern

        if p.hasPrefix("~/") {
            p = SafetyGuard.home + String(p.dropFirst(1))
        } else if p.hasPrefix("$TMP/") {
            guard let tmp = SafetyGuard.userTempRoot else { return [] }
            p = tmp + String(p.dropFirst(4))
        } else if !p.hasPrefix("/") {
            return []
        }

        guard p.contains("*") else {
            return fm.fileExists(atPath: p) ? [p] : []
        }

        // Walk component by component, branching on every `*`.
        let comps = p.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var frontier = ["/"]

        for comp in comps {
            if cancelled { return [] }
            var next: [String] = []
            for base in frontier {
                if comp == "*" {
                    guard let kids = try? fm.contentsOfDirectory(atPath: base) else { continue }
                    for k in kids where !k.hasPrefix(".") {
                        next.append((base as NSString).appendingPathComponent(k))
                    }
                } else {
                    let candidate = (base as NSString).appendingPathComponent(comp)
                    if fm.fileExists(atPath: candidate) { next.append(candidate) }
                }
            }
            frontier = next
            if frontier.isEmpty { break }
        }
        return frontier
    }

    // MARK: - Scanning

    /// Produces one group per rule. Groups with nothing in them are dropped.
    func scan(rules: [CleanRule],
              progress: ((String, Double) -> Void)? = nil) -> [CleanGroup] {

        var groups: [CleanGroup] = []
        let total = max(rules.count, 1)

        // Shared across every rule in one scan, so a path two rules both match
        // is listed once, counted once, and removed once.
        var seen = Set<String>()

        for (index, rule) in rules.enumerated() {
            if cancelled { break }
            progress?(rule.title, Double(index) / Double(total))

            var items: [CleanItem] = []

            for pattern in rule.targets {
                if cancelled { break }
                for root in expand(pattern) {
                    if cancelled { break }
                    let mode: RemovalMode = rule.module == .trashBin ? .userSelected : .automatic
                    items.append(contentsOf: candidates(in: root,
                                                        rule: rule,
                                                        mode: mode,
                                                        seen: &seen))
                }
            }

            guard !items.isEmpty else { continue }
            items.sort { $0.bytes > $1.bytes }

            groups.append(CleanGroup(ruleID: rule.id,
                                     title: rule.title,
                                     detail: rule.detail,
                                     risk: rule.risk,
                                     module: rule.module,
                                     items: items))
        }

        progress?("Done", 1.0)
        return groups.sorted { $0.bytes > $1.bytes }
    }

    private func candidates(in root: String,
                            rule: CleanRule,
                            mode: RemovalMode,
                            seen: inout Set<String>) -> [CleanItem] {

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root, isDirectory: &isDir) else { return [] }

        // A pattern that resolved to a plain file is itself the candidate,
        // whatever the rule's granularity says.
        let paths: [String]
        if !isDir.boolValue || rule.granularity == .itself {
            paths = [root]
        } else {
            guard let kids = try? fm.contentsOfDirectory(atPath: root) else { return [] }
            paths = kids.map { (root as NSString).appendingPathComponent($0) }
        }

        let cutoff = rule.minAgeDays > 0
            ? Date().addingTimeInterval(-Double(rule.minAgeDays) * 86_400)
            : nil

        var result: [CleanItem] = []

        for path in paths {
            if cancelled { break }
            let name = (path as NSString).lastPathComponent

            if rule.excluded.contains(name) { continue }
            if name == ".DS_Store" && rule.granularity == .childrenOf && paths.count > 1 { continue }
            if seen.contains(path) { continue }

            // The scanner asks the guard the same question the cleaner will ask.
            // Anything the guard would refuse is never even shown.
            let ruleRoot = (rule.granularity == .childrenOf && isDir.boolValue) ? root : nil
            guard SafetyGuard.approve(path, mode: mode, ruleRoot: ruleRoot).isAllowed else { continue }

            let attrs = try? fm.attributesOfItem(atPath: path)
            let modified = attrs?[.modificationDate] as? Date
            if let cutoff, let modified, modified > cutoff { continue }

            var childIsDir: ObjCBool = false
            _ = fm.fileExists(atPath: path, isDirectory: &childIsDir)
            let size = childIsDir.boolValue ? directorySize(path) : fileSize(path)
            if size < rule.minBytes { continue }
            if size == 0 && !childIsDir.boolValue { continue }

            seen.insert(path)
            result.append(CleanItem(path: path,
                                    displayName: name,
                                    bytes: size,
                                    isDirectory: childIsDir.boolValue,
                                    modified: modified))
        }

        return result
    }

    // MARK: - Sizes

    func fileSize(_ path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return 0 }
        return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? v.fileSize ?? 0)
    }

    /// Recursive allocated size. Skips symlinks and package-internal recursion limits.
    func directorySize(_ path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        guard let e = fm.enumerator(at: url,
                                    includingPropertiesForKeys: [.totalFileAllocatedSizeKey,
                                                                 .fileAllocatedSizeKey,
                                                                 .isRegularFileKey,
                                                                 .isSymbolicLinkKey],
                                    options: [],
                                    errorHandler: { _, _ in true })
        else { return 0 }

        var total: Int64 = 0
        var counted = 0
        for case let child as URL in e {
            if cancelled { break }
            counted += 1
            if counted > 400_000 { break }   // pathological trees: stop, report what we have
            guard let v = try? child.resourceValues(forKeys: [.totalFileAllocatedSizeKey,
                                                              .fileAllocatedSizeKey,
                                                              .isRegularFileKey,
                                                              .isSymbolicLinkKey])
            else { continue }
            if v.isSymbolicLink == true { continue }
            if v.isRegularFile == true {
                total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            }
        }
        return total
    }

    // MARK: - Disk

    struct DiskInfo {
        let total: Int64
        let free: Int64
        var used: Int64 { total - free }
        var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    }

    static func diskInfo() -> DiskInfo {
        let url = URL(fileURLWithPath: SafetyGuard.home)
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? url.resourceValues(forKeys: keys) else {
            return DiskInfo(total: 0, free: 0)
        }
        let total = Int64(v.volumeTotalCapacity ?? 0)
        let free = v.volumeAvailableCapacityForImportantUsage ?? 0
        return DiskInfo(total: total, free: Int64(free))
    }
}
