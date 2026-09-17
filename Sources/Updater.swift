//
//  Updater.swift
//  Purge
//
//  Checks GitHub Releases for a newer build, downloads the attached zip,
//  verifies it is really a newer Purge, and swaps the bundle in place.
//
//  Nothing is downloaded or installed without the user pressing a button.
//

import Foundation
import AppKit

struct ReleaseInfo {
    let version: String
    let tag: String
    let notes: String
    let pageURL: URL
    let assetURL: URL?
    let assetName: String?
    let publishedAt: Date?
}

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate(String)
    case available(String)
    case downloading(Double)
    case installing
    case readyToRelaunch
    case failed(String)
}

@MainActor
final class Updater: ObservableObject {

    @Published var state: UpdateState = .idle
    @Published var latest: ReleaseInfo?
    @Published var lastChecked: Date?

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 600
        return URLSession(configuration: c)
    }()

    // MARK: - Checking

    func check(owner: String, repo: String, silent: Bool = false) async {
        let o = owner.trimmingCharacters(in: .whitespaces)
        let r = repo.trimmingCharacters(in: .whitespaces)
        guard !o.isEmpty, !r.isEmpty else {
            state = .failed("Set your GitHub owner and repository in Settings first.")
            return
        }
        guard let url = URL(string: "https://api.github.com/repos/\(o)/\(r)/releases/latest") else {
            state = .failed("That owner/repository pair is not a valid URL.")
            return
        }

        if !silent { state = .checking }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Purge/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                state = .failed("No response from GitHub.")
                return
            }
            if http.statusCode == 404 {
                state = .failed("No published release found at \(o)/\(r).")
                return
            }
            guard http.statusCode == 200 else {
                state = .failed("GitHub replied \(http.statusCode).")
                return
            }

            guard let info = Self.parse(data) else {
                state = .failed("Could not read GitHub's answer.")
                return
            }

            latest = info
            lastChecked = Date()

            if Self.isNewer(info.version, than: AppInfo.version) {
                state = .available(info.version)
            } else {
                state = .upToDate(AppInfo.version)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    static func parse(_ data: Data) -> ReleaseInfo? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let tag = (root["tag_name"] as? String) ?? ""
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard !version.isEmpty else { return nil }

        let notes = (root["body"] as? String) ?? ""
        let page = URL(string: (root["html_url"] as? String) ?? "https://github.com")!

        var assetURL: URL?
        var assetName: String?
        if let assets = root["assets"] as? [[String: Any]] {
            // Prefer a zip that mentions the app by name.
            let zips = assets.filter { (($0["name"] as? String) ?? "").hasSuffix(".zip") }
            let best = zips.first { (($0["name"] as? String) ?? "").localizedCaseInsensitiveContains("purge") }
                ?? zips.first
            if let best,
               let s = best["browser_download_url"] as? String,
               let u = URL(string: s) {
                assetURL = u
                assetName = best["name"] as? String
            }
        }

        var published: Date?
        if let s = root["published_at"] as? String {
            published = ISO8601DateFormatter().date(from: s)
        }

        return ReleaseInfo(version: version, tag: tag, notes: notes,
                           pageURL: page, assetURL: assetURL,
                           assetName: assetName, publishedAt: published)
    }

    /// Plain numeric comparison: 1.10.0 beats 1.9.3.
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(whereSeparator: { !$0.isNumber }).map { Int($0) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    // MARK: - Installing

    func downloadAndInstall() async {
        guard let info = latest else { return }
        guard let assetURL = info.assetURL else {
            state = .failed("That release has no .zip attached. Open it on GitHub and install by hand.")
            return
        }
        guard Bundle.main.bundlePath.hasSuffix(".app") else {
            state = .failed("Purge is not running from an .app bundle, so it cannot replace itself.")
            return
        }

        state = .downloading(0)

        do {
            let (tempFile, response) = try await session.download(from: assetURL)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                state = .failed("Download failed (\(http.statusCode)).")
                return
            }

            state = .installing

            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("purge-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

            let zip = work.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: tempFile, to: zip)

            // ditto handles macOS archives correctly, keeping symlinks and
            // resource forks that would break a naive unzip.
            let extracted = work.appendingPathComponent("extracted")
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, extracted.path])

            guard let newApp = try findApp(in: extracted) else {
                state = .failed("No Purge.app inside the downloaded archive.")
                return
            }

            // Verify before trusting it.
            guard let bundle = Bundle(url: newApp),
                  bundle.bundleIdentifier == AppInfo.bundleID else {
                state = .failed("The downloaded app is not Purge. Nothing was installed.")
                return
            }
            let newVersion = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
            guard Self.isNewer(newVersion, than: AppInfo.version) else {
                state = .failed("The downloaded build (\(newVersion)) is not newer than \(AppInfo.version).")
                return
            }

            // Downloaded bundles carry a quarantine flag that would make macOS
            // refuse to launch the replacement silently.
            _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

            try scheduleSwap(newApp: newApp, work: work)
            state = .readyToRelaunch
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func findApp(in directory: URL) throws -> URL? {
        let fm = FileManager.default
        if let top = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            if let direct = top.first(where: { $0.pathExtension == "app" }) { return direct }
            for sub in top where (try? sub.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                if let nested = try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil),
                   let hit = nested.first(where: { $0.pathExtension == "app" }) {
                    return hit
                }
            }
        }
        return nil
    }

    /// Writes a detached script that waits for this process to exit, swaps the
    /// bundle, and relaunches. Called only after every check above passed.
    private func scheduleSwap(newApp: URL, work: URL) throws {
        let current = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let backup = work.appendingPathComponent("previous.app").path

        let script = """
        #!/bin/sh
        while kill -0 \(pid) 2>/dev/null; do sleep 0.3; done
        sleep 0.5
        /bin/mv "\(current)" "\(backup)" 2>/dev/null || /bin/rm -rf "\(current)"
        if /usr/bin/ditto "\(newApp.path)" "\(current)"; then
          /bin/rm -rf "\(backup)" 2>/dev/null || true
        else
          # Put the old one back rather than leaving the user with nothing.
          if [ -d "\(backup)" ]; then /bin/mv "\(backup)" "\(current)"; fi
        fi
        /usr/bin/xattr -dr com.apple.quarantine "\(current)" 2>/dev/null || true
        /usr/bin/open "\(current)"
        sleep 2
        /bin/rm -rf "\(work.path)"
        """

        let url = work.appendingPathComponent("swap.sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [url.path]
        try task.run()
    }

    func relaunch() {
        NSApp.terminate(nil)
    }

    @discardableResult
    private func run(_ tool: String, _ args: [String]) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        if task.terminationStatus != 0 {
            throw NSError(domain: "Purge", code: Int(task.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey:
                            "\((tool as NSString).lastPathComponent) failed: \(out)"])
        }
        return out
    }
}
