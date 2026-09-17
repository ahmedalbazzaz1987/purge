//
//  SettingsViews.swift
//  Purge
//

import SwiftUI
import AppKit

// MARK: - Updates

struct UpdatesView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var updater: Updater

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeading(title: "Updates",
                               subtitle: "Purge checks the Releases page of your own GitHub repository — nothing else phones home.")

                Card {
                    VStack(alignment: .leading, spacing: 15) {
                        HStack(spacing: 14) {
                            statusIcon
                            VStack(alignment: .leading, spacing: 2) {
                                Text(statusTitle)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(statusDetail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            actionButton
                        }

                        if case .downloading(let p) = updater.state {
                            ProgressView(value: p).tint(Theme.accent)
                        }

                        Divider().background(Theme.hairline)

                        HStack(spacing: 14) {
                            field("GitHub owner", text: $app.githubOwner)
                            field("Repository", text: $app.githubRepo)
                            Spacer()
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            Text("CHECK AUTOMATICALLY")
                                .font(.system(size: 9, weight: .bold)).tracking(0.8)
                                .foregroundStyle(Theme.textFaint)

                            HStack(spacing: 7) {
                                ForEach(UpdateFrequency.allCases) { f in
                                    let on = app.updateFrequency == f
                                    Button {
                                        app.updateFrequency = f
                                    } label: {
                                        Text(f.title)
                                            .font(.system(size: 11.5, weight: on ? .semibold : .regular))
                                            .foregroundStyle(on ? Theme.accent : Theme.textMuted)
                                            .padding(.horizontal, 11).padding(.vertical, 5)
                                            .background(Capsule().fill(on ? Theme.accent.opacity(0.13)
                                                                          : Color.white.opacity(0.04)))
                                            .overlay(Capsule().stroke(Theme.cardStroke, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                    .help(f.detail)
                                }
                                Spacer()
                            }

                            Text(app.updateFrequency.detail
                                 + (lastCheckedText.isEmpty ? "" : "  ·  Last checked \(lastCheckedText)."))
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textFaint)

                            Text("Checks run only while Purge is open. It installs no background agent, so nothing of Purge's runs when the app is closed.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textFaint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if let latest = updater.latest, !latest.notes.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Release notes — \(latest.tag)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            ScrollView {
                                Text(latest.notes)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.textMuted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 200)
                            Button("Open on GitHub") { NSWorkspace.shared.open(latest.pageURL) }
                                .buttonStyle(GhostButtonStyle())
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How updating works")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        bullet("Purge reads the latest release from api.github.com — a public, read-only endpoint. No token, no account.")
                        bullet("It downloads the .zip attached to that release and unpacks it with macOS's own ditto.")
                        bullet("Before installing anything it checks that the bundle identifier matches and the version really is newer. If either test fails, nothing is installed.")
                        bullet("The swap happens after Purge quits. If it goes wrong, the previous copy is put straight back.")
                        bullet("Prefer building from source? Run ./update.sh in the project folder — it pulls the latest commit and rebuilds.")
                    }
                }
            }
            .padding(24)
        }
    }

    private var lastCheckedText: String {
        guard let last = app.lastUpdateCheck else { return "" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: last, relativeTo: Date())
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold)).tracking(0.8)
                .foregroundStyle(Theme.textFaint)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.cardStroke, lineWidth: 1))
                .frame(width: 170)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Circle().fill(Theme.textFaint).frame(width: 3.5, height: 3.5).padding(.top, 6)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusIcon: some View {
        Group {
            switch updater.state {
            case .checking, .downloading, .installing:
                ProgressView().controlSize(.small)
            case .available:
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.accent)
            case .upToDate:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
            case .readyToRelaunch:
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill").foregroundStyle(Theme.green)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
            case .idle:
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Theme.textMuted)
            }
        }
        .font(.system(size: 26))
        .frame(width: 30)
    }

    private var statusTitle: String {
        switch updater.state {
        case .idle:            return "Version \(AppInfo.version)"
        case .checking:        return "Checking GitHub…"
        case .upToDate:        return "You are up to date"
        case .available(let v):return "Version \(v) is available"
        case .downloading:     return "Downloading…"
        case .installing:      return "Verifying and installing…"
        case .readyToRelaunch: return "Ready — restart to finish"
        case .failed:          return "Could not check"
        }
    }

    private var statusDetail: String {
        switch updater.state {
        case .idle:
            return "Press Check to ask \(app.githubOwner)/\(app.githubRepo) for its latest release."
        case .upToDate:
            return "\(AppInfo.version) is the newest published release."
        case .available:
            return "You are on \(AppInfo.version). Purge will verify the download before replacing itself."
        case .readyToRelaunch:
            return "The new version is staged. Purge will quit and reopen itself."
        case .failed(let message):
            return message
        default:
            return "Working…"
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch updater.state {
        case .available:
            Button("Download & Install") {
                Task { await updater.downloadAndInstall() }
            }
            .buttonStyle(PrimaryButtonStyle())
        case .readyToRelaunch:
            Button("Restart Purge") { updater.relaunch() }
                .buttonStyle(PrimaryButtonStyle(tint: Theme.green))
        case .checking, .downloading, .installing:
            EmptyView()
        default:
            Button("Check now") {
                Task {
                    await updater.check(owner: app.githubOwner, repo: app.githubRepo)
                    if case .failed = updater.state {} else { app.lastUpdateCheck = Date() }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var showLog = Local(false)
    @StateObject private var confirmSelfUninstall = Local(false)
    @StateObject private var footprint = Local<[CleanItem]>([])

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeading(title: "Settings",
                               subtitle: "How Purge behaves, what it promises, and how to get rid of it.")

                // Removal method
                Card {
                    VStack(alignment: .leading, spacing: 13) {
                        Text("When removing files")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)

                        ForEach(RemovalMethod.allCases) { method in
                            Button {
                                app.removalMethod = method
                            } label: {
                                HStack(alignment: .top, spacing: 11) {
                                    Image(systemName: app.removalMethod == method ? "largecircle.fill.circle" : "circle")
                                        .font(.system(size: 14))
                                        .foregroundStyle(app.removalMethod == method ? Theme.accent : Theme.textFaint)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(method.title)
                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundStyle(Theme.textPrimary)
                                        Text(method.explanation)
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(Theme.textMuted)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        Divider().background(Theme.hairline)

                        Toggle("Dry run — show what would be removed, change nothing", isOn: $app.dryRun)
                            .toggleStyle(.switch).tint(Theme.amber)
                            .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                        Toggle("Ask me to confirm before each clean", isOn: $app.confirmBefore)
                            .toggleStyle(.switch).tint(Theme.accent)
                            .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                    }
                }

                // Promises
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What Purge will never do")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        promise("Run as root, or ask for your admin password.")
                        promise("Touch anything outside your home folder — except an app you explicitly chose to uninstall.")
                        promise("Delete passwords, keychains, iCloud Drive, Photos, Messages, Mail, or your Documents and Desktop.")
                        promise("Remove a file you cannot see in the list first.")
                        promise("Send anything anywhere. The only network request it ever makes is the GitHub version check.")
                        promise("Install a background agent, a helper tool, or a login item.")
                    }
                }

                // Footprint + uninstall
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Purge's own footprint")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Everything this app has created on your Mac. Removing Purge removes exactly this list and nothing else remains.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textMuted)

                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(footprint.value) { item in
                                HStack(spacing: 8) {
                                    Image(systemName: item.isDirectory ? "folder" : "doc")
                                        .font(.system(size: 10)).foregroundStyle(Theme.textFaint)
                                    Text(Format.shortPath(item.path))
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(Theme.textMuted)
                                    Spacer()
                                    Text(item.sizeText)
                                        .font(.system(size: 10)).foregroundStyle(Theme.textFaint)
                                }
                            }
                            if footprint.value.isEmpty {
                                Text("Nothing yet — Purge has not written a single file.")
                                    .font(.system(size: 11)).foregroundStyle(Theme.textFaint)
                            }
                        }

                        HStack(spacing: 9) {
                            Button("Show action log") { showLog.value = true }
                                .buttonStyle(GhostButtonStyle())
                            Button("Clear action log") { ActionLog.shared.clear(); refresh() }
                                .buttonStyle(GhostButtonStyle())
                            Spacer()
                            Button {
                                confirmSelfUninstall.value = true
                            } label: { Label("Uninstall Purge", systemImage: "trash") }
                            .buttonStyle(PrimaryButtonStyle(tint: Theme.red))
                        }
                    }
                }

                Text("Purge \(AppInfo.version) · built for macOS on Apple silicon · no telemetry, no account, no background process")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(24)
        }
        .onAppear { refresh() }
        .sheet(isPresented: $showLog.value) { LogSheet() }
        .alert("Remove Purge completely?", isPresented: $confirmSelfUninstall.value) {
            Button("Cancel", role: .cancel) { }
            Button("Uninstall and quit", role: .destructive) {
                SelfUninstall.perform(alsoRemoveBundle: true)
            }
        } message: {
            Text("Purge will move its settings, log and its own application to the Trash, then quit. Files you already cleaned are not affected.")
        }
    }

    private func refresh() { footprint.value = SelfUninstall.footprintItems() }

    private func promise(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "xmark.shield.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.green)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct LogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var text = Local("")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Action log")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            ScrollView {
                Text(text.value)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 330)
            HStack {
                Text("Kept only on this Mac, in Purge's own support folder.")
                    .font(.system(size: 11)).foregroundStyle(Theme.textFaint)
                Spacer()
                Button("Close") { dismiss() }.buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(22)
        .frame(width: 620)
        .background(Theme.canvasBG)
        .onAppear { text.value = ActionLog.shared.read() }
    }
}
