import SwiftUI

struct MiniPlayer: View {
    var open: () -> Void
    @Environment(Player.self) private var player

    var body: some View {
        if let track = player.current {
            HStack(spacing: 4) {
                Button(action: open) {
                    HStack(spacing: 12) {
                        Artwork(url: track.coverURL(thumb: 100), cornerRadius: 10)
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(track.title)
                                .font(.system(size: 15, weight: .semibold))
                            Text(track.artist)
                                .font(.system(size: 13))
                                .foregroundStyle(Color(white: 0.64))
                        }
                        .lineLimit(1)
                        .id(track.id)
                        .transition(.push(from: .bottom).combined(with: .opacity))
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Now playing: \(track.title) by \(track.artist)")
                .accessibilityHint("Opens the player")

                Button { player.togglePlay() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                Button { player.next() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 20))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next track")
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .frame(height: 64)
            .overlay(alignment: .bottom) {
                GeometryReader { geo in
                    Capsule()
                        .fill(track.type.accent)
                        .frame(width: geo.size.width * player.progress, height: 2)
                        .animation(.linear(duration: 0.25), value: player.progress)
                }
                .frame(height: 2)
                .padding(.horizontal, 28)
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 32, style: .continuous))
            .animation(.spring(duration: 0.4), value: track.id)
        }
    }
}
