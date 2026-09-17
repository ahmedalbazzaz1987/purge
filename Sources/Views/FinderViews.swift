//
//  FinderViews.swift
//  Purge
//
//  Large & Old Files and Duplicates. Both are hand-picked lists: nothing here
//  is ever pre-selected for the user.
//

import SwiftUI
import AppKit

// MARK: - Search scope picker, shared by both screens

struct ScopePicker: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHERE TO LOOK")
                .font(.system(size: 9.5, weight: .bold)).tracking(1)
                .foregroundStyle(Theme.textFaint)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 7, alignment: .leading)],
                      alignment: .leading, spacing: 7) {
                ForEach(LargeFileFinder.searchableRoots, id: \.name) { root in
                    let on = app.largeRoots.contains(root.name)
                    Button {
                        if on { app.largeRoots.remove(root.name) } else { app.largeRoots.insert(root.name) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 10))
                            Text(root.name).font(.system(size: 11.5))
                        }
                        .foregroundStyle(on ? Theme.accent : Theme.textMuted)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(on ? Theme.accent.opacity(0.13) : Color.white.opacity(0.04)))
                        .overlay(Capsule().stroke(Theme.cardStroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Large & old files

struct LargeFilesView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var confirming = Local(false)

    private var selectedItems: [CleanItem] {
        app.largeFiles.filter { app.largeSelected.contains($0.path) }
    }
    private var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeading(title: "Large & Old Files",
                                   subtitle: "The honest way to free real space: find what is actually big, then decide yourself.")

                    Card {
                        VStack(alignment: .leading, spacing: 16) {
                            ScopePicker()

                            HStack(spacing: 26) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Bigger than \(Int(app.largeMinMB)) MB")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(Theme.textMuted)
                                    Slider(value: $app.largeMinMB, in: 10...2000, step: 10)
                                        .tint(Theme.accent)
                                        .frame(width: 210)
                                }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(app.largeMinAge == 0 ? "Any age" : "Untouched for \(Int(app.largeMinAge)) days")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(Theme.textMuted)
                                    Slider(value: $app.largeMinAge, in: 0...365, step: 15)
                                        .tint(Theme.accent)
                                        .frame(width: 210)
                                }
                                Spacer()
                                if app.isFindingLarge {
                                    VStack(alignment: .trailing, spacing: 5) {
                                        ProgressView().controlSize(.small)
                                        Button("Stop") { app.cancelLarge() }
                                            .buttonStyle(GhostButtonStyle())
                                    }
                                } else {
                                    Button {
                                        app.findLargeFiles()
                                    } label: { Label("Find", systemImage: "magnifyingglass") }
                                    .buttonStyle(PrimaryButtonStyle())
                                    .disabled(app.largeRoots.isEmpty)
                                }
                            }

                            if !app.largeStatus.isEmpty {
                                Text(app.largeStatus)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textFaint)
                            }
                        }
                    }

                    if app.largeFiles.isEmpty && !app.isFindingLarge {
                        EmptyState(symbol: "chart.pie",
                                   title: "No results yet",
                                   message: "Pick the folders to search and press Find. Purge never selects anything here for you — every file is yours to judge.")
                    } else {
                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("\(app.largeFiles.count) files · \(Format.bytes(app.largeFiles.reduce(0) { $0 + $1.bytes })) total")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Theme.textMuted)
                                    Spacer()
                                    Button("Clear selection") { app.largeSelected = [] }
                                        .buttonStyle(GhostButtonStyle())
                                }
                                .padding(16)
                                Divider().background(Theme.hairline)
                                ForEach(app.largeFiles) { item in
                                    ItemRow(item: item, selected: app.largeSelected.contains(item.path)) {
                                        if app.largeSelected.contains(item.path) { app.largeSelected.remove(item.path) }
                                        else { app.largeSelected.insert(item.path) }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }

            if !selectedItems.isEmpty {
                handPickedBar(count: selectedItems.count, bytes: selectedBytes) {
                    confirming.value = true
                }
            }
        }
        .alert("Remove \(selectedItems.count) files?", isPresented: $confirming.value) {
            Button("Cancel", role: .cancel) { }
            Button(app.removalMethod == .trash ? "Move to Trash" : "Delete", role: .destructive) {
                let items = selectedItems
                app.removeHandPicked(items) { _ in
                    app.largeFiles.removeAll { app.largeSelected.contains($0.path) }
                    app.largeSelected = []
                }
            }
        } message: {
            Text("These are your own documents and downloads. Purge has no idea whether you still need them — please check the list first.")
        }
    }
}

// MARK: - Duplicates

