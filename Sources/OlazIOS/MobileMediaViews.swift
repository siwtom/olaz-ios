import AVFoundation
import AVKit
import SwiftUI
import UIKit

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct MobileAsyncPhotoView: View {
    let url: URL?
    var maxPixelSize: CGFloat = 960
    var contentMode: ContentMode = .fill

    @State private var image: PlatformImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let displayImage {
                Image(platformImage: displayImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
                ZStack {
                    Color(.tertiarySystemFill)
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            } else {
                ZStack {
                    Color(.tertiarySystemFill)
                    ProgressView()
                }
            }
        }
        .task(id: url) {
            image = nil
            failed = false
            guard let url else {
                failed = true
                return
            }
            if let cached = MediaLoader.cachedImage(for: url, maxPixelSize: maxPixelSize) {
                image = cached
                return
            }
            if let loaded = await MediaLoader.shared.image(for: url, maxPixelSize: maxPixelSize) {
                image = loaded.image
            } else {
                failed = true
            }
        }
    }

    private var displayImage: PlatformImage? {
        if let image { return image }
        guard let url else { return nil }
        return MediaLoader.cachedImage(for: url, maxPixelSize: maxPixelSize)
    }
}

struct MobileAnimatedStickerView: View {
    let url: URL?
    var size: CGFloat = 132

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                UIKitAnimatedImageRepresentable(image: image)
                    .frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: size, height: size)
                    .overlay { ProgressView() }
            }
        }
        .task(id: url) {
            image = nil
            guard let url else { return }
            if let cachedAnim = MediaLoader.cachedAnimatedImage(for: url) {
                image = cachedAnim
                return
            }
            if let animated = await MediaLoader.shared.animatedImage(for: url) {
                image = animated.image
                return
            }
            if let still = await MediaLoader.shared.image(for: url, maxPixelSize: 512) {
                image = still.image
            }
        }
    }
}

private struct UIKitAnimatedImageRepresentable: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.backgroundColor = .clear
        return iv
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        if uiView.image !== image {
            uiView.image = image
        }
    }
}

struct PhotoViewerItem: Identifiable {
    let id = UUID()
    let engine: ZaloEngine
    let conversationId: String
    let messageId: String
    let fallbackURL: URL?
}

struct MobilePhotoViewerSheet: View {
    let item: PhotoViewerItem
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var rawData: Data?
    @State private var loading = true
    @State private var errorText: String?
    @State private var showShare = false
    @State private var savedMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image {
                    ZoomableImageScrollView(image: image)
                        .ignoresSafeArea()
                } else if loading {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.large)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.75))
                        Text(errorText ?? "Không thể tải ảnh độ phân giải cao.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                if let savedMessage {
                    VStack {
                        Spacer()
                        Text(savedMessage)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 28)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Đóng") { dismiss() }
                        .foregroundStyle(.white)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let image {
                        Button {
                            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                            savedMessage = "Đã lưu vào Ảnh"
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .foregroundStyle(.white)

                        Button {
                            showShare = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .foregroundStyle(.white)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .task {
            await loadFullPhoto()
        }
        .sheet(isPresented: $showShare) {
            if let rawData, let tempURL = writeTempImage(rawData) {
                ActivityShareSheet(items: [tempURL]).ignoresSafeArea()
            } else if let image {
                ActivityShareSheet(items: [image]).ignoresSafeArea()
            }
        }
    }

    private func loadFullPhoto() async {
        loading = true
        defer { loading = false }

        if !item.conversationId.isEmpty && !item.messageId.isEmpty {
            let resolved = await item.engine.resolveMedia(
                conversationId: item.conversationId,
                messageId: item.messageId,
                kind: .photo
            )
            switch resolved {
            case .file(let fileURL):
                if MediaLoader.isAllowedLocalFile(fileURL),
                   let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
                   let img = PlatformImageCodec.decode(data: data) {
                    self.rawData = data
                    self.image = img
                    return
                }
            case .expired:
                self.errorText = "Ảnh này đã quá hạn lưu trữ trên Zalo."
            case .unavailable, .unsupported:
                break
            }
        }

        if let fallbackURL = item.fallbackURL {
            if let loaded = await MediaLoader.shared.image(for: fallbackURL, maxPixelSize: 2400, cache: false) {
                self.image = loaded.image
                return
            }
        }
        if errorText == nil {
            errorText = "Không thể giải mã hoặc tải ảnh."
        }
    }

    private func writeTempImage(_ data: Data) -> URL? {
        let dir = FileManager.default.temporaryDirectory
        let file = dir.appendingPathComponent("olaz-photo-\(UUID().uuidString).jpg")
        try? data.write(to: file)
        return file
    }
}

private struct ZoomableImageScrollView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.backgroundColor = .clear
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1.0
        scroll.maximumZoomScale = 4.0
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false

        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFit
        iv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        iv.frame = scroll.bounds
        scroll.addSubview(iv)
        context.coordinator.imageView = iv
        return scroll
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    }
}

