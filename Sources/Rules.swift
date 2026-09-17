//
//  Rules.swift
//  Purge
//
//  The whitelist. Purge can only ever find what is described here, and
//  everything found still has to pass SafetyGuard before it is removed.
//

import Foundation

struct CleanRule: Identifiable {
    enum Granularity {
        /// Each direct child of every matched directory becomes one item.
        case childrenOf
        /// Each matched path itself becomes one item.
        case itself
    }

    let id: String
    let title: String
    let detail: String
    let risk: RiskTier
    let module: ModuleKind

    /// Path patterns. `~` is the home directory, `$TMP` the per-user temp root.
    /// A `*` matches one path component.
    let targets: [String]
    let granularity: Granularity

    /// Only consider items whose modification date is at least this old.
    var minAgeDays: Int = 0
    /// Component names to leave alone.
    var excluded: Set<String> = []
    /// Whether this group starts ticked in the results list.
    var preselected: Bool = true
    /// Skip items smaller than this, to keep the list readable.
    var minBytes: Int64 = 0
}

enum Rules {

    // Caches that belong to a browser or a dev tool are listed by their own
    // module, so System Junk skips them to avoid showing anything twice.
    private static let claimedCacheNames: Set<String> = [
        "com.apple.Safari", "com.apple.Safari.SafeBrowsing",
        "com.google.Chrome", "com.google.Chrome.helper", "Google",
        "com.microsoft.edgemac", "Microsoft Edge",
        "com.brave.Browser", "BraveSoftware",
        "Firefox", "org.mozilla.firefox",
        "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
        "com.apple.dt.Xcode", "com.apple.dt.xcodebuild", "org.swift.swiftpm",
        "Homebrew", "pip", "pipenv", "go-build", "node-gyp", "typescript",
        "Yarn", "CocoaPods", "com.docker.docker",
        "com.jetbrains", "JetBrains",
        // claimed by the "Update leftovers" rule
        "com.apple.appstore", "com.apple.SoftwareUpdate", "com.apple.installer",
    ]

    // Caches macOS is unhappy to lose: removing them forces an expensive
    // re-sync or re-index rather than a cheap rebuild.
    private static let fragileCacheNames: Set<String> = [
        "CloudKit", "com.apple.containermanagerd", "com.apple.homed",
        "com.apple.HomeKit", "com.apple.iCloudHelper", "com.apple.cloudd",
        "com.apple.bird", "com.apple.security", "com.apple.nsurlsessiond",
    ]

    // MARK: - System junk

    static let systemJunk: [CleanRule] = [
        CleanRule(
            id: "user.caches",
            title: "Application caches",
            detail: "Data apps keep around to start faster. macOS and each app rebuild this on their own.",
            risk: .safe,
            module: .systemJunk,
            targets: ["~/Library/Caches"],
            granularity: .childrenOf,
            excluded: claimedCacheNames.union(fragileCacheNames)
        ),

        CleanRule(
            id: "container.caches",
            title: "Sandboxed app caches",
            detail: "The same thing for App Store apps, which keep their caches inside their own container.",
            risk: .safe,
            module: .systemJunk,
            targets: ["~/Library/Containers/*/Data/Library/Caches"],
            granularity: .childrenOf
        ),

        CleanRule(
            id: "user.logs",
            title: "Application logs",
            detail: "Diagnostic text written by apps. Only useful while chasing a bug you already reported.",
            risk: .safe,
            module: .systemJunk,
            targets: ["~/Library/Logs"],
            granularity: .childrenOf,
            minAgeDays: 3,
            excluded: ["DiagnosticReports"]
        ),

        CleanRule(
            id: "crash.reports",
            title: "Crash reports",
            detail: "Reports from apps that quit unexpectedly. Kept for Apple's crash reporter, not for you.",
            risk: .safe,
            module: .systemJunk,
            targets: ["~/Library/Logs/DiagnosticReports"],
            granularity: .childrenOf,
            minAgeDays: 7
        ),

        CleanRule(
            id: "temp.files",
            title: "Temporary files",
            detail: "Your private temp folder. macOS clears it on restart — this clears it now.",
            risk: .safe,
            module: .systemJunk,
            targets: ["$TMP/T", "$TMP/C"],
            granularity: .childrenOf,
            minAgeDays: 1
        ),

        CleanRule(
            id: "saved.state",
            title: "Saved application state",
            detail: "Window positions and reopened documents. Apps will simply start with a fresh window.",
            risk: .mild,
            module: .systemJunk,
            targets: ["~/Library/Saved Application State"],
            granularity: .childrenOf,
            minAgeDays: 14
        ),

        CleanRule(
            id: "update.leftovers",
            title: "Update leftovers",
            detail: "Downloaded installers and staged payloads left behind after macOS and App Store updates.",
            risk: .safe,
            module: .systemJunk,
            targets: [
                "~/Library/Updates",
                "~/Library/Caches/com.apple.appstore",
                "~/Library/Caches/com.apple.SoftwareUpdate",
                "~/Library/Caches/com.apple.installer",
                "~/Library/Application Support/App Store/updatejournal.plist",
            ],
            granularity: .childrenOf
        ),

        CleanRule(
            id: "mail.downloads",
            title: "Mail attachment cache",
            detail: "Copies of attachments Mail downloaded to preview. The originals stay on the mail server.",
            risk: .mild,
            module: .systemJunk,
            targets: ["~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"],
            granularity: .childrenOf,
            minAgeDays: 30,
            preselected: false
        ),

        CleanRule(
            id: "quicklook.thumbs",
            title: "Quick Look thumbnails",
            detail: "Preview images generated for Finder. Regenerated the next time you look at a folder.",
            risk: .safe,
            module: .systemJunk,
            targets: ["$TMP/C/com.apple.QuickLook.thumbnailcache"],
            granularity: .childrenOf
        ),

        CleanRule(
            id: "font.caches",
            title: "Document version history",
            detail: "Old autosaved revisions of documents you already saved. The current file is untouched.",
            risk: .review,
            module: .systemJunk,
            targets: ["~/Library/Containers/*/Data/Library/Autosave Information"],
            granularity: .childrenOf,
            minAgeDays: 60,
            preselected: false
        ),
    ]

