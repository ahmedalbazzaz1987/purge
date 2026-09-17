//
//  Finders.swift
//  Purge
//
//  Large & old files, and duplicate detection. Both are read-only searches;
//  nothing here removes a file. Removal always goes through Cleaner, in
//  .userSelected mode, on files the user ticked by hand.
//

import Foundation
import CryptoKit

// MARK: - Large & old files

final class LargeFileFinder {

    private let fm = FileManager.default
    private var cancelled = false

    func cancel() { cancelled = true }
    func reset() { cancelled = false }

    /// Folders worth searching. All inside home; the user picks which ones.
    static let searchableRoots: [(name: String, relative: String)] = [
        ("Downloads",        "Downloads"),
        ("Documents",        "Documents"),
        ("Desktop",          "Desktop"),
        ("Movies",           "Movies"),
        ("Music",            "Music"),
        ("Pictures",         "Pictures"),
        ("Application Support", "Library/Application Support"),
        ("Containers",       "Library/Containers"),
        ("Developer",        "Library/Developer"),
    ]

    struct Options {
        var roots: [String]        // absolute
        var minBytes: Int64 = 100 * 1024 * 1024
        var minAgeDays: Int = 0
        var limit: Int = 500
    }

    func find(_ options: Options, progress: ((String) -> Void)? = nil) -> [CleanItem] {
        var found: [CleanItem] = []
        let cutoff = options.minAgeDays > 0
            ? Date().addingTimeInterval(-Double(options.minAgeDays) * 86_400)
            : nil

        // Never descend into these: they are databases that look like folders.
        let opaquePackages: Set<String> = [
            "photoslibrary", "musiclibrary", "tvlibrary", "photolibrary",
            "aplibrary", "logicx", "fcpbundle", "sparsebundle",
        ]

        for root in options.roots {
            if cancelled { break }
            progress?(Format.shortPath(root))

            guard let e = fm.enumerator(at: URL(fileURLWithPath: root),
                                        includingPropertiesForKeys: [.isRegularFileKey,
                                                                     .isSymbolicLinkKey,
                                                                     .totalFileAllocatedSizeKey,
                                                                     .contentModificationDateKey],
                                        options: [.skipsPackageDescendants],
                                        errorHandler: { _, _ in true })
            else { continue }

            for case let url as URL in e {
                if cancelled { break }

                let ext = url.pathExtension.lowercased()
                if opaquePackages.contains(ext) {
                    e.skipDescendants()
                    // The library itself is still worth reporting.
                    let size = Scanner().directorySize(url.path)
                    if size >= options.minBytes {
                        found.append(CleanItem(path: url.path,
                                               displayName: url.lastPathComponent,
                                               bytes: size,
                                               isDirectory: true,
                                               modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate))
                    }
                    continue
                }

                guard let v = try? url.resourceValues(forKeys: [.isRegularFileKey,
                                                                .isSymbolicLinkKey,
                                                                .totalFileAllocatedSizeKey,
                                                                .contentModificationDateKey])
                else { continue }

                if v.isSymbolicLink == true { continue }
                guard v.isRegularFile == true else { continue }

                let size = Int64(v.totalFileAllocatedSize ?? 0)
                guard size >= options.minBytes else { continue }

                let modified = v.contentModificationDate
                if let cutoff, let modified, modified > cutoff { continue }

                found.append(CleanItem(path: url.path,
                                       displayName: url.lastPathComponent,
                                       bytes: size,
                                       isDirectory: false,
                                       modified: modified))

                if found.count >= options.limit * 3 { break }
            }
        }

        return Array(found.sorted { $0.bytes > $1.bytes }.prefix(options.limit))
    }
}

// MARK: - Duplicates

struct DuplicateSet: Identifiable {
    let id = UUID()
    let items: [CleanItem]          // first one is the keeper
    var wastedBytes: Int64 {
        guard let first = items.first else { return 0 }
        return first.bytes * Int64(max(items.count - 1, 0))
    }
    var keeper: CleanItem? { items.first }
    var extras: [CleanItem] { Array(items.dropFirst()) }
}

