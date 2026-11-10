import SwiftUI

/// Small inline indicator: progress ring while downloading, filled arrow when saved.
struct DownloadBadge: View {
    let track: Track
    var size: CGFloat = 13
    @Environment(Downloads.self) private var downloads

    var body: some View {
        Group {
            switch downloads.state(for: track) {
            case .none:
                EmptyView()
            case .queued:
                Circle()
                    .strokeBorder(Color(white: 0.64), style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                    .frame(width: size, height: size)
                    .accessibilityLabel("Waiting to download")
            case .downloading(let p):
                ZStack {
                    Circle().stroke(.white.opacity(0.18), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: max(0.03, p))
                        .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.2), value: p)
                }
                .frame(width: size, height: size)
                .accessibilityLabel("Downloading, \(Int(p * 100)) percent")
            case .done:
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: size))
                    .foregroundStyle(Color(white: 0.64))
                    .accessibilityLabel("Downloaded")
            case .failed:
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: size))
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Download failed")
            }
        }
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(duration: 0.35), value: downloads.state(for: track))
    }
}

/// Context-menu items for one track.
struct DownloadMenuItems: View {
    let track: Track
    @Environment(Downloads.self) private var downloads

    var body: some View {
        switch downloads.state(for: track) {
        case .none, .failed:
            Button("Download", systemImage: "arrow.down.circle") { downloads.download([track]) }
        case .queued, .downloading:
            Button("Cancel Download", systemImage: "xmark.circle") { downloads.cancel(track) }
        case .done:
            Button("Remove Download", systemImage: "trash", role: .destructive) { downloads.remove([track]) }
        }
    }
}

/// Storage overview + per-category bulk download.
struct DownloadsSheet: View {
    @Environment(Library.self) private var library
    @Environment(Downloads.self) private var downloads
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemoveAll = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(downloads.totalBytes.formatted(.byteCount(style: .file)))
                            .font(.system(size: 34, weight: .bold))
                            .contentTransition(.numericText())
                        Text("\(downloads.downloadedCount) of \(library.tracks.count) tracks available offline")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    .padding(.vertical, 6)
                    .animation(.smooth, value: downloads.downloadedCount)
                }

                Section("Collections") {
                    ForEach(TrackKind.allCases) { kind in
                        CollectionDownloadRow(kind: kind)
                    }
                }

                if downloads.isBusy {
                    Section {
                        Button("Stop All Downloads", systemImage: "stop.circle") { downloads.cancelAll() }
                    }
                }

                if downloads.downloadedCount > 0 {
                    Section {
                        Button("Remove All Downloads", systemImage: "trash", role: .destructive) {
                            confirmRemoveAll = true
                        }
                    } footer: {
                        Text("Downloaded tracks play without a connection. Tracks removed from PocketBase are deleted from this iPhone on the next sync.")
                    }
                }
            }
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .confirmationDialog("Remove all \(downloads.downloadedCount) downloads?", isPresented: $confirmRemoveAll, titleVisibility: .visible) {
                Button("Remove All", role: .destructive) { downloads.removeAll() }
            } message: {
                Text("This frees \(downloads.totalBytes.formatted(.byteCount(style: .file))). You can download them again any time.")
            }
        }
    }
}

private struct CollectionDownloadRow: View {
    let kind: TrackKind
    @Environment(Library.self) private var library
    @Environment(Downloads.self) private var downloads

    var body: some View {
        let tracks = library.tracks(of: kind)
        let done = downloads.downloadedCount(in: tracks)
        let total = tracks.count
        let busy = tracks.contains { if case .downloading = downloads.state(for: $0) { true } else { downloads.state(for: $0) == .queued } }

        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(kind.accent.opacity(0.2), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: total == 0 ? 0 : Double(done) / Double(total))
                    .stroke(kind.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth, value: done)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).font(.body.weight(.semibold))
                Text("\(done) of \(total) downloaded")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer()
            Menu {
                if done < total {
                    Button("Download All \(total - done)", systemImage: "arrow.down.circle") { downloads.download(tracks) }
                }
                if busy {
                    Button("Stop", systemImage: "stop.circle") { tracks.forEach(downloads.cancel) }
                }
                if done > 0 {
                    Button("Remove \(done) Downloads", systemImage: "trash", role: .destructive) { downloads.remove(tracks) }
                }
            } label: {
                Image(systemName: done == total && total > 0 ? "checkmark.circle.fill" : (busy ? "ellipsis.circle" : "arrow.down.circle"))
                    .font(.system(size: 24))
                    .foregroundStyle(kind.accent)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("\(kind.title) download options")
        }
    }
}
