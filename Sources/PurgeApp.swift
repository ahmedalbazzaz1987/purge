//
//  PurgeApp.swift
//  Purge — a small, safe cleaner for macOS.
//

import SwiftUI
import AppKit

@main
struct PurgeApp: App {

    @StateObject private var state = AppState()
    @StateObject private var updater = Updater()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Purge") {
            RootView()
                .environmentObject(state)
                .environmentObject(updater)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1080, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    state.selection = .updates
                    Task { await updater.check(owner: state.githubOwner, repo: state.githubRepo) }
                }
                Divider()
                Button("Uninstall Purge…") {
                    state.selection = .settings
                }
            }

            CommandMenu("Scan") {
                Button("Smart Scan") { state.selection = .smartScan; state.scan(.smartScan) }
                    .keyboardShortcut("s", modifiers: [.command])
                Divider()
                ForEach(ModuleKind.smartScanMembers) { m in
                    Button(m.title) { state.selection = m; state.scan(m) }
                }
                Divider()
                Button("Refresh disk usage") { state.refreshDisk() }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        ActionLog.shared.write("=== Purge \(AppInfo.version) launched ===")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