    // MARK: - Browser data
    //
    // Deliberately limited to cache directories. Cookies, logins, history,
    // bookmarks, passwords and saved form data are never targeted.

    static let browserData: [CleanRule] = [
        CleanRule(
            id: "safari.cache",
            title: "Safari cache",
            detail: "Cached pages and images. Your history, bookmarks and passwords are not touched.",
            risk: .safe,
            module: .browserData,
            targets: [
                "~/Library/Caches/com.apple.Safari",
                "~/Library/Containers/com.apple.Safari/Data/Library/Caches",
            ],
            granularity: .childrenOf
        ),

        CleanRule(
            id: "chromium.cache",
            title: "Chrome / Edge / Brave cache",
            detail: "Cached web content and GPU shaders for every profile. You stay signed in everywhere.",
            risk: .safe,
            module: .browserData,
            targets: [
                "~/Library/Caches/Google/Chrome/*/Cache",
                "~/Library/Caches/Google/Chrome/*/Code Cache",
                "~/Library/Caches/com.google.Chrome",
                "~/Library/Caches/Microsoft Edge/*/Cache",
                "~/Library/Caches/com.microsoft.edgemac",
                "~/Library/Caches/BraveSoftware/Brave-Browser/*/Cache",
                "~/Library/Caches/com.brave.Browser",
                "~/Library/Application Support/Google/Chrome/*/Service Worker/CacheStorage",
                "~/Library/Application Support/Google/Chrome/*/GPUCache",
                "~/Library/Application Support/BraveSoftware/Brave-Browser/*/GPUCache",
                "~/Library/Application Support/Microsoft Edge/*/GPUCache",
            ],
            granularity: .childrenOf
        ),

        CleanRule(
            id: "firefox.cache",
            title: "Firefox cache",
            detail: "Firefox's disk cache for every profile. Logins, tabs and add-ons are left alone.",
            risk: .safe,
            module: .browserData,
            targets: [
                "~/Library/Caches/Firefox/Profiles/*/cache2",
                "~/Library/Caches/Firefox/Profiles/*/startupCache",
            ],
            granularity: .childrenOf
        ),

        CleanRule(
            id: "browser.crashes",
            title: "Browser crash reports",
            detail: "Crash dumps written by Chromium-based browsers.",
            risk: .safe,
            module: .browserData,
            targets: [
                "~/Library/Application Support/Google/Chrome/Crashpad/completed",
                "~/Library/Application Support/BraveSoftware/Brave-Browser/Crashpad/completed",
                "~/Library/Application Support/Microsoft Edge/Crashpad/completed",
            ],
            granularity: .childrenOf
        ),
    ]

    // MARK: - Developer junk