struct DuplicatesView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var confirming = Local(false)

    private var selectedItems: [CleanItem] {
        app.duplicateSets.flatMap(\.extras).filter { app.duplicateSelected.contains($0.path) }
    }
    private var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeading(title: "Duplicates",
                                   subtitle: "Byte-for-byte identical files, verified with a full SHA-256 — not guessed from the name.")

                    Card {
                        VStack(alignment: .leading, spacing: 15) {
                            ScopePicker()
                            HStack {
                                Text("Files under 1 MB are ignored, and the oldest copy in each set is always kept.")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.textFaint)
                                Spacer()
                                if app.isFindingDuplicates {
                                    ProgressView().controlSize(.small)
                                    Button("Stop") { app.cancelDuplicates() }
                                        .buttonStyle(GhostButtonStyle())
                                } else {
                                    Button {
                                        app.findDuplicates()
                                    } label: { Label("Find duplicates", systemImage: "square.on.square") }
                                    .buttonStyle(PrimaryButtonStyle())
                                    .disabled(app.largeRoots.isEmpty)
                                }
                            }
                            if !app.duplicateStatus.isEmpty {
                                Text(app.duplicateStatus)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textFaint)
                            }
                        }
                    }

                    if app.duplicateSets.isEmpty && !app.isFindingDuplicates {
                        EmptyState(symbol: "square.on.square",
                                   title: "No duplicates found yet",
                                   message: "Choose folders above and run a search. Comparison is exact — same size, same head and tail, same full hash.")
                    } else {
                        HStack {
                            Text("\(app.duplicateSets.count) sets · \(Format.bytes(app.duplicateSets.reduce(0) { $0 + $1.wastedBytes })) wasted")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textMuted)
                            Spacer()
                            Button("Select every extra copy") { app.selectAllDuplicateExtras() }
                                .buttonStyle(GhostButtonStyle())
                            Button("None") { app.duplicateSelected = [] }
                                .buttonStyle(GhostButtonStyle())
                        }

                        ForEach(app.duplicateSets) { set in
                            Card(padding: 0) {
                                VStack(spacing: 0) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(set.keeper?.displayName ?? "—")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(Theme.textPrimary)
                                            Text("\(set.items.count) copies · \(Format.bytes(set.wastedBytes)) recoverable")
                                                .font(.system(size: 11))
                                                .foregroundStyle(Theme.textFaint)
                                        }
                                        Spacer()
                                    }
                                    .padding(16)
                                    Divider().background(Theme.hairline)

                                    if let keeper = set.keeper {
                                        HStack(spacing: 11) {
                                            Image(systemName: "lock.fill")
                                                .font(.system(size: 10))
                                                .foregroundStyle(Theme.green)
                                                .frame(width: 15)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text("Kept — oldest copy")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundStyle(Theme.green)
                                                Text(Format.shortPath(keeper.path))
                                                    .font(.system(size: 9.5, design: .monospaced))
                                                    .foregroundStyle(Theme.textFaint)
                                                    .lineLimit(1).truncationMode(.middle)
                                            }
                                            Spacer()
                                            Text(keeper.sizeText)
                                                .font(.system(size: 11, design: .rounded))
                                                .foregroundStyle(Theme.textFaint)
                                        }
                                        .padding(.horizontal, 18).padding(.vertical, 7)
                                    }

                                    ForEach(set.extras) { extra in
                                        ItemRow(item: extra, selected: app.duplicateSelected.contains(extra.path)) {
                                            if app.duplicateSelected.contains(extra.path) { app.duplicateSelected.remove(extra.path) }
                                            else { app.duplicateSelected.insert(extra.path) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }

            if !selectedItems.isEmpty {
                handPickedBar(count: selectedItems.count, bytes: selectedBytes) { confirming.value = true }
            }
        }
        .alert("Remove \(selectedItems.count) duplicate copies?", isPresented: $confirming.value) {
            Button("Cancel", role: .cancel) { }
            Button(app.removalMethod == .trash ? "Move to Trash" : "Delete", role: .destructive) {
                let items = selectedItems
                app.removeHandPicked(items) { _ in
                    app.duplicateSelected = []
                    app.findDuplicates()
                }
            }
        } message: {
            Text("One copy of each file stays. \(Format.bytes(selectedBytes)) will be reclaimed.")
        }
    }
}

// MARK: - Shared bottom bar

@ViewBuilder
func handPickedBar(count: Int, bytes: Int64, action: @escaping () -> Void) -> some View {
    VStack(spacing: 0) {
        Divider().background(Theme.hairline)
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(count) selected · \(Format.bytes(bytes))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Hand-picked by you")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textFaint)
            }
            Spacer()
            Button(action: action) {
                Label("Remove", systemImage: "trash")
            }
            .buttonStyle(PrimaryButtonStyle(tint: Theme.red))
        }
        .padding(.horizontal, 24).padding(.vertical, 13)
        .background(Theme.sidebarBG)
    }
}
