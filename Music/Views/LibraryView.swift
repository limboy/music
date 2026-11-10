import SwiftUI

struct LibraryView: View {
    @Environment(Library.self) private var library
    @State private var kind: TrackKind = .song
    @State private var query = ""
    @State private var searching = false
    @State private var showDownloads = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

            TabView(selection: $kind) {
                ForEach(TrackKind.allCases) { k in
                    CategoryPage(kind: k, query: query)
                        .tag(k)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)   // let rows scroll under the glass mini player
        }
        .background(Color(red: 0.04, green: 0.04, blue: 0.045).ignoresSafeArea())
        .sheet(isPresented: $showDownloads) {
            DownloadsSheet()
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Library")
                    .font(.system(size: 34, weight: .bold))
                Spacer()
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        GlassIconButton(systemName: searching ? "xmark" : "magnifyingglass",
                                        label: searching ? "Close search" : "Search library") {
                            withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                                searching.toggle()
                                if !searching { query = "" }
                            }
                            searchFocused = searching
                        }
                        GlassIconButton(systemName: "arrow.down.circle", label: "Downloads") {
                            showDownloads = true
                        }
                        SyncButton()
                    }
                }
            }
            .frame(height: 52)

            SyncStatus()
                .padding(.top, 4)

            if searching {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search \(kind.title.lowercased())", text: $query)
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .glassEffect(.regular, in: .capsule)
                .padding(.top, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            CategoryPicker(selection: $kind)
                .padding(.top, 16)
        }
    }
}

// MARK: - Sync

private struct SyncButton: View {
    @Environment(Library.self) private var library

    var body: some View {
        Button {
            Task { await library.sync() }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 17, weight: .semibold))
                .symbolEffect(.rotate.byLayer, options: .repeat(.continuous), isActive: library.isSyncing)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .disabled(library.isSyncing)
        .accessibilityLabel("Sync with PocketBase")
    }
}

private struct SyncStatus: View {
    @Environment(Library.self) private var library
    @Environment(Downloads.self) private var downloads
    @Environment(Connectivity.self) private var connectivity

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Circle().fill(dotColor).frame(width: 7, height: 7)
                    Text(label)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .font(.footnote)
                .foregroundStyle(Color(white: 0.64))

                if case .syncing(let done, let total) = library.syncState {
                    ProgressView(value: Double(done), total: Double(max(total, 1)))
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .scaleEffect(y: 0.6)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: library.syncState)
        }
    }

    private var dotColor: Color {
        if !connectivity.isOnline { return Color(white: 0.5) }
        return switch library.syncState {
        case .idle: library.lastSynced == nil ? .gray : .green
        case .syncing: TrackKind.jazz.accent
        case .failed: .red
        }
    }

    private var label: String {
        if !connectivity.isOnline {
            return "Offline · \(downloads.downloadedCount) downloaded tracks available"
        }
        switch library.syncState {
        case .syncing(let done, let total):
            return "Syncing pb.limboy.me · \(done) of \(total)"
        case .failed:
            return "Sync failed · showing \(library.tracks.count) cached tracks"
        case .idle:
            guard let date = library.lastSynced else { return "Not synced yet" }
            let ago = date.timeIntervalSinceNow > -60 ? "just now" : date.formatted(.relative(presentation: .named))
            return "\(library.tracks.count) tracks · Synced \(ago)"
        }
    }
}

// MARK: - Category picker

