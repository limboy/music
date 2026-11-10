import SwiftUI

/// Square cover art that never changes layout while loading.
struct Artwork: View {
    let url: URL?
    var cornerRadius: CGFloat = 8
    @State private var image: UIImage?

    init(url: URL?, cornerRadius: CGFloat = 8) {
        self.url = url
        self.cornerRadius = cornerRadius
        _image = State(initialValue: ImageCache.shared.cached(url))
    }

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            }
            .task(id: url) {
                if let hit = ImageCache.shared.cached(url) { image = hit; return }
                let loaded = await ImageCache.shared.image(for: url)
                withAnimation(.easeOut(duration: 0.25)) { image = loaded }
            }
            .accessibilityHidden(true)
    }
}

/// Animated level bars shown next to the track that's playing.
struct LevelBars: View {
    var isPlaying: Bool
    var color: Color
    var bars: Int = 4
    var barWidth: CGFloat = 3
    var maxHeight: CGFloat = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: barWidth * 0.7) {
                ForEach(0..<bars, id: \.self) { i in
                    let k = isPlaying ? 0.3 + 0.7 * abs(sin(t * (2.2 + Double(i) * 0.9) + Double(i) * 1.7)) : 0.25
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth, height: max(barWidth, maxHeight * k))
                }
            }
            .frame(height: maxHeight, alignment: .bottom)
        }
        .accessibilityLabel(isPlaying ? "Now playing" : "Paused")
    }
}

/// Horizontal capsule scrubber (no thumb) used for playback position and volume.
struct Scrubber: View {
    var value: Double                       // 0…1
    var label: String = "Playback position"
    var onChanged: (Double) -> Void = { _ in }
    var onEnded: (Double) -> Void

    @State private var dragValue: Double?
    @GestureState private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let shown = dragValue ?? value
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                Capsule().fill(.white.opacity(0.92))
                    .frame(width: max(0, geo.size.width * shown))
            }
            .frame(height: isDragging ? 10 : 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, s, _ in s = true }
                    .onChanged { g in
                        let v = min(1, max(0, g.location.x / geo.size.width))
                        dragValue = v
                        onChanged(v)
                    }
                    .onEnded { g in
                        let v = min(1, max(0, g.location.x / geo.size.width))
                        onEnded(v)
                        dragValue = nil
                    }
            )
            .animation(.spring(duration: 0.3), value: isDragging)
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: onEnded(min(1, value + 0.05))
            case .decrement: onEnded(max(0, value - 0.05))
            @unknown default: break
            }
        }
    }
}

/// Round glass icon button used in headers.
struct GlassIconButton: View {
    let systemName: String
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}
