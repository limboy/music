import AVKit
import MediaPlayer
import SwiftUI

struct NowPlayingView: View {
    @Environment(Player.self) private var player
    @Environment(LyricsService.self) private var lyrics
    @Environment(\.dismiss) private var dismiss
    @State private var showLyrics = false
    @State private var showQueue = false
    @State private var scrubTime: TimeInterval?
    @Namespace private var art

    var body: some View {
        if let track = player.current {
            ZStack {
                VStack(spacing: 0) {
                    topBar(track)
                        .padding(.horizontal, 12)

                    if showLyrics {
                        compactHeader(track)
                            .padding(.horizontal, 24)
                            .padding(.top, 18)
                        LyricsPanel(track: track)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 30)), removal: .opacity))
                    } else {
                        Spacer(minLength: 16)
                        Artwork(url: track.coverURL(thumb: 600), cornerRadius: 18)
                            .matchedGeometryEffect(id: "art", in: art)
                            .aspectRatio(1, contentMode: .fit)
                            .shadow(color: .black.opacity(0.5), radius: 30, y: 24)
                            .scaleEffect(player.isPlaying ? 1 : 0.86)
                            .animation(.spring(duration: 0.6, bounce: 0.35), value: player.isPlaying)
                            .padding(.horizontal, 32)
                        Spacer(minLength: 24)
                        titleBlock(track)
                            .padding(.horizontal, 32)
                    }

                    controls(track)
                        .padding(.horizontal, 32)
                        .padding(.top, 22)
                        .padding(.bottom, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { AmbientBackground(track: track) }
            .foregroundStyle(.white)
            .task(id: track.id) { await lyrics.load(track) }
            .sheet(isPresented: $showQueue) {
                QueueSheet()
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.ultraThinMaterial)
            }
        } else {
            Color.black.onAppear { dismiss() }
        }
    }

    // MARK: Pieces

    private func topBar(_ track: Track) -> some View {
        HStack {
            GlassIconButton(systemName: "chevron.down", label: "Close Now Playing") { dismiss() }
            Spacer()
            VStack(spacing: 1) {
                Text("PLAYING FROM")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(.white.opacity(0.7))
                Text(track.type.title)
                    .font(.system(size: 14, weight: .semibold))
            }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.top, 8)
    }

    private func titleBlock(_ track: Track) -> some View {
        // Each line is matched with its counterpart in `compactHeader`, so toggling lyrics
        // flies the title and singer up into the header instead of sliding them away.
        VStack(alignment: .center, spacing: 3) {
            Text(track.title)
                .font(.system(size: 22, weight: .semibold))
                .matchedGeometryEffect(id: "title", in: art, properties: .position)
            Text(track.artist)
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.7))
                .matchedGeometryEffect(id: "artist", in: art, properties: .position)
        }
        .lineLimit(1)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .contextMenu { DownloadMenuItems(track: track) }
        .animation(.spring(duration: 0.45), value: track.id)
    }

    private func compactHeader(_ track: Track) -> some View {
        HStack(spacing: 12) {
            Artwork(url: track.coverURL(thumb: 600), cornerRadius: 8)
                .matchedGeometryEffect(id: "art", in: art)
                .frame(width: 56, height: 56)
                .shadow(color: .black.opacity(0.4), radius: 10, y: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 17, weight: .semibold))
                    .matchedGeometryEffect(id: "title", in: art, properties: .position)
                Text(track.artist)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.7))
                    .matchedGeometryEffect(id: "artist", in: art, properties: .position)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func controls(_ track: Track) -> some View {
        VStack(spacing: 0) {
            // Progress
            let duration = max(player.duration, 1)
            let shownTime = scrubTime ?? player.currentTime
            Scrubber(value: shownTime / duration) { v in
                scrubTime = v * duration
            } onEnded: { v in
                player.seek(to: v * duration)
                scrubTime = nil
            }
            HStack {
                Text(shownTime.clock)
                Spacer()
                Text("-" + (duration - shownTime).clock)
            }
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.7))

            // Transport
            HStack(spacing: 0) {
                transportButton("backward.fill", size: 34, label: "Previous track") { player.previous() }
                Spacer()
                Button { player.togglePlay() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 46))
                        .contentTransition(.symbolEffect(.replace.downUp))
                        .frame(width: 80, height: 80)
                        .overlay {
                            if player.isBuffering { ProgressView().tint(.white).offset(y: 44) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Spacer()
                transportButton("forward.fill", size: 34, label: "Next track") { player.next() }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)

            // Volume
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill").font(.system(size: 13))
                VolumeBar()
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 13))
            }
            .foregroundStyle(.white.opacity(0.7))

            // Bottom actions
            HStack {
                Button {
                    withAnimation(.spring(duration: 0.6, bounce: 0.12)) { showLyrics.toggle() }
                } label: {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(showLyrics ? Color.black : .white.opacity(0.85))
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(showLyrics ? 0.92 : 0)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Lyrics")
                .accessibilityAddTraits(showLyrics ? .isSelected : [])
                Spacer()
                AirPlayButton().frame(width: 44, height: 44)
                Spacer()
                Button { showQueue = true } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Up next")
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
        }
    }

    private func transportButton(_ symbol: String, size: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .frame(width: 64, height: 64)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }
}

private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

// MARK: - Background