private struct CategoryPicker: View {
    @Binding var selection: TrackKind
    @Environment(Library.self) private var library
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TrackKind.allCases) { k in
                Button {
                    withAnimation(.spring(duration: 0.45, bounce: 0.18)) { selection = k }
                } label: {
                    HStack(spacing: 6) {
                        Text(k.title).font(.system(size: 14, weight: .semibold))
                        Text("\(library.count(of: k))")
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .opacity(0.6)
                            .contentTransition(.numericText())
                    }
                    .foregroundStyle(selection == k ? Color.white : Color(white: 0.62))
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background {
                        if selection == k {
                            Capsule()
                                .fill(.white.opacity(0.16))
                                .shadow(color: .black.opacity(0.25), radius: 5, y: 3)
                                .matchedGeometryEffect(id: "indicator", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == k ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color(red: 0.46, green: 0.46, blue: 0.5).opacity(0.22)))
    }
}

// MARK: - Category page

private struct CategoryPage: View {
    let kind: TrackKind
    let query: String
    @Environment(Library.self) private var library
    @Environment(Player.self) private var player

    private var tracks: [Track] {
        let all = library.tracks(of: kind)
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(q) ||
            $0.artist.localizedCaseInsensitiveContains(q) ||
            $0.album.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        let tracks = self.tracks
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 12) {
                    actionButton("Play", icon: "play.fill") {
                        if let first = tracks.first { player.play(first, in: tracks) }
                    }
                    actionButton("Shuffle", icon: "shuffle") {
                        player.shuffle(tracks)
                    }
                }
                .disabled(tracks.isEmpty)

                if tracks.isEmpty {
                    emptyState
                } else if kind == .song {
                    LazyVStack(spacing: 0) {
                        ForEach(tracks) { t in
                            SongRow(track: t, accent: kind.accent) { player.play(t, in: tracks) }
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 22) {
                        ForEach(tracks) { t in
                            CoverCell(track: t, accent: kind.accent) { player.play(t, in: tracks) }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, player.current == nil ? 40 : 120, for: .scrollContent)
        .refreshable { await library.sync() }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(kind.accent)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(red: 0.46, green: 0.46, blue: 0.5).opacity(0.2)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 8) {
            if library.isSyncing && library.tracks.isEmpty {
                ProgressView()
                Text("Fetching your library…")
            } else if !query.isEmpty {
                Image(systemName: "magnifyingglass").font(.title2)
                Text("No matches for “\(query)”")
            } else {
                Image(systemName: "music.note.list").font(.title2)
                Text("Nothing here yet. Pull to sync.")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

// MARK: - Cells

private struct SongRow: View {
    let track: Track
    let accent: Color
    let action: () -> Void
    @Environment(Player.self) private var player

    var body: some View {
        let isCurrent = player.current?.id == track.id
        Button(action: action) {
            HStack(spacing: 12) {
                Artwork(url: track.coverURL(thumb: 100), cornerRadius: 8)
                    .frame(width: 48, height: 48)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(isCurrent ? accent : .white)
                        HStack(spacing: 5) {
                            DownloadBadge(track: track, size: 12)
                            Text(track.subtitle)
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(Color(white: 0.64))
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    if isCurrent {
                        LevelBars(isPlaying: player.isPlaying, color: accent)
                    } else {
                        Text(track.seconds.clock)
                            .font(.system(size: 13))
                            .monospacedDigit()
                            .foregroundStyle(Color(white: 0.64))
                    }
                }
                .frame(height: 64)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(player.isPlayable(track) ? 1 : 0.35)
        .disabled(!player.isPlayable(track))
        .contextMenu { DownloadMenuItems(track: track) }
        .animation(.easeInOut(duration: 0.25), value: isCurrent)
    }
}

private struct CoverCell: View {
    let track: Track
    let accent: Color
    let action: () -> Void
    @Environment(Player.self) private var player

    var body: some View {
        let isCurrent = player.current?.id == track.id
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Artwork(url: track.coverURL(thumb: 400), cornerRadius: 14)
                    .aspectRatio(1, contentMode: .fit)
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 10)
                    .overlay(alignment: .bottomTrailing) {
                        if isCurrent {
                            LevelBars(isPlaying: player.isPlaying, color: accent, barWidth: 2.5, maxHeight: 13)
                                .frame(width: 30, height: 30)
                                .glassEffect(.regular, in: .circle)
                                .padding(8)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isCurrent ? accent : .white)
                    HStack(spacing: 5) {
                        DownloadBadge(track: track, size: 12)
                        Text(track.artist)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Color(white: 0.64))
                }
                .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(player.isPlayable(track) ? 1 : 0.35)
        .disabled(!player.isPlayable(track))
        .contextMenu { DownloadMenuItems(track: track) }
        .animation(.spring(duration: 0.35), value: isCurrent)
    }
}
