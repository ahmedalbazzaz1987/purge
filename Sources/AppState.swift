//
//  AppState.swift
//  Purge
//
//  One observable object holds everything the views read. All disk work runs
//  off the main thread; only published properties cross back.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {

    // Navigation
    @Published var selection: ModuleKind = .smartScan

    // Scanning
    @Published var isScanning = false
    @Published var scanProgress: Double = 0
    @Published var scanLabel: String = ""
    @Published var groups: [CleanGroup] = []
    @Published var selectedPaths: Set<String> = []
    @Published var expandedGroups: Set<String> = []
    @Published var lastScanModule: ModuleKind?

    // Cleaning
    @Published var isCleaning = false
    @Published var cleanProgress: Double = 0
    @Published var cleanLabel: String = ""
    @Published var lastReport: RemovalReport?
    @Published var showReport = false

    // Disk
    @Published var disk = Scanner.diskInfo()

    // Large files
    @Published var largeFiles: [CleanItem] = []
    @Published var largeSelected: Set<String> = []
    @Published var isFindingLarge = false
    @Published var largeStatus = ""
    @Published var largeRoots: Set<String> = ["Downloads", "Documents", "Movies"]
    @Published var largeMinMB: Double = 100
    @Published var largeMinAge: Double = 0

    // Duplicates
    @Published var duplicateSets: [DuplicateSet] = []
    @Published var duplicateSelected: Set<String> = []
    @Published var isFindingDuplicates = false
    @Published var duplicateStatus = ""

    // Uninstaller
    @Published var apps: [AppTarget] = []
    @Published var chosenApp: AppTarget?
    @Published var appLeftovers: [CleanItem] = []
    @Published var appLeftoverSelected: Set<String> = []
    @Published var appSearch = ""
    @Published var isLoadingApps = false

    // Startup
    @Published var startupItems: [StartupItem] = []

    // Settings. Published so the interface reacts, and written straight through
    // to UserDefaults so the self-uninstaller has exactly one plist to remove.
    @Published var removalMethod: RemovalMethod = .trash { didSet { save("removalMethod", removalMethod.rawValue) } }
    @Published var dryRun: Bool = false                  { didSet { save("dryRun", dryRun) } }
    @Published var confirmBefore: Bool = true            { didSet { save("confirmBefore", confirmBefore) } }
    @Published var githubOwner: String = "ahmedalbazzaz" { didSet { save("githubOwner", githubOwner) } }
    @Published var githubRepo: String = "purge"          { didSet { save("githubRepo", githubRepo) } }
    @Published var updateFrequency: UpdateFrequency = .daily { didSet { save("updateFrequency", updateFrequency.rawValue) } }

    /// When the last successful check ran. Lives in the same plist as the rest,
    /// so removing Purge still removes everything.
    var lastUpdateCheck: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: "lastUpdateCheck")
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "lastUpdateCheck")
        }
    }

    var isUpdateCheckDue: Bool { updateFrequency.isDue(since: lastUpdateCheck) }

    private var loadingDefaults = false
    private func save(_ key: String, _ value: Any) {
        guard !loadingDefaults else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    init() {
        loadingDefaults = true
        let d = UserDefaults.standard
        if let raw = d.string(forKey: "removalMethod"), let m = RemovalMethod(rawValue: raw) {
            removalMethod = m
        }
        if d.object(forKey: "dryRun") != nil        { dryRun = d.bool(forKey: "dryRun") }
        if d.object(forKey: "confirmBefore") != nil { confirmBefore = d.bool(forKey: "confirmBefore") }
        if let raw = d.string(forKey: "updateFrequency"), let f = UpdateFrequency(rawValue: raw) {
            updateFrequency = f
        } else if d.object(forKey: "checkOnLaunch") != nil {
            // Carried over from the older on/off setting.
            updateFrequency = d.bool(forKey: "checkOnLaunch") ? .launch : .never
        }
        if let s = d.string(forKey: "githubOwner"), !s.isEmpty { githubOwner = s }
        if let s = d.string(forKey: "githubRepo"),  !s.isEmpty { githubRepo = s }
        loadingDefaults = false
    }

    // Workers
    private var scanner = Scanner()
    private let cleaner = Cleaner()
    private var largeFinder = LargeFileFinder()
    private var dupFinder = DuplicateFinder()
    let appUninstaller = AppUninstaller()

    // MARK: - Derived

    var selectedItems: [CleanItem] {
        groups.flatMap(\.items).filter { selectedPaths.contains($0.path) }
    }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.bytes } }
    var foundBytes: Int64 { groups.reduce(0) { $0 + $1.bytes } }
    var foundCount: Int { groups.reduce(0) { $0 + $1.items.count } }

    func groupState(_ group: CleanGroup) -> (all: Bool, some: Bool) {
        let paths = Set(group.items.map(\.path))
        let hit = paths.intersection(selectedPaths).count
        return (hit == paths.count && hit > 0, hit > 0 && hit < paths.count)
    }

    // MARK: - Scanning

    func scan(_ module: ModuleKind) {
        guard !isScanning else { return }
        let rules = Rules.rules(for: module)
        guard !rules.isEmpty else { return }

        isScanning = true
        scanProgress = 0
        scanLabel = "Starting"
        groups = []
        selectedPaths = []
        lastScanModule = module
        lastReport = nil

        let s = Scanner()
        scanner = s

        Task.detached(priority: .userInitiated) {
            let found = s.scan(rules: rules) { label, progress in
                Task { @MainActor in
                    self.scanLabel = label
                    self.scanProgress = progress
                }
            }
            await MainActor.run {
                self.groups = found
                // Pre-tick everything the matching rule marks as preselected.
                var preset = Set<String>()
                for g in found {
                    guard let rule = rules.first(where: { $0.id == g.ruleID }), rule.preselected else { continue }
                    preset.formUnion(g.items.map(\.path))
                }
                self.selectedPaths = preset
                self.expandedGroups = Set(found.prefix(2).map(\.ruleID))
                self.isScanning = false
                self.scanLabel = ""
                self.disk = Scanner.diskInfo()
            }
        }
    }

    func cancelScan() {
        scanner.cancel()
        isScanning = false
    }

    func toggle(_ item: CleanItem) {
        if selectedPaths.contains(item.path) { selectedPaths.remove(item.path) }
        else { selectedPaths.insert(item.path) }
    }

    func toggle(group: CleanGroup) {
        let paths = Set(group.items.map(\.path))
        if paths.isSubset(of: selectedPaths) { selectedPaths.subtract(paths) }
        else { selectedPaths.formUnion(paths) }
    }

    func selectAll(safeOnly: Bool) {
        var paths = Set<String>()
        for g in groups where !safeOnly || g.risk == .safe {
            paths.formUnion(g.items.map(\.path))
        }
        selectedPaths = paths
    }

    func clearSelection() { selectedPaths = [] }

    // MARK: - Cleaning

    func clean() {
        let items = selectedItems
        guard !items.isEmpty, !isCleaning else { return }

        isCleaning = true
        cleanProgress = 0
        let method = removalMethod
        let dry = dryRun

        // Trash contents can never be swept automatically, so anything that
        // came from that group is carried as an explicit hand-picked item.
        let handPicked = Set(groups.filter { $0.module == .trashBin }
                                   .flatMap { $0.items.map(\.path) })

        // Hand the worker over here, on the main actor, rather than reaching
        // back for it from the detached task.
        let worker = cleaner

        Task.detached(priority: .userInitiated) {
            let report = worker.remove(items, mode: .automatic, method: method,
                                       dryRun: dry, userSelectedPaths: handPicked) { p, label in
                Task { @MainActor in
                    self.cleanProgress = p
                    self.cleanLabel = label
                }
            }
            await MainActor.run {
                self.lastReport = report
                self.isCleaning = false
                self.cleanLabel = ""
                self.showReport = true
                self.disk = Scanner.diskInfo()
                if !dry { self.removeCleanedFromGroups(report) }
            }
        }
    }

    private func removeCleanedFromGroups(_ report: RemovalReport) {
        let stillThere = Set(report.failed.map(\.path) + report.skipped.map(\.path))
        groups = groups.compactMap { g in
            var copy = g
            copy.items = g.items.filter { item in
                !selectedPaths.contains(item.path) || stillThere.contains(item.path)
            }
            return copy.items.isEmpty ? nil : copy
        }
        selectedPaths = selectedPaths.intersection(stillThere)
    }

    /// Used by Large Files, Duplicates and Startup Items — always .userSelected.
    func removeHandPicked(_ items: [CleanItem], completion: @escaping (RemovalReport) -> Void) {
        guard !items.isEmpty else { return }
        isCleaning = true
        let method = removalMethod
        let dry = dryRun
        let worker = cleaner
        Task.detached(priority: .userInitiated) {
            let report = worker.remove(items, mode: .userSelected, method: method, dryRun: dry) { p, label in
                Task { @MainActor in
                    self.cleanProgress = p
                    self.cleanLabel = label
                }
            }
            await MainActor.run {
                self.isCleaning = false
                self.lastReport = report
                self.showReport = true
                self.disk = Scanner.diskInfo()
                completion(report)
            }
        }
    }

    // MARK: - Large files

    func findLargeFiles() {
        guard !isFindingLarge else { return }
        isFindingLarge = true
        largeFiles = []
        largeSelected = []

        let home = SafetyGuard.home
        let roots = LargeFileFinder.searchableRoots
            .filter { largeRoots.contains($0.name) }
            .map { (home as NSString).appendingPathComponent($0.relative) }
            .filter { FileManager.default.fileExists(atPath: $0) }

        var opts = LargeFileFinder.Options(roots: roots)
        opts.minBytes = Int64(largeMinMB) * 1024 * 1024
        opts.minAgeDays = Int(largeMinAge)

        let finder = LargeFileFinder()
        largeFinder = finder

        Task.detached(priority: .userInitiated) {
            let found = finder.find(opts) { status in
                Task { @MainActor in self.largeStatus = "Searching \(status)" }
            }
            await MainActor.run {
                self.largeFiles = found
                self.isFindingLarge = false
                self.largeStatus = ""
            }
        }
    }

    func cancelLarge() { largeFinder.cancel(); isFindingLarge = false }

    // MARK: - Duplicates

    func findDuplicates() {
        guard !isFindingDuplicates else { return }
        isFindingDuplicates = true
        duplicateSets = []
        duplicateSelected = []

        let home = SafetyGuard.home
        let roots = LargeFileFinder.searchableRoots
            .filter { largeRoots.contains($0.name) }
            .map { (home as NSString).appendingPathComponent($0.relative) }
            .filter { FileManager.default.fileExists(atPath: $0) }

        let finder = DuplicateFinder()
        dupFinder = finder

        Task.detached(priority: .userInitiated) {
            let sets = finder.find(roots: roots) { status in
                Task { @MainActor in self.duplicateStatus = status }
            }
            await MainActor.run {
                self.duplicateSets = sets
                self.isFindingDuplicates = false
                self.duplicateStatus = ""
            }
        }
    }

    func cancelDuplicates() { dupFinder.cancel(); isFindingDuplicates = false }

    func selectAllDuplicateExtras() {
        duplicateSelected = Set(duplicateSets.flatMap { $0.extras.map(\.path) })
    }

    // MARK: - Uninstaller

    func loadApps() {
        guard apps.isEmpty, !isLoadingApps else { return }
        isLoadingApps = true
        let u = appUninstaller
        Task.detached(priority: .userInitiated) {
            let list = u.installedApps()
            await MainActor.run {
                self.apps = list
                self.isLoadingApps = false
            }
        }
    }

    func choose(app: AppTarget) {
        chosenApp = app
        appLeftovers = []
        appLeftoverSelected = []
        let u = appUninstaller
        Task.detached(priority: .userInitiated) {
            // Measure this one bundle properly, then look for its leftovers.
            let measured = u.target(for: app.bundleURL, measure: true) ?? app
            let found = u.leftovers(for: measured)
            await MainActor.run {
                self.chosenApp = measured
                self.appLeftovers = found
                self.appLeftoverSelected = Set(found.map(\.path))
            }
        }
    }

    func performUninstall(includeBundle: Bool) {
        guard let app = chosenApp else { return }
        let picked = appLeftovers.filter { appLeftoverSelected.contains($0.path) }
        let u = appUninstaller
        let method = removalMethod
        let dry = dryRun
        isCleaning = true
        Task.detached(priority: .userInitiated) {
            let report = u.uninstall(app: app, leftovers: picked,
                                     includeBundle: includeBundle,
                                     method: method, dryRun: dry)
            await MainActor.run {
                self.isCleaning = false
                self.lastReport = report
                self.showReport = true
                self.disk = Scanner.diskInfo()
                if !dry {
                    self.chosenApp = nil
                    self.appLeftovers = []
                    self.apps = []
                    self.loadApps()
                }
            }
        }
    }

    // MARK: - Startup

    func loadStartupItems() { startupItems = StartupItems.list() }

    func refreshDisk() { disk = Scanner.diskInfo() }
}