final class DuplicateFinder {

    private let fm = FileManager.default
    private var cancelled = false

    func cancel() { cancelled = true }
    func reset() { cancelled = false }

    /// Three passes: group by size, then by a cheap head+tail hash, then by a
    /// full SHA-256. Only files that survive all three are called duplicates.
    func find(roots: [String],
              minBytes: Int64 = 1024 * 1024,
              progress: ((String) -> Void)? = nil) -> [DuplicateSet] {

        // Pass 1 — size buckets
        var bySize: [Int64: [String]] = [:]
        for root in roots {
            if cancelled { break }
            progress?("Listing \(Format.shortPath(root))")
            guard let e = fm.enumerator(at: URL(fileURLWithPath: root),
                                        includingPropertiesForKeys: [.isRegularFileKey,
                                                                     .isSymbolicLinkKey,
                                                                     .fileSizeKey],
                                        options: [.skipsPackageDescendants, .skipsHiddenFiles],
                                        errorHandler: { _, _ in true })
            else { continue }

            for case let url as URL in e {
                if cancelled { break }
                guard let v = try? url.resourceValues(forKeys: [.isRegularFileKey,
                                                                .isSymbolicLinkKey,
                                                                .fileSizeKey]),
                      v.isSymbolicLink != true,
                      v.isRegularFile == true,
                      let size = v.fileSize, Int64(size) >= minBytes
                else { continue }
                bySize[Int64(size), default: []].append(url.path)
            }
        }

        let candidates = bySize.filter { $0.value.count > 1 }
        guard !candidates.isEmpty else { return [] }

        // Pass 2 — partial hash
        var byPartial: [String: [String]] = [:]
        var done = 0
        for (size, paths) in candidates {
            if cancelled { break }
            done += 1
            progress?("Comparing \(done) of \(candidates.count) size groups")
            for p in paths {
                guard let h = partialHash(p, size: size) else { continue }
                byPartial["\(size)-\(h)", default: []].append(p)
            }
        }

        // Pass 3 — full hash
        var byFull: [String: [String]] = [:]
        for (_, paths) in byPartial where paths.count > 1 {
            if cancelled { break }
            progress?("Verifying \(paths.count) possible matches")
            for p in paths {
                guard let h = fullHash(p) else { continue }
                byFull[h, default: []].append(p)
            }
        }

        // Build result
        var sets: [DuplicateSet] = []
        for (_, paths) in byFull where paths.count > 1 {
            // Oldest file wins the "keeper" slot — it is usually the original.
            let items: [CleanItem] = paths.compactMap { path in
                let attrs = try? fm.attributesOfItem(atPath: path)
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                return CleanItem(path: path,
                                 displayName: (path as NSString).lastPathComponent,
                                 bytes: size,
                                 isDirectory: false,
                                 modified: attrs?[.modificationDate] as? Date)
            }
            .sorted { ($0.modified ?? .distantFuture) < ($1.modified ?? .distantFuture) }

            if items.count > 1 { sets.append(DuplicateSet(items: items)) }
        }

        return sets.sorted { $0.wastedBytes > $1.wastedBytes }
    }

    private func partialHash(_ path: String, size: Int64) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let chunk = 64 * 1024
        var hasher = SHA256()
        guard let head = try? handle.read(upToCount: chunk) else { return nil }
        hasher.update(data: head)
        if size > Int64(chunk) * 2 {
            try? handle.seek(toOffset: UInt64(size) - UInt64(chunk))
            if let tail = try? handle.read(upToCount: chunk) { hasher.update(data: tail) }
        }
        return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
    }

    private func fullHash(_ path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            if cancelled { return nil }
            guard let data = try? handle.read(upToCount: 4 * 1024 * 1024), !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
    }
}
