import AVFoundation
import MediaPlayer
import Observation
import UIKit

@Observable
final class Player {
    private(set) var queue: [Track] = []
    private(set) var index: Int = 0
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isBuffering = false

    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }
    var upNext: [Track] { queue.indices.contains(index + 1) ? Array(queue[(index + 1)...]) : [] }
    var progress: Double { duration > 0 ? min(1, currentTime / duration) : 0 }

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var isSeeking = false
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private let downloads: Downloads
    @ObservationIgnored private let connectivity: Connectivity

    /// Offline, only downloaded tracks can play.
    func isPlayable(_ track: Track) -> Bool {
        connectivity.isOnline || downloads.isDownloaded(track)
    }

    init(downloads: Downloads, connectivity: Connectivity) {
        self.downloads = downloads
        self.connectivity = connectivity
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
        player.automaticallyWaitsToMinimizeStalling = true

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isSeeking else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
            }
        }

        observers.append(NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance(by: 1, wrap: true) }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            MainActor.assumeIsolated {
                if type == .began { self?.pause() }
            }
        })

        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            let waiting = p.timeControlStatus == .waitingToPlayAtSpecifiedRate
            Task { @MainActor in self?.isBuffering = waiting }
        }

        setupRemoteCommands()
    }

    // MARK: Transport

    func play(_ track: Track, in list: [Track]) {
        guard isPlayable(track) else { return }
        let playable = list.filter(isPlayable)
        queue = playable
        index = playable.firstIndex(of: track) ?? 0
        load()
    }

    func shuffle(_ list: [Track]) {
        let playable = list.filter(isPlayable)
        guard !playable.isEmpty else { return }
        queue = playable.shuffled()
        index = 0
        load()
    }

    func togglePlay() {
        isPlaying ? pause() : resume()
    }

    func resume() {
        guard current != nil else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    func next() { advance(by: 1, wrap: true) }

    func previous() {
        if currentTime > 3 { seek(to: 0) } else { advance(by: -1, wrap: true) }
    }

    func playFromQueue(_ track: Track) {
        guard let i = queue.firstIndex(of: track) else { return }
        index = i
        load()
    }

    func seek(to time: TimeInterval) {
        let t = max(0, min(time, duration))
        currentTime = t
        isSeeking = true
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.isSeeking = false
                self?.updateNowPlayingInfo()
            }
        }
    }

    // MARK: Internals

    private func advance(by delta: Int, wrap: Bool) {
        guard !queue.isEmpty else { return }
        // Skip tracks that can't play right now (offline and not downloaded).
        var i = index
        for _ in 0..<queue.count {
            i += delta
            if wrap { i = (i + queue.count) % queue.count }
            guard queue.indices.contains(i) else { return }
            if isPlayable(queue[i]) {
                index = i
                load()
                return
            }
        }
        pause()
    }

    private func load() {
        guard let track = current else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: downloads.localURL(for: track) ?? track.audioURL)
        player.replaceCurrentItem(with: item)
        currentTime = 0
        duration = track.seconds
        player.play()
        isPlaying = true
        updateNowPlayingInfo()
        loadArtwork(for: track)

        // The PocketBase "duration" is a hint; prefer the real one once known.
        Task { [weak self] in
            if let d = try? await item.asset.load(.duration), d.seconds.isFinite, d.seconds > 0 {
                guard let self, self.current?.id == track.id else { return }
                self.duration = d.seconds
                self.updateNowPlayingInfo()
            }
        }
    }

    // MARK: Lock screen / Control Center

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }; return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }; return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlay() }; return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }; return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }; return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let t = e.positionTime
            Task { @MainActor in self?.seek(to: t) }
            return .success
        }
    }

    @ObservationIgnored private var artwork: MPMediaItemArtwork?

    private func updateNowPlayingInfo() {
        guard let track = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(for track: Track) {
        artwork = nil
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            guard let image = await ImageCache.shared.image(for: track.coverURL(thumb: 600)) else { return }
            guard let self, !Task.isCancelled, self.current?.id == track.id else { return }
            self.artwork = Self.makeArtwork(image)
            self.updateNowPlayingInfo()
        }
    }

    /// Built outside the main actor: MediaPlayer calls the handler on a background queue.
    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
