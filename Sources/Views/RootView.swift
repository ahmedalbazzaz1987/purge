//
//  RootView.swift
//  Purge
//

import SwiftUI
import Combine

struct RootView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var updater: Updater

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 216, ideal: 228, max: 260)
        } detail: {
            ZStack {
                Theme.canvasBG.ignoresSafeArea()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 940, minHeight: 620)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $app.showReport) {
            ReportSheet()
        }
        // Launch check.
        .task { await runScheduledCheck() }
        // While Purge stays open, re-evaluate every hour. Nothing runs when the
        // app is closed: Purge installs no background agent, by design.
        .onReceive(Timer.publish(every: 3600, on: .main, in: .common).autoconnect()) { _ in
            Task { await runScheduledCheck() }
        }
    }

    /// Only reaches the network when the chosen frequency says a check is due.
    private func runScheduledCheck() async {
        guard app.isUpdateCheckDue else { return }
        guard !app.githubOwner.isEmpty, !app.githubRepo.isEmpty else { return }
        await updater.check(owner: app.githubOwner, repo: app.githubRepo, silent: true)
        if case .failed = updater.state { return }   // retry next time rather than backing off
        app.lastUpdateCheck = Date()
    }

    @ViewBuilder
    private var detail: some View {
        switch app.selection {
        case .smartScan, .systemJunk, .browserData, .developerJunk, .trashBin:
            CleanModuleView(module: app.selection)
        case .largeFiles:   LargeFilesView()
        case .duplicates:   DuplicatesView()
        case .uninstaller:  UninstallerView()
        case .startupItems: StartupItemsView()
        case .updates:      UpdatesView()
        case .settings:     SettingsView()
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var updater: Updater

    private let cleanGroup: [ModuleKind] = [.smartScan, .systemJunk, .browserData, .developerJunk, .trashBin]
    private let findGroup: [ModuleKind]  = [.largeFiles, .duplicates]
    private let toolGroup: [ModuleKind]  = [.uninstaller, .startupItems]
    private let sysGroup: [ModuleKind]   = [.updates, .settings]

    var body: some View {
        ZStack {
            Theme.sidebarBG.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                brand
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        section("CLEAN", cleanGroup)
                        section("FIND", findGroup)
                        section("MANAGE", toolGroup)
                        section("APP", sysGroup)
                    }
                    .padding(.vertical, 8)
                }
                Spacer(minLength: 0)
                diskFooter
            }
        }
    }

    private var brand: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accent, Theme.accentDeep],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 26, height: 26)
                Image(systemName: "wind")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.8))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Purge")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("v\(AppInfo.version)")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textFaint)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    private func section(_ title: String, _ items: [ModuleKind]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9.5, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Theme.textFaint)
                .padding(.horizontal, 18)
                .padding(.bottom, 5)
            ForEach(items) { item in
                row(item)
            }
        }
    }

    private func row(_ item: ModuleKind) -> some View {
        let active = app.selection == item
        let badge: String? = {
            if item == .updates, case .available(let v) = updater.state { return v }
            return nil
        }()

        return Button {
            app.selection = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                    .foregroundStyle(active ? Theme.accent : Theme.textMuted)
                Text(item.title)
                    .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? Theme.textPrimary : Theme.textMuted)
                Spacer(minLength: 4)
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.8))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.accent))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6.5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(active ? Color.white.opacity(0.07) : Color.clear)
            )
            .overlay(alignment: .leading) {
                if active {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.accent)
                        .frame(width: 2.5, height: 15)
                        .offset(x: -4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .help(item.blurb)
    }

    private var diskFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().background(Theme.hairline)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Macintosh HD")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.textMuted)
                    Spacer()
                    Text("\(Format.bytes(app.disk.free)) free")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(LinearGradient(colors: [Theme.accent, Theme.accentDeep],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(3, geo.size.width * app.disk.usedFraction))
                    }
                }
                .frame(height: 5)
                Text("\(Format.bytes(app.disk.used)) of \(Format.bytes(app.disk.total)) used")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .padding(.top, 10)
        }
    }
}

// MARK: - Report sheet

struct ReportSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let r = app.lastReport ?? RemovalReport()
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 11) {
                Image(systemName: app.dryRun ? "eye" : "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(app.dryRun ? Theme.amber : Theme.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.dryRun ? "Dry run complete" : "Clean complete")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(app.dryRun
                         ? "Nothing was touched. This is what would have happened."
                         : "\(r.removed) item\(r.removed == 1 ? "" : "s") removed.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Card(padding: 13) { StatTile(value: r.freedText, label: "RECLAIMED", tint: Theme.green) }
                Card(padding: 13) { StatTile(value: "\(r.removed)", label: "ITEMS") }
                if !r.skipped.isEmpty {
                    Card(padding: 13) { StatTile(value: "\(r.skipped.count)", label: "PROTECTED", tint: Theme.amber) }
                }
                if !r.failed.isEmpty {
                    Card(padding: 13) { StatTile(value: "\(r.failed.count)", label: "FAILED", tint: Theme.red) }
                }
            }

            if app.removalMethod == .trash && !app.dryRun && r.removed > 0 {
                Text("Items were moved to the Trash, so the space is not free until you empty it. You can change this in Settings.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.amber)
            }

            if !r.skipped.isEmpty || !r.failed.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array((r.skipped + r.failed).enumerated()), id: \.offset) { pair in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(Format.shortPath(pair.element.path))
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(Theme.textMuted)
                                Text(pair.element.reason)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textFaint)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 130)
            }

            HStack {
                Text("A full record is kept in the action log.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(Theme.canvasBG)
    }
}