struct VideoViewerItem: Identifiable {
    let id = UUID()
    let engine: ZaloEngine
    let conversationId: String
    let messageId: String
    let fallbackURL: URL?
}

struct MobileVideoPlayerSheet: View {
    let item: VideoViewerItem
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var fileURL: URL?
    @State private var loading = true
    @State private var errorText: String?
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea(edges: .bottom)
                } else if loading {
                    ProgressView("Đang tải video...")
                        .tint(.white)
                        .foregroundStyle(.white)
                } else {
                    Text(errorText ?? "Không phát được video này.")
                        .foregroundStyle(.white)
                        .padding()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Đóng") {
                        player?.pause()
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if fileURL != nil {
                        Button {
                            showShare = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .foregroundStyle(.white)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .task {
            await prepareVideo()
        }
        .onDisappear {
            player?.pause()
        }
        .sheet(isPresented: $showShare) {
            if let fileURL {
                ActivityShareSheet(items: [fileURL]).ignoresSafeArea()
            }
        }
    }

    private func prepareVideo() async {
        loading = true
        defer { loading = false }

        if !item.conversationId.isEmpty && !item.messageId.isEmpty {
            let resolved = await item.engine.resolveMedia(
                conversationId: item.conversationId,
                messageId: item.messageId,
                kind: .video
            )
            switch resolved {
            case .file(let url):
                fileURL = url
                startPlayback(url)
                return
            case .expired:
                errorText = "Video này đã quá hạn lưu trữ trên Zalo."
            case .unavailable, .unsupported:
                break
            }
        }

        if let fallbackURL = item.fallbackURL,
           let local = try? await MediaLoader.shared.localFile(for: fallbackURL) {
            fileURL = local
            startPlayback(local)
            return
        }
        if errorText == nil {
            errorText = "Không thể phát hoặc tải video."
        }
    }

    private func startPlayback(_ url: URL) {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let p = AVPlayer(url: url)
        player = p
        p.play()
    }
}

struct MobileVoiceBubblePlayer: View {
    let engine: ZaloEngine
    let conversationId: String
    let messageId: String
    let url: URL?
    let duration: Int
    let isMine: Bool

    @State private var isLoading = false
    @State private var isPlaying = false
    @State private var player: AVPlayer?
    @State private var endObserver: NSObjectProtocol?
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Button {
                    Task { await togglePlay() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .tint(isMine ? .white : .accentColor)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(isMine ? .white : .accentColor)
                    }
                }
                .buttonStyle(.plain)

                Image(systemName: "waveform")
                    .font(.headline)
                    .foregroundStyle(isMine ? .white.opacity(0.9) : .secondary)

                Text(formattedDuration(duration))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(isMine ? .white : .primary)
            }
            if let errorText {
                Text(errorText)
                    .font(.caption2)
                    .foregroundStyle(isMine ? .white.opacity(0.85) : .red)
            }
        }
        .onDisappear {
            stopPlayer()
        }
    }

    private func togglePlay() async {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }
        if let player {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
            _ = await player.seek(to: .zero)
            player.play()
            isPlaying = true
            return
        }

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        guard let url, let playURL = try? await MediaLoader.shared.localFile(for: url) else {
            errorText = "Không tải được tin nhắn thoại"
            return
        }

        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let avPlayer = AVPlayer(url: playURL)
        if let item = avPlayer.currentItem {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    isPlaying = false
                }
            }
        }
        player = avPlayer
        avPlayer.play()
        isPlaying = true
    }

    private func stopPlayer() {
        player?.pause()
        isPlaying = false
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }
}