    static let developerJunk: [CleanRule] = [
        CleanRule(
            id: "xcode.derived",
            title: "Xcode DerivedData",
            detail: "Intermediate build products and indexes. Xcode rebuilds them on the next build.",
            risk: .safe,
            module: .developerJunk,
            targets: ["~/Library/Developer/Xcode/DerivedData"],
            granularity: .childrenOf
        ),

        CleanRule(
            id: "xcode.caches",
            title: "Xcode caches & device support",
            detail: "Module caches, previews, and symbol files for devices you have connected before.",
            risk: .safe,
            module: .developerJunk,
            targets: [
                "~/Library/Caches/com.apple.dt.Xcode",
                "~/Library/Developer/Xcode/iOS DeviceSupport",
                "~/Library/Developer/Xcode/watchOS DeviceSupport",
                "~/Library/Developer/CoreSimulator/Caches",
            ],
            granularity: .childrenOf
        ),

        CleanRule(
            id: "xcode.archives",
            title: "Xcode archives",
            detail: "Builds you archived for distribution. Keep these if you may still need to re-submit one.",
            risk: .review,
            module: .developerJunk,
            targets: ["~/Library/Developer/Xcode/Archives"],
            granularity: .childrenOf,
            preselected: false
        ),

        CleanRule(
            id: "sim.devices",
            title: "Unavailable simulators",
            detail: "Simulator runtimes and devices Xcode no longer lists. Large and easy to recreate.",
            risk: .mild,
            module: .developerJunk,
            targets: ["~/Library/Developer/CoreSimulator/Devices"],
            granularity: .childrenOf,
            minAgeDays: 90,
            preselected: false
        ),

        CleanRule(
            id: "pkg.caches",
            title: "Package manager caches",
            detail: "Downloaded archives for npm, yarn, pip, Homebrew, CocoaPods, Go and Rust.",
            risk: .safe,
            module: .developerJunk,
            targets: [
                "~/.npm/_cacache",
                "~/Library/Caches/Yarn",
                "~/Library/Caches/pip",
                "~/Library/Caches/Homebrew",
                "~/Library/Caches/CocoaPods",
                "~/Library/Caches/go-build",
                "~/Library/Caches/node-gyp",
                "~/Library/Caches/typescript",
                "~/.gradle/caches",
                "~/.cargo/registry/cache",
                "~/.bun/install/cache",
                "~/.deno/gen",
            ],
            granularity: .childrenOf
        ),

        CleanRule(
            id: "swiftpm.caches",
            title: "Swift Package Manager cache",
            detail: "Cloned dependency checkouts. Re-fetched automatically when a project needs them.",
            risk: .safe,
            module: .developerJunk,
            targets: [
                "~/Library/Caches/org.swift.swiftpm",
                "~/Library/org.swift.swiftpm/cache",
            ],
            granularity: .childrenOf
        ),

        CleanRule(
            id: "container.dev",
            title: "Docker & VM leftovers",
            detail: "Log files and build caches from Docker Desktop. Your images and volumes stay.",
            risk: .mild,
            module: .developerJunk,
            targets: [
                "~/Library/Containers/com.docker.docker/Data/log",
                "~/Library/Caches/com.docker.docker",
            ],
            granularity: .childrenOf,
            preselected: false
        ),
    ]

    // MARK: - Trash

    static let trashRules: [CleanRule] = [
        CleanRule(
            id: "trash.bin",
            title: "Trash",
            detail: "Everything you already moved to the Trash. This is the step that actually frees the space.",
            risk: .review,
            module: .trashBin,
            targets: ["~/.Trash"],
            granularity: .childrenOf,
            preselected: false
        )
    ]

    // MARK: - Lookup

    static func rules(for module: ModuleKind) -> [CleanRule] {
        switch module {
        case .systemJunk:    return systemJunk
        case .browserData:   return browserData
        case .developerJunk: return developerJunk
        case .trashBin:      return trashRules
        case .smartScan:     return systemJunk + browserData + developerJunk + trashRules
        default:             return []
        }
    }

    /// Things worth telling the user about but that Purge will not delete,
    /// because they sit outside the home directory.
    static let advisoryPaths: [(title: String, path: String, hint: String)] = [
        ("macOS installer",
         "/Applications",
         "A downloaded \"Install macOS …\" app can be 12 GB or more. Drag it to the Trash yourself once you no longer need it."),
        ("System-wide caches",
         "/Library/Caches",
         "Owned by the system and shared by all users. Purge stays out of it on purpose — it needs an admin password and rarely returns much."),
    ]
}
