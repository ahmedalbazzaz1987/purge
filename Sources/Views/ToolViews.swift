//
//  ToolViews.swift
//  Purge
//

import SwiftUI
import AppKit

// MARK: - Uninstaller

struct UninstallerView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var confirming = Local(false)

    private var filtered: [AppTarget] {
        guard !app.appSearch.isEmpty else { return app.apps }
        return app.apps.filter { $0.name.localizedCaseInsensitiveContains(app.appSearch) }
    }

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 250, idealWidth: 290, maxWidth: 360)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { app.loadApps() }
        .alert("Uninstall \(app.chosenApp?.name ?? "")?", isPresented: $confirming.value) {
            Button("Cancel", role: .cancel) { }
            Button("Uninstall", role: .destructive) { app.performUninstall(includeBundle: true) }
        } message: {
            Text("The app and the \(app.appLeftoverSelected.count) support files you ticked will be \(app.removalMethod == .trash ? "moved to the Trash" : "deleted").")
        }
    }

    private var list: some View {
        ZStack {
            Theme.sidebarBG.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textFaint)
                    TextField("Filter applications", text: $app.appSearch)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                .padding(14)

                if app.isLoadingApps {
                    HStack { ProgressView().controlSize(.small); Text("Reading /Applications…").font(.system(size: 11.5)).foregroundStyle(Theme.textMuted) }
                        .padding(.horizontal, 16)
                }

                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filtered, id: \.bundleID) { target in
                            appRow(target)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private func appRow(_ target: AppTarget) -> some View {
        let active = app.chosenApp?.bundleID == target.bundleID
        return Button {
            app.choose(app: target)
        } label: {
            HStack(spacing: 9) {
                if let icon = target.icon {
                    Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(target.name)
                        .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                        .foregroundStyle(active ? Theme.textPrimary : Theme.textMuted)
                        .lineLimit(1)
                    Text("v\(target.version)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.textFaint)
                }
                Spacer()
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(active ? Color.white.opacity(0.07) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detail: some View {
        ZStack {
            Theme.canvasBG.ignoresSafeArea()
            if let target = app.chosenApp {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 14) {
                            if let icon = target.icon {
                                Image(nsImage: icon).resizable().frame(width: 52, height: 52)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(target.name)
                                    .font(.system(size: 21, weight: .bold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("\(target.bundleID) · version \(target.version)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.textFaint)
                            }
                            Spacer()
                        }

                        HStack(spacing: 10) {
                            Card(padding: 13) { StatTile(value: Format.bytes(target.bundleBytes), label: "APPLICATION") }
                            Card(padding: 13) {
                                StatTile(value: Format.bytes(app.appLeftovers.reduce(0) { $0 + $1.bytes }),
                                         label: "LEFTOVER FILES", tint: Theme.amber)
                            }
                            Card(padding: 13) { StatTile(value: "\(app.appLeftovers.count)", label: "LOCATIONS") }
                        }

                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Support files found")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Button("All") { app.appLeftoverSelected = Set(app.appLeftovers.map(\.path)) }
                                        .buttonStyle(GhostButtonStyle())
                                    Button("None") { app.appLeftoverSelected = [] }
                                        .buttonStyle(GhostButtonStyle())
                                }
                                .padding(16)
                                Divider().background(Theme.hairline)
                                if app.appLeftovers.isEmpty {
                                    Text("Nothing found outside the app bundle. This one is tidy.")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Theme.textFaint)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(16)
                                } else {
                                    ForEach(app.appLeftovers) { item in
                                        ItemRow(item: item, selected: app.appLeftoverSelected.contains(item.path)) {
                                            if app.appLeftoverSelected.contains(item.path) { app.appLeftoverSelected.remove(item.path) }
                                            else { app.appLeftoverSelected.insert(item.path) }
                                        }
                                    }
                                }
                            }
                        }

                        HStack {
                            Text("Purge only looks in the standard places a Mac app stores state, matched against this app's bundle identifier.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textFaint)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button {
                                confirming.value = true
                            } label: { Label("Uninstall", systemImage: "xmark.bin") }
                            .buttonStyle(PrimaryButtonStyle(tint: Theme.red))
                            .disabled(app.isCleaning)
                        }
                    }
                    .padding(24)
                }
            } else {
                EmptyState(symbol: "xmark.bin",
                           title: "Pick an application",
                           message: "Purge lists what is in /Applications, finds the files that app left in your Library, and removes both together. System apps are never listed.")
            }
        }
    }
}

// MARK: - Startup items

struct StartupItemsView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var error = Local<String?>(nil)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeading(title: "Startup Items",
                               subtitle: "Background agents that launch when you log in, from your own Library folder.")

                if let message = error.value {
                    Text(message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.red)
                }

                if app.startupItems.isEmpty {
                    EmptyState(symbol: "bolt",
                               title: "No user launch agents",
                               message: "Nothing in ~/Library/LaunchAgents. System-level agents are managed by macOS and Purge does not touch them.")
                } else {
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(app.startupItems) { item in
                                HStack(spacing: 11) {
                                    Image(systemName: "bolt.circle")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Theme.amber)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.label)
                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundStyle(Theme.textPrimary)
                                        Text(item.program)
                                            .font(.system(size: 9.5, design: .monospaced))
                                            .foregroundStyle(Theme.textFaint)
                                            .lineLimit(1).truncationMode(.middle)
                                    }
                                    Spacer()
                                    Button("Reveal") {
                                        NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
                                    }
                                    .buttonStyle(GhostButtonStyle())
                                    Button("Disable") {
                                        error.value = StartupItems.disable(item)
                                        app.loadStartupItems()
                                    }
                                    .buttonStyle(GhostButtonStyle(tint: Theme.red))
                                }
                                .padding(.horizontal, 18).padding(.vertical, 10)
                                Divider().background(Theme.hairline)
                            }
                        }
                    }

                    Text("Disable moves the agent's .plist to the Trash, so you can put it back. It takes effect after your next login.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .padding(24)
        }
        .onAppear { app.loadStartupItems() }
    }
}