private struct AmbientBackground: View {
    let track: Track

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.08)
            Artwork(url: track.coverURL(thumb: 100), cornerRadius: 0)
                .scaleEffect(1.6)
                .blur(radius: 70)
                .saturation(1.5)
                .brightness(-0.18)
                .id(track.id)
                .transition(.opacity)
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.35), .black.opacity(0.6)],
                           startPoint: .top, endPoint: .bottom)
        }
        .animation(.easeInOut(duration: 0.8), value: track.id)
        .ignoresSafeArea()
    }
}

// MARK: - Lyrics

private struct LyricsPanel: View {
    let track: Track
    @Environment(Player.self) private var player
    @Environment(LyricsService.self) private var lyrics
    @State private var position = ScrollPosition(idType: Int.self)

    var body: some View {
        Group {
            switch lyrics.state(for: track) {
            case .loading:
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unavailable:
                NoLyricsView(track: track)
            case .loaded(let l):
                lyricList(l)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func lyricList(_ l: Lyrics) -> some View {
        let active = l.activeIndex(at: player.currentTime + 0.2)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 120)
                ForEach(l.lines) { line in
                    let distance = abs(line.id - (active ?? -1))
                    Button { player.seek(to: line.time) } label: {
                        Text(line.text)
                            .font(.system(size: 28, weight: .bold))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                            .opacity(line.id == active ? 1 : (distance == 1 ? 0.4 : 0.28))
                            .blur(radius: line.id == active ? 0 : min(1.6, Double(distance) * 0.5))
                            .scaleEffect(line.id == active ? 1 : 0.96, anchor: .leading)
                            .animation(.spring(duration: 0.55), value: active)
                    }
                    .buttonStyle(.plain)
                    .id(line.id)
                }
                Text(l.source == .lrclib ? "Lyrics from LRCLIB" : "Synced lyrics from your library")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 24)
                Color.clear.frame(height: 200)
            }
            .padding(.horizontal, 32)
            .scrollTargetLayout()
        }
        .scrollPosition($position, anchor: .center)
        .scrollIndicators(.hidden)
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.14),
                                     .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .onAppear { position.scrollTo(id: active ?? 0, anchor: .center) }
        .onChange(of: active) { _, new in
            withAnimation(.spring(duration: 0.7, bounce: 0.1)) {
                position.scrollTo(id: new ?? 0, anchor: .center)
            }
        }
    }
}

private struct NoLyricsView: View {
    let track: Track
    @Environment(Player.self) private var player

    var body: some View {
        VStack(spacing: 18) {
            LevelBars(isPlaying: player.isPlaying, color: .white.opacity(0.9), bars: 7, barWidth: 6, maxHeight: 56)
            VStack(spacing: 6) {
                Text(track.type == .song ? "No lyrics found" : "Instrumental")
                    .font(.system(size: 24, weight: .bold))
                Text(track.type == .song ? "LRCLIB doesn’t have synced lyrics for this one." : "Nothing to sing along to — just listen.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Queue

private struct QueueSheet: View {
    @Environment(Player.self) private var player

    var body: some View {
        NavigationStack {
            List {
                if let current = player.current {
                    Section("Now Playing") { QueueRow(track: current) }
                }
                Section("Up Next") {
                    ForEach(player.upNext) { t in
                        Button { player.playFromQueue(t) } label: { QueueRow(track: t) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct QueueRow: View {
    let track: Track
    var body: some View {
        HStack(spacing: 12) {
            Artwork(url: track.coverURL(thumb: 100), cornerRadius: 6).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.system(size: 15, weight: .medium))
                Text(track.artist).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            Text(track.seconds.clock).font(.footnote).monospacedDigit().foregroundStyle(.secondary)
        }
        .listRowBackground(Color.clear)
    }
}

// MARK: - System bridges

private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = UIColor.white.withAlphaComponent(0.85)
        v.activeTintColor = .white
        v.prioritizesVideoDevices = false
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// System volume drawn with the same thumbless capsule as the progress bar.
/// iOS only lets apps change volume through MPVolumeView, so a tiny, invisible one sits behind the bar
/// and its slider is driven programmatically. Having it on screen also suppresses the system volume HUD.
private struct VolumeBar: View {
    @State private var volume = VolumeController()

    var body: some View {
        Scrubber(value: volume.level, label: "Volume") { v in
            volume.set(v)
        } onEnded: { v in
            volume.set(v)
        }
        .background(alignment: .leading) {
            HiddenVolumeView(controller: volume)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityHidden(true)
        }
        .animation(.easeOut(duration: 0.15), value: volume.level)
    }
}

@Observable
private final class VolumeController {
    private(set) var level = Double(AVAudioSession.sharedInstance().outputVolume)
    @ObservationIgnored weak var slider: UISlider?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init() {
        // Follow the hardware volume buttons.
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
            let v = Double(session.outputVolume)
            Task { @MainActor in self?.level = v }
        }
    }

    func set(_ value: Double) {
        level = value
        slider?.setValue(Float(value), animated: false)
        slider?.sendActions(for: .valueChanged)
    }
}

private struct HiddenVolumeView: UIViewRepresentable {
    let controller: VolumeController

    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        v.isUserInteractionEnabled = false
        controller.slider = v.subviews.compactMap { $0 as? UISlider }.first
        return v
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        if controller.slider == nil {
            controller.slider = uiView.subviews.compactMap { $0 as? UISlider }.first
        }
    }
}
