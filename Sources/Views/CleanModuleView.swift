//
//  CleanModuleView.swift
//  Purge
//
//  The scan / review / clean screen, shared by Smart Scan and every
//  individual cleaning module.
//

import SwiftUI
import AppKit

struct CleanModuleView: View {
    let module: ModuleKind
    @EnvironmentObject var app: AppState
    @StateObject private var confirming = Local(false)

    private var isCurrent: Bool { app.lastScanModule == module }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if app.isScanning {
                        scanningCard
                    } else if !isCurrent || app.groups.isEmpty {
                        idleCard
                    } else {
                        resultsHeader
                        ForEach(app.groups) { group in
                            GroupCard(group: group)
                        }
                        if module == .smartScan || module == .systemJunk {
                            advisories
                        }
                    }
                }
                .padding(24)
            }

            if isCurrent && !app.groups.isEmpty && !app.isScanning {
                actionBar
            }
        }
        .alert("Remove \(app.selectedItems.count) items?", isPresented: $confirming.value) {
            Button("Cancel", role: .cancel) { }
            Button(app.removalMethod == .trash ? "Move to Trash" : "Delete", role: .destructive) {
                app.clean()
            }
        } message: {
            Text(app.removalMethod == .trash
                 ? "They go to the Trash, so you can put anything back."
                 : "This frees \(Format.bytes(app.selectedBytes)) immediately and cannot be undone.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            SectionHeading(title: module.title, subtitle: module.blurb)
            Spacer()
            if app.dryRun {
                Label("Dry run", systemImage: "eye")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.amber.opacity(0.14)))
            }
        }
    }

    // MARK: - States

    private var idleCard: some View {
        Card {
            HStack(spacing: 26) {
                DiskRing(fraction: app.disk.usedFraction,
                         centerTop: Format.bytes(app.disk.free),
                         centerBottom: "free of \(Format.bytes(app.disk.total))")

                VStack(alignment: .leading, spacing: 13) {
                    Text(module == .smartScan
                         ? "Scan everything that is safe to remove"
                         : "Scan for \(module.title.lowercased())")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text(module == .smartScan
                         ? "Purge looks only inside your own home folder, never asks for an admin password, and shows you every single file before anything is removed."
                         : module.blurb + ". Nothing is removed until you press Clean.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 9) {
                        Button {
                            app.scan(module)
                        } label: {
                            Label("Scan", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        if !SafetyGuard.hasFullDiskAccess() {
                            Button {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                            } label: {
                                Label("Grant Full Disk Access", systemImage: "lock.open")
                            }
                            .buttonStyle(GhostButtonStyle(tint: Theme.amber))
                            .help("Optional. Without it a few protected caches stay invisible to Purge.")
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var scanningCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text(app.scanLabel.isEmpty ? "Scanning…" : "Scanning \(app.scanLabel)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button("Stop") { app.cancelScan() }
                        .buttonStyle(GhostButtonStyle())
                }
                ProgressView(value: app.scanProgress)
                    .tint(Theme.accent)
                Text("Reading file sizes only. Nothing is being changed.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
            }
        }
    }

    private var resultsHeader: some View {
        Card {
            HStack(spacing: 22) {
                StatTile(value: Format.bytes(app.foundBytes), label: "FOUND", tint: Theme.accent)
                StatTile(value: "\(app.foundCount)", label: "ITEMS")
                StatTile(value: Format.bytes(app.selectedBytes), label: "SELECTED", tint: Theme.green)
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 7) {
                        Button("Safe only") { app.selectAll(safeOnly: true) }
                            .buttonStyle(GhostButtonStyle())
                        Button("All") { app.selectAll(safeOnly: false) }
                            .buttonStyle(GhostButtonStyle())
                        Button("None") { app.clearSelection() }
                            .buttonStyle(GhostButtonStyle())
                    }
                    Button {
                        app.scan(module)
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(GhostButtonStyle())
                }
            }
        }
    }

    private var advisories: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("OUTSIDE PURGE'S REACH")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(1)
                .foregroundStyle(Theme.textFaint)
            ForEach(Array(Rules.advisoryPaths.enumerated()), id: \.offset) { pair in
                Card(padding: 13) {
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Theme.textFaint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pair.element.title)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(Theme.textMuted)
                            Text(pair.element.hint)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.textFaint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button("Reveal") {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: pair.element.path)
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider().background(Theme.hairline)
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.selectedItems.isEmpty ? "Nothing selected" : "\(app.selectedItems.count) items · \(Format.bytes(app.selectedBytes))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(app.removalMethod.title)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textFaint)
                }

                Spacer()

                if app.isCleaning {
                    ProgressView(value: app.cleanProgress)
                        .tint(Theme.accent)
                        .frame(width: 150)
                    Text(app.cleanLabel)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                        .frame(maxWidth: 180, alignment: .leading)
                } else {
                    Button {
                        if app.confirmBefore && !app.dryRun { confirming.value = true } else { app.clean() }
                    } label: {
                        Label(app.dryRun ? "Preview" : "Clean", systemImage: app.dryRun ? "eye" : "wind")
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: app.selectedItems.isEmpty ? Theme.textFaint : Theme.accent))
                    .disabled(app.selectedItems.isEmpty)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 13)
            .background(Theme.sidebarBG)
        }
    }
}

// MARK: - One rule's results

struct GroupCard: View {
    let group: CleanGroup
    @EnvironmentObject var app: AppState

    private var expanded: Bool { app.expandedGroups.contains(group.ruleID) }

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                head
                if expanded {
                    Divider().background(Theme.hairline)
                    VStack(spacing: 0) {
                        ForEach(group.items.prefix(200)) { item in
                            ItemRow(item: item,
                                    selected: app.selectedPaths.contains(item.path)) {
                                app.toggle(item)
                            }
                        }
                        if group.items.count > 200 {
                            Text("+ \(group.items.count - 200) more, included in the totals")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textFaint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 18).padding(.vertical, 9)
                        }
                    }
                }
            }
        }
    }

    private var head: some View {
        let state = app.groupState(group)
        return HStack(spacing: 12) {
            Button { app.toggle(group: group) } label: {
                Tick(on: state.all, mixed: state.some)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(group.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    RiskBadge(risk: group.risk)
                }
                Text(group.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 1) {
                Text(group.sizeText)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                Text("\(group.items.count) items")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textFaint)
            }

            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if expanded { app.expandedGroups.remove(group.ruleID) }
                    else { app.expandedGroups.insert(group.ruleID) }
                }
            } label: {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }
}

struct ItemRow: View {
    let item: CleanItem
    let selected: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Button(action: toggle) { Tick(on: selected) }
                .buttonStyle(.plain)

            Image(systemName: item.isDirectory ? "folder" : "doc")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textFaint)
                .frame(width: 13)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(Format.shortPath(item.path))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Text(Format.age(item.modified))
                .font(.system(size: 10))
                .foregroundStyle(Theme.textFaint)
                .frame(width: 78, alignment: .trailing)

            Text(item.sizeText)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textMuted)
                .frame(width: 72, alignment: .trailing)

            Button {
                NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textFaint)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6.5)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .background(Color.white.opacity(0.001))
    }
}
