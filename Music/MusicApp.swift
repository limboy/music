import SwiftUI

@main
struct MusicApp: App {
    @State private var library = Library()
    @State private var lyrics = LyricsService()
    @State private var downloads: Downloads
    @State private var connectivity: Connectivity
    @State private var player: Player

    init() {
        let downloads = Downloads()
        let connectivity = Connectivity()
        _downloads = State(initialValue: downloads)
        _connectivity = State(initialValue: connectivity)
        _player = State(initialValue: Player(downloads: downloads, connectivity: connectivity))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(player)
                .environment(lyrics)
                .environment(downloads)
                .environment(connectivity)
                .preferredColorScheme(.dark)
                .tint(.white)
        }
    }
}

struct RootView: View {
    @Environment(Library.self) private var library
    @Environment(Player.self) private var player
    @Environment(Downloads.self) private var downloads
    @State private var showPlayer = false
    @Namespace private var transition

    var body: some View {
        LibraryView()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if player.current != nil {
                    MiniPlayer { showPlayer = true }
                        .matchedTransitionSource(id: "nowPlaying", in: transition)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.5, bounce: 0.2), value: player.current == nil)
            .fullScreenCover(isPresented: $showPlayer) {
                NowPlayingView()
                    .navigationTransition(.zoom(sourceID: "nowPlaying", in: transition))
            }
            .task {
                await library.sync()
                // Only prune after a successful sync, so a network error never deletes downloads.
                if library.syncState == .idle, !library.tracks.isEmpty {
                    downloads.prune(keeping: Set(library.tracks.map(\.id)))
                }
            }
    }
}
